import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sympli/controllers/factors_controller.dart';
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/controllers/insights_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/helpers/factor_text.dart';
import 'package:sympli/helpers/insights.dart';
import 'package:sympli/models/symptom_entry.dart';

/// Muster: Veränderungen der letzten 7 Tage mit möglichen Gründen,
/// Zusammenhänge mit Faktoren, 30-Tage-Verlauf und Wochentage.
class PatternScreen extends ConsumerStatefulWidget {
  const PatternScreen({super.key});

  @override
  ConsumerState<PatternScreen> createState() => _PatternScreenState();
}

class _PatternScreenState extends ConsumerState<PatternScreen> {
  /// Im Verlauf-Diagramm gewähltes Symptom (null = häufigstes).
  String? _symptomId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final entriesAsync = ref.watch(recentEntriesProvider);
    final reportAsync = ref.watch(insightsProvider);
    final settings = ref.watch(userSettingsProvider).value;
    final entries = entriesAsync.value ?? const <SymptomEntry>[];

    final last30 = entriesInLastDays(entries, 30);
    final symptoms = symptomsByFrequency(last30);
    final selected = symptoms.isEmpty
        ? null
        : symptoms.firstWhere(
            (s) => s.id == _symptomId,
            orElse: () => symptoms.first,
          );

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async {
          ref.invalidate(factorLogsProvider);
          ref.invalidate(weatherProvider);
          await ref.refresh(recentEntriesProvider.future);
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 150),
              children: [
                Text(
                  'Muster',
                  style: theme.textTheme.headlineSmall?.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 2),
                Text(
                  'Auffälligkeiten aus deinen Einträgen',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 20),
                if (entriesAsync.isLoading && !entriesAsync.hasValue)
                  const _Loading()
                else if (entriesAsync.hasError && !entriesAsync.hasValue)
                  _ErrorRow(
                    text: 'Muster konnten nicht geladen werden.',
                    onRetry: () => ref.invalidate(recentEntriesProvider),
                  )
                else ...[
                  // --- Auswertung ------------------------------------------
                  if (reportAsync.hasValue)
                    ..._insightSections(context, reportAsync.value!)
                  else if (reportAsync.hasError)
                    _ErrorRow(
                      text:
                          'Auswertung nicht möglich. Ist das Datenbank-Update '
                          '(002_checkin_faktoren.sql) schon ausgeführt?',
                      onRetry: () => ref.invalidate(insightsProvider),
                    )
                  else
                    const _Loading(),

                  if (settings != null && !settings.hasLocation) ...[
                    const SizedBox(height: 14),
                    _HintCard(
                      icon: Icons.cloud_outlined,
                      title: 'Wetter einbeziehen',
                      text:
                          'Luftdruckwechsel lösen bei vielen Menschen '
                          'Beschwerden aus. Leg deine Stadt fest, dann '
                          'prüfen wir auch das.',
                      action: 'Ort festlegen',
                      onTap: () => context.push('/settings'),
                    ),
                  ],

                  // --- Diagramme -------------------------------------------
                  const SizedBox(height: 26),
                  _SectionLabel('ÜBERBLICK'),
                  _Card(
                    title: 'Verlauf · 30 Tage',
                    trailing: selected == null
                        ? null
                        : _SymptomPicker(
                            selected: selected,
                            options: symptoms,
                            onSelected: (s) =>
                                setState(() => _symptomId = s.id),
                          ),
                    child: _TrendChart(
                      values: dailyCounts(
                        last30,
                        30,
                        symptomId: selected?.id,
                      ),
                      symptomName: selected?.name,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    title: 'Wochentag-Muster',
                    trailing: Text(
                      'letzte $historyDays Tage',
                      style: theme.textTheme.bodySmall?.copyWith(color: faint),
                    ),
                    child: _WeekdayBars(counts: weekdayCounts(entries)),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Diese Hinweise zeigen mögliche Zusammenhänge, keine '
                      'Ursachen. Sie ersetzen keine ärztliche Diagnose und '
                      'sind kein medizinischer Rat.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        height: 1.45,
                        color: faint,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _insightSections(BuildContext context, InsightReport report) {
    final theme = Theme.of(context);

    if (!report.enoughData) {
      return [_CollectingCard(report: report)];
    }

    final top = report.associations.isEmpty ? null : report.associations.first;
    final more = report.associations.skip(1).toList();

    return [
      // Veränderungen
      _SectionLabel('VERÄNDERUNGEN · LETZTE 7 TAGE'),
      if (report.changes.isEmpty)
        _HintCard(
          icon: Icons.check_circle_outline_rounded,
          title: 'Keine auffälligen Veränderungen',
          text:
              'Deine Symptome liegen im Rahmen der Wochen davor. Wir '
              'melden uns, wenn sich etwas deutlich ändert.',
        )
      else
        for (final (i, c) in report.changes.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _ChangeCard(change: c),
        ],
      const SizedBox(height: 26),

      // Zusammenhänge
      _SectionLabel('MÖGLICHE ZUSAMMENHÄNGE'),
      if (top == null)
        _HintCard(
          icon: Icons.hourglass_empty_rounded,
          title: 'Noch kein deutlicher Zusammenhang',
          text:
              'Je mehr Tage mit Check-in, desto genauer wird es – auch und '
              'gerade an Tagen ohne Symptome.',
        )
      else ...[
        _AssociationHero(association: top),
        if (more.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Card(
            title: 'Weitere Hinweise',
            child: Column(
              children: [
                for (final (i, a) in more.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 20,
                      color: theme.brightness == Brightness.dark
                          ? AppColors.borderDark
                          : AppColors.border,
                    ),
                  _AssociationTile(association: a),
                ],
              ],
            ),
          ),
        ],
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// Bausteine

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 0.9,
      ),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: AppColors.coral, fontSize: 13),
        ),
      ),
      TextButton(onPressed: onRetry, child: const Text('Erneut')),
    ],
  );
}

