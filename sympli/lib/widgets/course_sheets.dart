import 'package:flutter/material.dart';
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/course_report.dart';
import 'package:sympli/helpers/day_phase.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/models/symptom_entry.dart';
import 'package:sympli/services/file_download.dart';

// ==========================================================================
// Shared sheet frame
// ==========================================================================

/// Rounded bottom sheet container with drag handle, matching the check-in sheet.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.borderDark : AppColors.border;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => child,
  );
}

// ==========================================================================
// Entry details (tap on a circle in the timeline)
// ==========================================================================

/// Shows the details of [entry] and lets the user switch between all
/// entries of the same day ([dayEntries]). Needed for touch devices,
/// where the hover tooltip is not available.
Future<void> showEntryDetailsSheet(
  BuildContext context, {
  required SymptomEntry entry,
  required List<SymptomEntry> dayEntries,
}) {
  return _showSheet<void>(
    context,
    _EntryDetailsSheet(initial: entry, dayEntries: dayEntries),
  );
}

class _EntryDetailsSheet extends StatefulWidget {
  const _EntryDetailsSheet({required this.initial, required this.dayEntries});

  final SymptomEntry initial;
  final List<SymptomEntry> dayEntries;

  @override
  State<_EntryDetailsSheet> createState() => _EntryDetailsSheetState();
}

class _EntryDetailsSheetState extends State<_EntryDetailsSheet> {
  late SymptomEntry _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mono = theme.extension<AppMonoFont>()?.style ?? const TextStyle();
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final faint = isDark ? AppColors.inkSoftDark : AppColors.inkFaint;

    final e = _selected;
    final phase = DayPhase.fromTime(e.occurredAt);
    final style = IntensityStyle.of(e.intensity, isDark: isDark);
    final note = e.note?.trim();

