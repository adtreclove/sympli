import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/day_phase.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/models/symptom_entry.dart';
import 'package:sympli/widgets/course_sheets.dart';

/// Course: Entries in the last 7 or 30 days, with summary and timeline.
/// The summary can be filtered to a single symptom and exported.
class CourseScreen extends ConsumerStatefulWidget {
  const CourseScreen({super.key});

  @override
  ConsumerState<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends ConsumerState<CourseScreen> {
  int _days = 7;

  /// Active symptom filter. null = all symptoms.
  String? _symptomId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(recentEntriesProvider);
    final all = async.value ?? const <SymptomEntry>[];
    final inRange = entriesInLastDays(all, _days);

    // Options for the filter: symptoms of the current range by frequency.
    final symptoms = symptomsByFrequency(inRange);
    final counts = <String, int>{};
    for (final e in inRange) {
      counts[e.symptomId] = (counts[e.symptomId] ?? 0) + 1;
    }

    // Resolve the active filter. It stays active when switching to a range
    // without entries for it (shown with 0); it is only dropped if the
    // symptom no longer exists in the loaded data at all.
    SymptomRef? filter;
    if (_symptomId != null) {
      for (final e in all) {
        if (e.symptomId == _symptomId) {
          filter = SymptomRef(e.symptomId, e.symptomName);
          break;
        }
      }
      if (filter != null && !symptoms.contains(filter)) {
        symptoms.add(filter);
      }
    }

    final entries = filter == null
        ? inRange
        : inRange.where((e) => e.symptomId == filter!.id).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => ref.refresh(recentEntriesProvider.future),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 150),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Verlauf',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 26,
                        ),
                      ),
                    ),
                    _RangeToggle(
                      value: _days,
                      onChanged: (d) => setState(() => _days = d),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (async.isLoading && !async.hasValue)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (async.hasError && !async.hasValue)
                  _LoadError(
                    onRetry: () => ref.invalidate(recentEntriesProvider),
                  )
                else ...[
                  _SummaryCard(
                    entries: entries,
                    symptoms: symptoms,
                    counts: counts,
                    filter: filter,
                    onFilterChanged: (s) => setState(() => _symptomId = s?.id),
                  ),
                  const SizedBox(height: 18),
                  _Timeline(entries: entries, days: _days),
                  const SizedBox(height: 26),
                  _ExportButton(
                    onPressed: () => showExportSheet(
                      context,
                      allEntries: all,
                      initialDays: _days,
                      filter: filter,
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
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.borderDark : AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in const [7, 30])
            _ToggleOption(
              label: '$d Tage',
              selected: d == value,
              onTap: () => onChanged(d),
            ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  const _ToggleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.inkDark : AppColors.ink;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.surfaceDark : AppColors.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? ink : faint,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.entries,
    required this.symptoms,
    required this.counts,
    required this.filter,
    required this.onFilterChanged,
  });

  /// Entries of the range, already filtered if a filter is active.
  final List<SymptomEntry> entries;

  /// Selectable symptoms, most frequent first.
  final List<SymptomRef> symptoms;

  /// Number of entries per symptom id in the range (unfiltered).
  final Map<String, int> counts;
  final SymptomRef? filter;
  final ValueChanged<SymptomRef?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final avg = averageIntensity(entries);
    final big = theme.textTheme.headlineSmall?.copyWith(fontSize: 21);

    Widget stat(String value, String label, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: big?.copyWith(color: color),
        ),
        const SizedBox(height: 1),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
      ],
    );

    Widget divider() => Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: border,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: filter == null ? border : AppColors.accent),
      ),
      child: Row(
        children: [
          stat('${entries.length}', 'Einträge'),
          divider(),
          Expanded(
            child: _SymptomFilter(
              symptoms: symptoms,
              counts: counts,
              filter: filter,
              onChanged: onFilterChanged,
              valueStyle: big,
            ),
          ),
          divider(),
          stat(
            avg == null
                ? '–'
                : '${avg.toStringAsFixed(1).replaceAll('.', ',')} ø',
            'Intensität',
            color: avg == null ? null : AppColors.coral,
          ),
        ],
      ),
    );
  }
}

/// Middle stat of the summary: shows the most frequent symptom, and opens a
/// menu to filter the whole course to one symptom.
class _SymptomFilter extends StatelessWidget {
  const _SymptomFilter({
    required this.symptoms,
    required this.counts,
    required this.filter,
    required this.onChanged,
    required this.valueStyle,
  });

  final List<SymptomRef> symptoms;
  final Map<String, int> counts;
  final SymptomRef? filter;
  final ValueChanged<SymptomRef?> onChanged;
  final TextStyle? valueStyle;

