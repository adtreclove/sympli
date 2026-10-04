import 'dart:ui' show Color;

import 'package:sympli/helpers/app_theme.dart';
import 'package:sympli/helpers/day_phase.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/models/symptom_entry.dart';

/// Builds the downloadable summary of the course ("Verlauf") as a
/// self-contained, print-friendly HTML document (no external resources).
///
/// The file can be opened in any browser and saved as PDF via "Print".
class CourseReport {
  CourseReport._();

  static const _weekdaysLong = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];
  static const _weekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  /// Suggested file name, e.g. `sympli-zusammenfassung_2026-10-04_30-tage.html`.
  static String fileName({required int days, String? symptomName, DateTime? now}) {
    final today = isoDate(now ?? DateTime.now());
    final suffix = symptomName == null ? '' : '_${_slug(symptomName)}';
    return 'sympli-zusammenfassung_${today}_$days-tage$suffix.html';
  }

  /// [entries] must already be limited to the last [days] days and, if a
  /// filter is active, to the symptom named [symptomName].
  static String buildHtml({
    required List<SymptomEntry> entries,
    required int days,
    String? symptomName,
    DateTime? now,
  }) {
    final created = now ?? DateTime.now();
    final today = dayKey(created);
    final start = addDays(today, -(days - 1));

    // Chronological order, so entries within a day read top to bottom.
    final sorted = [...entries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    final byDay = <DateTime, List<SymptomEntry>>{};
    for (final e in sorted) {
      byDay.putIfAbsent(dayKey(e.occurredAt), () => []).add(e);
    }

    final b = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="de"><head><meta charset="utf-8">')
      ..writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
      )
      ..writeln('<title>sympli · Zusammenfassung ${_date(start)} – ${_date(today)}</title>')
      ..writeln('<style>$_css</style></head><body><main>');

    // ---------- Header ----------
    b
      ..writeln('<header>')
      ..writeln('<div class="brand">sympli</div>')
      ..writeln('<h1>Symptom-Zusammenfassung</h1>')
      ..writeln(
        '<p class="meta">Zeitraum: <b>${_date(start)} – ${_date(today)}</b> '
        '($days Tage)'
        '${symptomName == null ? '' : ' · Filter: <b>${_esc(symptomName)}</b>'}'
        '<br>Erstellt am ${_date(created)} um ${DateLabels.time(created)} Uhr</p>',
      )
      ..writeln(
        '<button class="no-print" onclick="window.print()">'
        'Drucken / als PDF speichern</button>',
      )
      ..writeln('</header>');

    // ---------- Key figures ----------
    final avg = averageIntensity(sorted);
    final maxIntensity = sorted.isEmpty
        ? null
        : sorted.map((e) => e.intensity).reduce((a, c) => a > c ? a : c);
    final top = symptomsByFrequency(sorted);
    final daysWithEntries = byDay.length;

    b
      ..writeln('<section class="kpis">')
      ..writeln(_kpi('${sorted.length}', 'Einträge'))
      ..writeln(_kpi('$daysWithEntries / $days', 'Tage mit Symptomen'))
      ..writeln(
        _kpi(
          avg == null ? '–' : '${_num(avg)} / 5',
          'ø Intensität',
          accent: avg != null,
        ),
      )
      ..writeln(_kpi(maxIntensity == null ? '–' : '$maxIntensity / 5', 'stärkste Intensität'))
      ..writeln(
        _kpi(
          top.isEmpty ? '–' : _esc(top.first.name),
          symptomName == null ? 'häufigstes Symptom' : 'Symptom',
        ),
      )
      ..writeln('</section>');

    if (sorted.isEmpty) {
      b.writeln(
        '<p class="empty">Im gewählten Zeitraum wurden keine Einträge erfasst.</p>',
      );
    } else {
      _writeSymptomTable(b, sorted);
      _writeDistributions(b, sorted);
    }

    // ---------- Day overview ----------
    b
      ..writeln('<h2>Tagesübersicht</h2>')
      ..writeln(
        '<p class="hint">Jeder Punkt ist ein Eintrag auf der 24-Stunden-Achse. '
        'Größe = Intensität, Farbe = Tageszeit '
        '${_legendDot(DayPhase.morgen)} Morgen '
        '${_legendDot(DayPhase.mittag)} Mittag '
        '${_legendDot(DayPhase.abend)} Abend '
        '${_legendDot(DayPhase.nacht)} Nacht.</p>',
      );

    for (var i = 0; i < days; i++) {
      final day = addDays(today, -i);
      _writeDay(b, day, byDay[day] ?? const []);
    }

    // ---------- Footer ----------
    b
      ..writeln(
        '<footer>Diese Zusammenfassung basiert ausschließlich auf deinen eigenen '
        'Einträgen in sympli. Sie zeigt mögliche Muster, keine Ursachen, und '
        'ersetzt keine ärztliche Diagnose.</footer>',
      )
      ..writeln('</main></body></html>');

    return b.toString();
  }

  // ------------------------------------------------------------------------
  // Sections
  // ------------------------------------------------------------------------

  /// One row per symptom: count, days, average/max intensity, typical phase.
  static void _writeSymptomTable(StringBuffer b, List<SymptomEntry> entries) {
    final groups = <String, List<SymptomEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.symptomId, () => []).add(e);
    }

    b
      ..writeln('<h2>Symptome im Überblick</h2>')
      ..writeln('<table class="symptoms"><thead><tr>')
      ..writeln(
        '<th>Symptom</th><th class="r">Anzahl</th><th class="r">Tage</th>'
        '<th class="r">ø Int.</th><th class="r">max</th>'
        '<th>meist</th><th>zuletzt</th>',
      )
      ..writeln('</tr></thead><tbody>');

    for (final ref in symptomsByFrequency(entries)) {
      final list = groups[ref.id]!;
      final dayCount = list.map((e) => dayKey(e.occurredAt)).toSet().length;
      final avg = averageIntensity(list)!;
      final max = list.map((e) => e.intensity).reduce((a, c) => a > c ? a : c);
      final last = list.last.occurredAt; // list is sorted ascending

      b.writeln(
        '<tr><td><b>${_esc(ref.name)}</b></td>'
        '<td class="r">${list.length}</td>'
        '<td class="r">$dayCount</td>'
        '<td class="r">${_num(avg)}</td>'
        '<td class="r">$max</td>'
        '<td>${_dominantPhase(list).label}</td>'
        '<td>${_date(last)}, ${DateLabels.time(last)}</td></tr>',
      );
    }
    b.writeln('</tbody></table>');
  }

  /// Distribution by time of day, weekday and intensity as simple bars.
  static void _writeDistributions(StringBuffer b, List<SymptomEntry> entries) {
    final phaseCounts = {for (final p in DayPhase.values) p: 0};
    for (final e in entries) {
      final p = DayPhase.fromTime(e.occurredAt);
      phaseCounts[p] = phaseCounts[p]! + 1;
    }
    final weekday = weekdayCounts(entries);
    final intensity = List<int>.filled(5, 0);
    for (final e in entries) {
      intensity[e.intensity.clamp(1, 5) - 1]++;
    }

    b
      ..writeln('<div class="grid3">')
      ..writeln('<div class="box"><h3>Tageszeit</h3>');
    final phaseMax = phaseCounts.values.fold<int>(1, (m, v) => v > m ? v : m);
    for (final p in DayPhase.values) {
      b.writeln(_bar(p.label, phaseCounts[p]!, phaseMax, _hex(p.color(false))));
    }
    b
      ..writeln('</div>')
      ..writeln('<div class="box"><h3>Wochentag</h3>');
    final wdMax = weekday.fold<int>(1, (m, v) => v > m ? v : m);
    for (var i = 0; i < 7; i++) {
      b.writeln(_bar(_weekdaysShort[i], weekday[i], wdMax, _hex(AppColors.accent)));
    }
    b
      ..writeln('</div>')
      ..writeln('<div class="box"><h3>Intensität</h3>');
    final intMax = intensity.fold<int>(1, (m, v) => v > m ? v : m);
    for (var i = 5; i >= 1; i--) {
      final style = IntensityStyle.of(i, isDark: false);
      b.writeln(
        _bar('$i · ${style.label}', intensity[i - 1], intMax, _hex(style.foreground)),
      );
    }
    b.writeln('</div></div>');
  }

  /// A single day: heading, mini timeline and a table with every entry.
  static void _writeDay(StringBuffer b, DateTime day, List<SymptomEntry> list) {
    final head =
        '<span class="wd">${_weekdaysLong[day.weekday - 1]}</span> '
        '<span class="dt">${_date(day)}</span>';

    if (list.isEmpty) {
      b.writeln(
        '<div class="day day-empty">$head<span class="sum">keine Einträge</span></div>',
      );
      return;
    }

    final avg = averageIntensity(list)!;
    final max = list.map((e) => e.intensity).reduce((a, c) => a > c ? a : c);

    b
      ..writeln('<section class="day">')
      ..writeln(
        '<div class="day-head">$head<span class="sum">'
        '${list.length} ${list.length == 1 ? 'Eintrag' : 'Einträge'} · '
        'ø ${_num(avg)} · max $max</span></div>',
      )
      ..writeln(_timelineSvg(list))
      ..writeln('<table class="entries"><tbody>');

    for (final e in list) {
      final style = IntensityStyle.of(e.intensity, isDark: false);
      final phase = DayPhase.fromTime(e.occurredAt);
      final note = e.note?.trim();
      b.writeln(
        '<tr><td class="time">${DateLabels.time(e.occurredAt)}</td>'
        '<td class="phase">${_legendDot(phase)} ${phase.label}</td>'
        '<td class="name"><b>${_esc(e.symptomName)}</b>'
        '${note == null || note.isEmpty ? '' : '<div class="note">${_esc(note)}</div>'}'
        '</td>'
        '<td class="int"><span class="badge" style="color:${_hex(style.foreground)};'
        'background:${_hex(style.background)}">${e.intensity}/5 · ${style.label}</span></td></tr>',
      );
    }
    b.writeln('</tbody></table></section>');
  }

  /// Inline SVG copy of the app's day track (0–24 h axis with dots).
  static String _timelineSvg(List<SymptomEntry> list) {
    const w = 480.0;
    const h = 30.0;
    const pad = 10.0;
    const inner = w - 2 * pad;
    const y = 12.0;

    final s = StringBuffer(
      '<svg class="track" viewBox="0 0 $w $h" preserveAspectRatio="none" '
      'role="img" aria-label="Zeitleiste">',
    )..write('<line x1="$pad" y1="$y" x2="${w - pad}" y2="$y" stroke="#E3E7E4" stroke-width="1"/>');

    for (final hour in const [0, 6, 12, 18, 24]) {
      final x = pad + inner * hour / 24;
      s
        ..write('<line x1="$x" y1="${y - 3}" x2="$x" y2="${y + 3}" stroke="#C9D0CC" stroke-width="1"/>')
        ..write(
          '<text x="$x" y="${h - 1}" text-anchor="middle" font-size="8" '
          'fill="#8B9793">${hour.toString().padLeft(2, '0')}</text>',
        );
    }
    for (final e in list) {
      final t = e.occurredAt;
      final x = pad + inner * (t.hour + t.minute / 60) / 24;
      final r = 3.0 + e.intensity.clamp(1, 5) * 0.8;
      s.write(
        '<circle cx="${x.toStringAsFixed(1)}" cy="$y" r="${r.toStringAsFixed(1)}" '
        'fill="${_hex(DayPhase.fromTime(t).color(false))}" stroke="#fff" stroke-width="1.5">'
        '<title>${_esc(e.symptomName)} · ${DateLabels.time(t)}</title></circle>',
      );
    }
    s.write('</svg>');
    return s.toString();
  }

  // ------------------------------------------------------------------------
  // Small helpers
  // ------------------------------------------------------------------------

  static String _kpi(String value, String label, {bool accent = false}) =>
      '<div class="kpi"><div class="v${accent ? ' accent' : ''}">$value</div>'
      '<div class="l">$label</div></div>';

  static String _bar(String label, int value, int max, String color) {
    final pct = max == 0 ? 0 : (value / max * 100).round();
    return '<div class="bar"><span class="bl">$label</span>'
        '<span class="bt"><span class="bf" style="width:$pct%;background:$color"></span></span>'
        '<span class="bv">$value</span></div>';
  }

  static String _legendDot(DayPhase p) =>
      '<span class="dot" style="background:${_hex(p.color(false))}"></span>';

  /// Time of day with the most entries (ties: earlier phase wins).
  static DayPhase _dominantPhase(List<SymptomEntry> list) {
    final counts = {for (final p in DayPhase.values) p: 0};
    for (final e in list) {
      final p = DayPhase.fromTime(e.occurredAt);
      counts[p] = counts[p]! + 1;
    }
    return DayPhase.values.reduce((a, c) => counts[c]! > counts[a]! ? c : a);
  }

  /// "04.10.2026"
  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// German decimal format with one digit, e.g. "3,4".
  static String _num(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Escapes user content (symptom names, notes) for safe HTML output.
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll('\n', '<br>');

  /// File-name-safe version of a symptom name ("Kopfschmerzen" → "kopfschmerzen").
  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static const _css = '''
*{box-sizing:border-box}
body{margin:0;background:#F2F4F1;color:#12181A;font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
main{max-width:820px;margin:0 auto;padding:28px 18px 40px;background:#fff;min-height:100vh}
header{border-bottom:1px solid #DCE2DD;padding-bottom:16px;margin-bottom:18px}
.brand{font-weight:700;color:#128577;letter-spacing:.5px}
h1{font-size:26px;margin:2px 0 6px}
h2{font-size:17px;margin:28px 0 10px}
h3{font-size:12px;text-transform:uppercase;letter-spacing:.6px;color:#5C6864;margin:0 0 8px}
.meta{color:#5C6864;margin:0 0 12px}
button{font:inherit;font-weight:600;border:0;border-radius:12px;padding:10px 16px;background:#128577;color:#fff;cursor:pointer}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}
.kpi{border:1px solid #DCE2DD;border-radius:14px;padding:10px 12px}
.kpi .v{font-size:19px;font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.kpi .v.accent{color:#E24F30}
.kpi .l{font-size:11.5px;color:#5C6864}
table{width:100%;border-collapse:collapse}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid #EDF0EE;vertical-align:top}
th{font-size:11.5px;color:#5C6864;font-weight:600}
.r{text-align:right}
.symptoms td{font-size:13px}
.grid3{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin-top:16px}
.box{border:1px solid #DCE2DD;border-radius:14px;padding:12px}
.bar{display:flex;align-items:center;gap:8px;font-size:12px;margin:4px 0}
.bl{width:74px;color:#5C6864;white-space:nowrap}
.bt{flex:1;height:8px;background:#EDF0EE;border-radius:4px;overflow:hidden}
.bf{display:block;height:100%;border-radius:4px}
.bv{width:24px;text-align:right;font-variant-numeric:tabular-nums}
.hint{color:#5C6864;font-size:12.5px}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;vertical-align:middle}
.day{border:1px solid #DCE2DD;border-radius:14px;padding:10px 12px;margin:8px 0;break-inside:avoid;page-break-inside:avoid}
.day-head,.day-empty{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap}
.day-empty{border-style:dashed;color:#8B9793;padding:7px 12px}
.wd{font-weight:700}
.dt{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;color:#8B9793}
.sum{margin-left:auto;font-size:12px;color:#5C6864}
.track{display:block;width:100%;height:34px;margin:6px 0 2px}
.entries td{font-size:13px;border-bottom:1px solid #F2F4F1}
.entries tr:last-child td{border-bottom:0}
.time{font-family:ui-monospace,Menlo,Consolas,monospace;width:52px;color:#5C6864}
.phase{width:90px;color:#5C6864;white-space:nowrap}
.int{text-align:right;white-space:nowrap}
.badge{display:inline-block;font-size:11.5px;font-weight:600;padding:2px 8px;border-radius:9px}
.note{color:#5C6864;font-size:12.5px;margin-top:2px}
.empty{color:#5C6864;font-style:italic}
footer{margin-top:28px;padding-top:12px;border-top:1px solid #DCE2DD;color:#8B9793;font-size:11.5px}
@media (max-width:560px){.phase{display:none}main{padding:20px 14px 32px}}
@media print{
  @page{size:A4;margin:14mm}
  body{background:#fff}
  main{max-width:none;padding:0;min-height:0}
  .no-print{display:none}
  *{-webkit-print-color-adjust:exact;print-color-adjust:exact}
}
''';
}