    // Chronological list of the day's entries
    final others = [...widget.dayEntries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateLabels.dayHeader(e.occurredAt),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: phase.color(isDark),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.symptomName,
                  style: theme.textTheme.headlineSmall?.copyWith(fontSize: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.schedule_rounded,
                label: '${DateLabels.time(e.occurredAt)} Uhr',
                textStyle: mono,
              ),
              _InfoChip(
                label: phase.label,
                dotColor: phase.color(isDark),
              ),
              _InfoChip(
                label: '${e.intensity}/5 · ${style.label}',
                foreground: style.foreground,
                background: style.background,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('INTENSITÄT', style: theme.textTheme.labelSmall),
          const SizedBox(height: 6),
          _IntensityMeter(value: e.intensity, color: style.foreground),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('NOTIZ', style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(note, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          ],
          if (others.length > 1) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: border),
            const SizedBox(height: 14),
            Text(
              'ALLE EINTRÄGE AN DIESEM TAG (${others.length})',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 6),
            for (final o in others)
              _DayEntryRow(
                entry: o,
                selected: identical(o, e) || o.id == e.id,
                faint: faint,
                mono: mono,
                onTap: () => setState(() => _selected = o),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    this.icon,
    this.dotColor,
    this.foreground,
    this.background,
    this.textStyle,
  });

  final String label;
  final IconData? icon;
  final Color? dotColor;
  final Color? foreground;
  final Color? background;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg =
        foreground ?? (isDark ? AppColors.inkDark : AppColors.ink);
    final bg = background ?? (isDark ? AppColors.borderDark : AppColors.surface2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: (textStyle ?? const TextStyle()).copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Five segments, filled up to [value].
class _IntensityMeter extends StatelessWidget {
  const _IntensityMeter({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final empty = isDark ? AppColors.borderDark : AppColors.surface2;

    return Row(
      children: [
        for (var i = 1; i <= 5; i++) ...[
          if (i > 1) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: i <= value ? color : empty,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayEntryRow extends StatelessWidget {
  const _DayEntryRow({
    required this.entry,
    required this.selected,
    required this.faint,
    required this.mono,
    required this.onTap,
  });

  final SymptomEntry entry;
  final bool selected;
  final Color faint;
  final TextStyle mono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final style = IntensityStyle.of(entry.intensity, isDark: isDark);
    final phase = DayPhase.fromTime(entry.occurredAt);
    final highlight = isDark ? AppColors.borderDark : AppColors.bg;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? highlight : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                DateLabels.time(entry.occurredAt),
                style: mono.copyWith(fontSize: 12, color: faint),
              ),
            ),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: phase.color(isDark),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.symptomName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '${entry.intensity}/5',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: style.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================================
// Export
// ==========================================================================

/// Lets the user pick the period (and whether to keep the active symptom
/// filter) and downloads the summary as an HTML file.
Future<void> showExportSheet(
  BuildContext context, {
  required List<SymptomEntry> allEntries,
  required int initialDays,
  SymptomRef? filter,
}) {
  return _showSheet<void>(
    context,
    _ExportSheet(
      allEntries: allEntries,
      initialDays: initialDays,
      filter: filter,
    ),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({
    required this.allEntries,
    required this.initialDays,
    required this.filter,
  });

  final List<SymptomEntry> allEntries;
  final int initialDays;
  final SymptomRef? filter;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  static const _periods = [7, 30, historyDays];

  late int _days = widget.initialDays;
  late bool _onlyFilter = widget.filter != null;
  bool _busy = false;

  List<SymptomEntry> get _selection {
    final inRange = entriesInLastDays(widget.allEntries, _days);
    final f = widget.filter;
    if (!_onlyFilter || f == null) return inRange;
    return inRange.where((e) => e.symptomId == f.id).toList();
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final symptomName = _onlyFilter ? widget.filter?.name : null;

    final html = CourseReport.buildHtml(
      entries: _selection,
      days: _days,
      symptomName: symptomName,
    );
    final ok = await downloadFile(
      fileName: CourseReport.fileName(days: _days, symptomName: symptomName),
      content: html,
      mimeType: 'text/html;charset=utf-8',
    );

    if (!mounted) return;
    navigator.pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Zusammenfassung wurde heruntergeladen.'
              : 'Export ist derzeit nur in der Web-Version verfügbar.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final count = _selection.length;
    final filter = widget.filter;

    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Zusammenfassung exportieren',
            style: theme.textTheme.headlineSmall?.copyWith(fontSize: 21),
          ),
          const SizedBox(height: 4),
          Text(
            'Mit Kennzahlen, Übersicht je Symptom, Verteilung nach Tageszeit '
            'und Wochentag sowie allen Einträgen Tag für Tag – inklusive '
            'Uhrzeit, Intensität und Notizen.',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 18),
          Text('ZEITRAUM', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final d in _periods)
                ChoiceChip(
                  label: Text('$d Tage'),
                  selected: d == _days,
                  showCheckmark: false,
                  selectedColor: AppColors.accent,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: d == _days ? Colors.white : theme.colorScheme.onSurface,
                  ),
                  side: BorderSide(color: d == _days ? AppColors.accent : border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  onSelected: (_) => setState(() => _days = d),
                ),
            ],
          ),
          if (filter != null) ...[
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _onlyFilter,
              activeTrackColor: AppColors.accent,
              title: Text(
                'Nur „${filter.name}“',
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
              ),
              subtitle: Text(
                'Aktuellen Filter übernehmen',
                style: theme.textTheme.bodySmall,
              ),
              onChanged: (v) => setState(() => _onlyFilter = v),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            count == 1 ? '1 Eintrag im Zeitraum' : '$count Einträge im Zeitraum',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_download_outlined, size: 20),
            label: const Text('Herunterladen'),
          ),
          const SizedBox(height: 8),
          Text(
            'Die Datei öffnet sich im Browser und lässt sich dort drucken '
            'oder als PDF speichern.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