  /// Menu value for "all symptoms" (PopupMenuButton ignores null values).
  static const _all = SymptomRef('', 'Alle Symptome');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.mittagDark : AppColors.accent;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final active = filter != null;

    final value = filter?.name ?? (symptoms.isEmpty ? '–' : symptoms.first.name);
    final label = active ? 'gefiltert' : 'häufigstes Symptom';

    return Row(
      children: [
        Expanded(
          child: PopupMenuButton<SymptomRef>(
            tooltip: 'Nach Symptom filtern',
            enabled: symptoms.isNotEmpty,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (s) => onChanged(s.id.isEmpty ? null : s),
            itemBuilder: (_) => [
              _menuItem(_all, null, selected: !active),
              const PopupMenuDivider(),
              for (final s in symptoms)
                _menuItem(s, counts[s.id] ?? 0, selected: s == filter),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle?.copyWith(color: active ? accent : null),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: active ? accent : null,
                          fontWeight: active ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    if (symptoms.isNotEmpty)
                      Icon(
                        Icons.expand_more_rounded,
                        size: 15,
                        color: active ? accent : faint,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Quick reset of the filter
        if (active)
          IconButton(
            tooltip: 'Filter entfernen',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.close_rounded, size: 18, color: faint),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }

  PopupMenuItem<SymptomRef> _menuItem(
    SymptomRef s,
    int? count, {
    required bool selected,
  }) {
    return PopupMenuItem(
      value: s,
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.name,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 12),
            Text(
              '$count×',
              style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ],
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
          ],
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries, required this.days});

  final List<SymptomEntry> entries;
  final int days;

  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const _labelWidth = 52.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mono = theme.extension<AppMonoFont>()?.style ?? const TextStyle();
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;
    final today = dayKey(DateTime.now());
    final rowHeight = days <= 7 ? 44.0 : 36.0;

    final byDay = <DateTime, List<SymptomEntry>>{};
    for (final e in entries) {
      byDay.putIfAbsent(dayKey(e.occurredAt), () => []).add(e);
    }

    return Column(
      children: [
        for (var i = 0; i < days; i++)
          Builder(
            builder: (context) {
              final day = addDays(today, -i);
              return SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _labelWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdays[day.weekday - 1],
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 13.5,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            '${day.day.toString().padLeft(2, '0')}.'
                            '${day.month.toString().padLeft(2, '0')}',
                            style: mono.copyWith(fontSize: 10.5, color: faint),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _DayTrack(entries: byDay[day] ?? const [])),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(width: _labelWidth),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _DayTrack.edgePadding,
                ),
                child: LayoutBuilder(
                  builder: (context, c) => SizedBox(
                    height: 14,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final h in const [0, 6, 12, 18, 24])
                          Positioned(
                            left: c.maxWidth * h / 24 - 10,
                            width: 20,
                            child: Text(
                              h.toString().padLeft(2, '0'),
                              textAlign: TextAlign.center,
                              style: mono.copyWith(fontSize: 10, color: faint),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DayTrack extends StatelessWidget {
  const _DayTrack({required this.entries});

  final List<SymptomEntry> entries;

  static const edgePadding = 8.0;

  /// Extra transparent area around each circle so it is easy to hit
  /// with a finger on touch devices.
  static const _hitSlop = 6.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = isDark ? AppColors.borderDark : const Color(0xFFE3E7E4);
    final surface = isDark ? AppColors.bgDark : AppColors.bg;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: edgePadding),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: 0,
                right: 0,
                child: Container(height: 1, color: line),
              ),
              for (final e in entries)
                Builder(
                  builder: (context) {
                    final t = e.occurredAt;
                    final x = w * (t.hour + t.minute / 60) / 24;
                    final d = 9.0 + e.intensity.clamp(1, 5) * 1.3;
                    final style = IntensityStyle.of(
                      e.intensity,
                      isDark: isDark,
                    );
                    return Positioned(
                      left: x - d / 2 - 2 - _hitSlop,
                      // Tooltip = hover info on desktop/web,
                      // tap = details sheet (works on smartphones too).
                      child: Tooltip(
                        message:
                            '${e.symptomName} · ${DateLabels.time(t)} · ${style.label}',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => showEntryDetailsSheet(
                              context,
                              entry: e,
                              dayEntries: entries,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(_hitSlop),
                              child: Container(
                                width: d + 4,
                                height: d + 4,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: DayPhase.fromTime(t).color(isDark),
                                  border: Border.all(color: surface, width: 2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Opens the export sheet (download of the summary).
class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.mittagDark : AppColors.accent;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.file_download_outlined, size: 20),
      label: const Text('Zusammenfassung exportieren'),
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.border),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Verlauf konnte nicht geladen werden.',
            style: TextStyle(color: AppColors.coral, fontSize: 13),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Erneut')),
      ],
    );
  }
}
