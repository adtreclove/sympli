import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sympli/controllers/factors_controller.dart';
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/controllers/insights_controller.dart';
import 'package:sympli/controllers/user_settings_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/helpers/insights.dart';
import 'package:sympli/models/symptom_entry.dart';
import 'package:sympli/widgets/pattern_screen_widgets.dart';

/// Pattern: Changes in the last 7 days with possible reasons
/// Connections with factors, 30 days and week days
class PatternScreen extends ConsumerStatefulWidget {
  const PatternScreen({super.key});

  @override
  ConsumerState<PatternScreen> createState() => _PatternScreenState();
}

class _PatternScreenState extends ConsumerState<PatternScreen> {
  /// chosen symptom. null = most frequent
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
                  const Loading()
                else if (entriesAsync.hasError && !entriesAsync.hasValue)
                  ErrorRow(
                    text: 'Muster konnten nicht geladen werden.',
                    onRetry: () => ref.invalidate(recentEntriesProvider),
                  )
                else ...[
                  //  Summary
                  if (reportAsync.hasValue)
                    ..._insightSections(context, reportAsync.value!)
                  else if (reportAsync.hasError)
                    ErrorRow(
                      text:
                          'Auswertung nicht möglich. Ist das Datenbank-Update '
                          '(002_checkin_faktoren.sql) schon ausgeführt?',
                      onRetry: () => ref.invalidate(insightsProvider),
                    )
                  else
                    const Loading(),

                  if (settings != null && !settings.hasLocation) ...[
                    const SizedBox(height: 14),
                    HintCard(
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

                  // Charts / Diagrams
                  const SizedBox(height: 26),
                  SectionLabel('ÜBERBLICK'),
                  Card(
                    title: 'Verlauf · 30 Tage',
                    trailing: selected == null
                        ? null
                        : SymptomPicker(
                            selected: selected,
                            options: symptoms,
                            onSelected: (s) =>
                                setState(() => _symptomId = s.id),
                          ),
                    child: TrendChart(
                      values: dailyCounts(last30, 30, symptomId: selected?.id),
                      symptomName: selected?.name,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    title: 'Wochentag-Muster',
                    trailing: Text(
                      'letzte $historyDays Tage',
                      style: theme.textTheme.bodySmall?.copyWith(color: faint),
                    ),
                    child: WeekdayBars(counts: weekdayCounts(entries)),
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
      return [CollectingCard(report: report)];
    }

    final top = report.associations.isEmpty ? null : report.associations.first;
    final more = report.associations.skip(1).toList();

    return [
      // Veränderungen
      SectionLabel('VERÄNDERUNGEN · LETZTE 7 TAGE'),
      if (report.changes.isEmpty)
        HintCard(
          icon: Icons.check_circle_outline_rounded,
          title: 'Keine auffälligen Veränderungen',
          text:
              'Deine Symptome liegen im Rahmen der Wochen davor. Wir '
              'melden uns, wenn sich etwas deutlich ändert.',
        )
      else
        for (final (i, c) in report.changes.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          ChangeCard(change: c),
        ],
      const SizedBox(height: 26),

      // Zusammenhänge
      SectionLabel('MÖGLICHE ZUSAMMENHÄNGE'),
      if (top == null)
        HintCard(
          icon: Icons.hourglass_empty_rounded,
          title: 'Noch kein deutlicher Zusammenhang',
          text:
              'Je mehr Tage mit Check-in, desto genauer wird es – auch und '
              'gerade an Tagen ohne Symptome.',
        )
      else ...[
        AssociationHero(association: top),
        if (more.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
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
                  AssociationTile(association: a),
                ],
              ],
            ),
          ),
        ],
      ],
    ];
  }
}
