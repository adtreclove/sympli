import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/controllers/theme_controller.dart';
import 'package:sympli/controllers/today_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/day_phase.dart';
import 'package:sympli/models/symptom_entry.dart';
import 'package:sympli/widgets/checkin_card.dart';
import 'package:sympli/widgets/day_clock.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// Aktualisiert Uhrzeit & Zeiger jeweils zum Minutenwechsel.
  /// Nach Mitternacht werden die Einträge des neuen Tages geladen.
  void _scheduleTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      final previous = _now;
      setState(() => _now = DateTime.now());
      if (previous.day != _now.day) ref.invalidate(todayEntriesProvider);
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? _firstName() {
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    if (meta == null) return null;
    for (final key in const [
      'first_name',
      'name',
      'full_name',
      'display_name',
    ]) {
      final value = meta[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim().split(' ').first;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(todayEntriesProvider);
    final entries = entriesAsync.value ?? const <SymptomEntry>[];
    final name = _firstName();
    final greeting = DateLabels.greeting(_now);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => ref.refresh(todayEntriesProvider.future),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // unten Platz für FAB + Bottom-Nav (extendBody in der Shell)
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 150),
              children: [
                _Header(
                  dateLabel: DateLabels.dayHeader(_now),
                  greeting: name == null ? greeting : '$greeting, $name',
                ),
                const SizedBox(height: 22),
                _DayCard(entries: entries, now: _now),
                const SizedBox(height: 14),
                CheckInCard(now: _now),
                const SizedBox(height: 26),
                Text(
                  'HEUTE ERFASST',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 6),
                entriesAsync.when(
                  skipLoadingOnRefresh: true,
                  skipLoadingOnReload: true,
                  data: (list) => list.isEmpty
                      ? const _EmptyHint()
                      : _EntryList(entries: list),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (_, __) => _ErrorHint(
                    onRetry: () => ref.invalidate(todayEntriesProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header

class _Header extends ConsumerWidget {
  const _Header({required this.dateLabel, required this.greeting});

  final String dateLabel;
  final String greeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inkSoft = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11.5,
                  letterSpacing: 0.9,
                  color: inkSoft,
                ),
              ),
              const SizedBox(height: 6),
              Text(greeting, style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _CircleButton(
          icon: Icons.tune_rounded,
          tooltip: 'Einstellungen',
          onTap: () => context.push('/settings'),
        ),
        const SizedBox(width: 8),
        _CircleButton(
          icon: Icons.contrast_rounded,
          tooltip: 'Hell / Dunkel',
          onTap: () =>
              ref.read(themeModeProvider.notifier).toggle(theme.brightness),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        shape: CircleBorder(
          side: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: isDark ? AppColors.inkDark : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Dein Tag"-Karte

class _DayCard extends StatelessWidget {
  const _DayCard({required this.entries, required this.now});

  final List<SymptomEntry> entries;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final count = entries.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Dein Tag', style: theme.textTheme.titleMedium),
              ),
              Text(
                count == 1 ? '1 Eintrag' : '$count Einträge',
                style: theme.textTheme.bodySmall?.copyWith(color: faint),
              ),
            ],
          ),
          const SizedBox(height: 4),
          DayClock(entries: entries, now: now),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final phase in DayPhase.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Dot(color: phase.color(isDark), size: 7),
                    const SizedBox(width: 5),
                    Text(
                      phase.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liste "Heute erfasst"

class _EntryList extends StatelessWidget {
  const _EntryList({required this.entries});

  final List<SymptomEntry> entries;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? AppColors.borderDark : AppColors.border;

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: divider),
          _EntryRow(entry: entries[i]),
        ],
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final SymptomEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mono = theme.extension<AppMonoFont>()?.style ?? const TextStyle();
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final intensity = IntensityStyle.of(entry.intensity, isDark: isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          _Dot(
            color: DayPhase.fromTime(entry.occurredAt).color(isDark),
            size: 9,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.symptomName,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  DateLabels.time(entry.occurredAt),
                  style: mono.copyWith(fontSize: 12, color: faint),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: intensity.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              intensity.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: intensity.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        'Heute noch nichts erfasst. Tippe auf +, um einen Eintrag hinzuzufügen.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
      ),
    );
  }
}

class _ErrorHint extends StatelessWidget {
  const _ErrorHint({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Einträge konnten nicht geladen werden.',
              style: TextStyle(color: AppColors.coral, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Erneut')),
        ],
      ),
    );
  }
}