/// Dunkle Karte – wie im Mockup.
class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2321) : AppColors.ink,
        borderRadius: BorderRadius.circular(22),
        border: isDark ? Border.all(color: AppColors.borderDark) : null,
      ),
      child: child,
    );
  }
}

const _onDark = Color(0xFFF4F7F5);

/// Solange zu wenig Tage da sind: Fortschritt + warum der Check-in zählt.
class _CollectingCard extends StatelessWidget {
  const _CollectingCard({required this.report});

  final InsightReport report;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = isDark ? AppColors.morgenDark : AppColors.amber;
    final progress = (report.observedDays / targetObservedDays).clamp(0.0, 1.0);

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 17, color: amber),
              const SizedBox(width: 8),
              Text(
                'WIR SAMMELN NOCH',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Ab etwa 2–3 Wochen erkennen wir Veränderungen und mögliche '
            'Zusammenhänge.',
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: _onDark,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: amber,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${report.observedDays} von $targetObservedDays Tagen · '
            'davon ${report.checkInDays} mit Check-in',
            style: TextStyle(
              fontSize: 11.5,
              color: _onDark.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tipp: Mach den Check-in jeden Tag – auch an guten Tagen. Nur so '
            'können wir gute und schlechte Tage vergleichen.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: _onDark.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Veränderung mit möglichen Gründen.
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});

  final SymptomChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;
    final color = change.isWorse
        ? (isDark ? const Color(0xFFF27A60) : AppColors.coral)
        : (isDark ? AppColors.mittagDark : AppColors.accent);
    final icon = switch (change.kind) {
      ChangeKind.more || ChangeKind.newSymptom => Icons.trending_up_rounded,
      ChangeKind.less => Icons.trending_down_rounded,
      ChangeKind.stronger => Icons.arrow_upward_rounded,
      ChangeKind.milder => Icons.arrow_downward_rounded,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(change.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      change.detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (change.reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              change.isWorse
                  ? 'IN DIESER ZEIT WAR ANDERS'
                  : 'DAS KÖNNTE GEHOLFEN HABEN',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                letterSpacing: 0.8,
                color: faint,
              ),
            ),
            const SizedBox(height: 6),
            for (final r in change.reasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(factorIcon(r.type), size: 17, color: inkSoft),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${r.type.name}  ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: r.detail,
                              style: TextStyle(color: inkSoft),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (r.matchesPattern)
                      Tooltip(
                        message:
                            'Dieser Faktor hing bei dir schon früher mit '
                            '${change.symptomName} zusammen.',
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            'passt zum Muster',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Bei deinen Check-in-Werten war in dieser Zeit nichts '
              'auffällig anders.',
              style: theme.textTheme.bodySmall?.copyWith(color: faint),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stärkster Zusammenhang – dunkle Karte mit zwei Balken (wie im Mockup).
class _AssociationHero extends StatelessWidget {
  const _AssociationHero({required this.association});

  final Association association;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = isDark ? AppColors.morgenDark : AppColors.amber;
    final muted = _onDark.withValues(alpha: 0.55);
    final a = association;
    final s = a.sentence;

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 17, color: amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MÖGLICHER ZUSAMMENHANG',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: amber,
                  ),
                ),
              ),
              _StrengthChip(label: a.strengthLabel, strong: a.isStrong),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 16.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: _onDark,
              ),
              children: [
                TextSpan(text: s.before),
                TextSpan(
                  text: s.highlight,
                  style: TextStyle(color: amber),
                ),
                TextSpan(text: s.after),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MiniBar(
                fraction: 1,
                color: amber,
                label: a.sideLabel,
                tooltip:
                    '${(a.rateSide * 100).round()} % dieser Tage mit '
                    '${a.symptomName}',
              ),
              const SizedBox(width: 20),
              _MiniBar(
                fraction: a.rateSide == 0 ? 0 : a.rateOther / a.rateSide,
                color: _onDark.withValues(alpha: 0.35),
                label: a.otherLabel,
                tooltip:
                    '${(a.rateOther * 100).round()} % dieser Tage mit '
                    '${a.symptomName}',
              ),
              const Spacer(),
              Text(
                'Basierend auf\n${a.daysConsidered} Tagen',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, height: 1.4, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StrengthChip extends StatelessWidget {
  const _StrengthChip({required this.label, required this.strong});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: strong
        ? 'Der Unterschied ist groß und stützt sich auf genug Tage.'
        : 'Auffällig, aber noch auf wenigen Tagen – kann sich ändern.',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: strong ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: _onDark.withValues(alpha: strong ? 0.95 : 0.7),
        ),
      ),
    ),
  );
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({
    required this.fraction,
    required this.color,
    required this.label,
    required this.tooltip,
  });

  final double fraction;
  final Color color;
  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    const h = 48.0;
    return Tooltip(
      message: tooltip,
      child: Column(
        children: [
          Container(
            width: 36,
            height: h,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Container(
              height: math.max(6.0, h * fraction.clamp(0.0, 1.0)),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Weitere Zusammenhänge als kompakte Zeile.
class _AssociationTile extends StatelessWidget {
  const _AssociationTile({required this.association});

  final Association association;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;
    final amber = isDark ? AppColors.morgenDark : const Color(0xFFB86E0B);
    final a = association;
    final s = a.sentence;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(factorIcon(a.type), size: 18, color: inkSoft),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  children: [
                    TextSpan(text: s.before),
                    TextSpan(
                      text: s.highlight,
                      style: TextStyle(
                        color: amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: s.after),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${a.strengthLabel} · ${a.daysConsidered} Tage',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Helle Hinweis-Karte, optional mit Knopf.
class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.mittagDark : AppColors.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                if (action != null && onTap != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(action!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weiße Karten

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Chip mit dem gewählten Symptom; Tippen öffnet die Auswahl.
class _SymptomPicker extends StatelessWidget {
  const _SymptomPicker({
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final SymptomRef selected;
  final List<SymptomRef> options;
  final ValueChanged<SymptomRef> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.mittagDark : AppColors.accent;
    final bg = isDark
        ? AppColors.mittagDark.withValues(alpha: 0.14)
        : AppColors.accentSoft;

    return PopupMenuButton<SymptomRef>(
      tooltip: 'Symptom wählen',
      enabled: options.length > 1,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        for (final s in options)
          PopupMenuItem(
            value: s,
            child: Text(
              s.name,
              style: TextStyle(
                fontWeight: s == selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.fromLTRB(11, 5, 8, 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (options.length > 1)
              Icon(Icons.expand_more_rounded, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Linien-Diagramm: Einträge pro Tag

class _TrendChart extends StatefulWidget {
  const _TrendChart({required this.values, required this.symptomName});

  final List<int> values;
  final String? symptomName;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int? _hover;

  void _updateHover(Offset local, double width) {
    final n = widget.values.length;
    final i = ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mono = theme.extension<AppMonoFont>()?.style ?? const TextStyle();
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final line = isDark ? AppColors.mittagDark : AppColors.accent;
    final n = widget.values.length;

    String hoverLabel(int i) {
      final day = addDays(dayKey(DateTime.now()), -(n - 1 - i));
      final v = widget.values[i];
      return '${day.day}.${day.month}. · $v ${v == 1 ? 'Eintrag' : 'Einträge'}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: _hover == null
              ? null
              : Text(
                  hoverLabel(_hover!),
                  style: mono.copyWith(fontSize: 11, color: faint),
                ),
        ),
        LayoutBuilder(
          builder: (context, c) => MouseRegion(
            onHover: (e) => _updateHover(e.localPosition, c.maxWidth),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              // nur horizontal, damit senkrechtes Scrollen weiter geht
              onTapDown: (d) => _updateHover(d.localPosition, c.maxWidth),
              onHorizontalDragStart: (d) =>
                  _updateHover(d.localPosition, c.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _updateHover(d.localPosition, c.maxWidth),
              onHorizontalDragEnd: (_) => setState(() => _hover = null),
              child: SizedBox(
                height: 92,
                width: c.maxWidth,
                child: CustomPaint(
                  painter: _TrendPainter(
                    values: widget.values,
                    lineColor: line,
                    gridColor: isDark
                        ? AppColors.borderDark
                        : const Color(0xFFEDF0EE),
                    surface: isDark ? AppColors.surfaceDark : AppColors.surface,
                    hover: _hover,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('vor 30 T.', style: mono.copyWith(fontSize: 10, color: faint)),
            Text('heute', style: mono.copyWith(fontSize: 10, color: faint)),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.surface,
    required this.hover,
  });

  final List<int> values;
  final Color lineColor;
  final Color gridColor;
  final Color surface;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const topPad = 6.0;
    final h = size.height - topPad;
    final maxV = math.max(values.reduce(math.max), 1);

    // dezente Gitterlinien
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var g = 0; g <= 2; g++) {
      final y = topPad + h * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    Offset pt(int i) => Offset(
      values.length == 1 ? 0 : size.width * i / (values.length - 1),
      topPad + h - h * values[i] / maxV,
    );

    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }

    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = lineColor.withValues(alpha: 0.08));

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Punkt am heutigen Tag bzw. am berührten Tag
    final marked = hover ?? values.length - 1;
    final p = pt(marked);
    if (hover != null) {
      canvas.drawLine(
        Offset(p.dx, topPad),
        Offset(p.dx, size.height),
        Paint()
          ..color = lineColor.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(p, 6, Paint()..color = surface);
    canvas.drawCircle(p, 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values ||
      old.hover != hover ||
      old.lineColor != lineColor ||
      old.surface != surface;
}

// ---------------------------------------------------------------------------
// Balken pro Wochentag

class _WeekdayBars extends StatelessWidget {
  const _WeekdayBars({required this.counts});

  final List<int> counts;

  static const _labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.mittagDark : AppColors.accent;
    final rest = isDark ? AppColors.borderDark : AppColors.surface2;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final maxV = counts.reduce(math.max);
    const minH = 14.0;
    const maxH = 64.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message:
                    '${_labels[i]}: ${counts[i]} ${counts[i] == 1 ? 'Eintrag' : 'Einträge'}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      height: maxV == 0
                          ? minH
                          : minH + (maxH - minH) * counts[i] / maxV,
                      decoration: BoxDecoration(
                        color: maxV > 0 && counts[i] == maxV ? accent : rest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: maxV > 0 && counts[i] == maxV
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: maxV > 0 && counts[i] == maxV ? accent : faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
