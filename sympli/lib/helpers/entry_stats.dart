import 'dart:math' as math;

import 'package:sympli/models/symptom_entry.dart';

/// Tag ohne Uhrzeit (lokal) – Schlüssel zum Gruppieren nach Tagen.
DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// Kalendertage addieren (auch über die Zeitumstellung hinweg korrekt –
/// `subtract(Duration(days: n))` würde dort um eine Stunde verrutschen).
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Anzahl Kalendertage von [from] bis [to].
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Einträge der letzten [days] Tage inkl. heute.
List<SymptomEntry> entriesInLastDays(
  List<SymptomEntry> entries,
  int days, {
  DateTime? today,
}) {
  final start = addDays(dayKey(today ?? DateTime.now()), -(days - 1));
  return entries.where((e) => !e.occurredAt.isBefore(start)).toList();
}

class SymptomRef {
  const SymptomRef(this.id, this.name);
  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is SymptomRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Symptome nach Häufigkeit sortiert (häufigstes zuerst).
List<SymptomRef> symptomsByFrequency(List<SymptomEntry> entries) {
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final e in entries) {
    counts[e.symptomId] = (counts[e.symptomId] ?? 0) + 1;
    names[e.symptomId] = e.symptomName;
  }
  final ids = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : names[a]!.compareTo(names[b]!);
    });
  return [for (final id in ids) SymptomRef(id, names[id]!)];
}

double? averageIntensity(List<SymptomEntry> entries) {
  if (entries.isEmpty) return null;
  final sum = entries.fold<int>(0, (s, e) => s + e.intensity);
  return sum / entries.length;
}

/// Einträge pro Tag für die letzten [days] Tage, ältester Tag zuerst.
/// Mit [symptomId] nur dieses Symptom.
List<int> dailyCounts(
  List<SymptomEntry> entries,
  int days, {
  String? symptomId,
  DateTime? today,
}) {
  final end = dayKey(today ?? DateTime.now());
  final counts = List<int>.filled(days, 0);
  for (final e in entries) {
    if (symptomId != null && e.symptomId != symptomId) continue;
    final diff = daysBetween(e.occurredAt, end);
    if (diff >= 0 && diff < days) counts[days - 1 - diff]++;
  }
  return counts;
}

/// Einträge pro Wochentag, Index 0 = Montag.
List<int> weekdayCounts(List<SymptomEntry> entries) {
  final counts = List<int>.filled(7, 0);
  for (final e in entries) {
    counts[e.occurredAt.weekday - 1]++;
  }
  return counts;
}

/// "2026-09-27" – Format für `date`-Spalten.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

double mean(Iterable<double> values) {
  var sum = 0.0;
  var n = 0;
  for (final v in values) {
    sum += v;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}

double median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Stichproben-Standardabweichung.
double stdDev(List<double> values) {
  if (values.length < 2) return 0;
  final m = mean(values);
  var sq = 0.0;
  for (final v in values) {
    sq += (v - m) * (v - m);
  }
  return math.sqrt(sq / (values.length - 1));
}
