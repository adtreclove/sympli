import 'dart:math' as math;

import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/helpers/factor_text.dart';
import 'package:sympli/models/factor.dart';
import 'package:sympli/models/symptom_entry.dart';

// ============================================================================
// Auswertung für den Muster-Screen
//
// 1) Veränderungen: letzte 7 Tage vs. die 4 Wochen davor (persönliche Norm).
//    Zu jeder Veränderung: welche Faktoren waren in der Zeit anders?
// 2) Zusammenhänge: über alle Tage – tritt ein Symptom an Tagen mit hohem
//    bzw. niedrigem Faktor-Wert häufiger auf? Auch mit einem Tag Versatz
//    (z.B. Alkohol → Kopfschmerzen am nächsten Tag).
//
// Gezählt werden nur "beobachtete" Tage: Tage mit Check-in oder Eintrag.
// Ein Tag ohne beides kann "keine Symptome" oder "App nicht benutzt" heißen.
// ============================================================================

/// Ab so vielen beobachteten Tagen werten wir überhaupt aus.
const minObservedDays = 14;

/// Ab hier gelten die Ergebnisse als einigermaßen stabil (Fortschrittsbalken).
const targetObservedDays = 21;

class FactorSeries {
  const FactorSeries(this.type, this.values);
  final FactorType type;
  final Map<DateTime, double> values;
}

// Ergebnis-Typen

enum ChangeKind { more, less, newSymptom, stronger, milder }

class FactorShift {
  const FactorShift({
    required this.type,
    required this.recent,
    required this.base,
    required this.recentCount,
    required this.score,
    required this.matchesPattern,
  });

  final FactorType type;

  /// Mittelwert (bzw. Anteil "ja" bei Ja/Nein) in beiden Zeiträumen.
  final double recent;
  final double base;
  final int recentCount;
  final double score;

  /// Passt die Richtung zu einem bekannten Zusammenhang mit dem Symptom?
  final bool matchesPattern;

  String get detail {
    if (type.kind == FactorKind.boolean) {
      final days = (recent * recentCount).round();
      return 'an $days von $recentCount Tagen – sonst etwa '
          '${fmtNum(base * 7)} von 7';
    }
    return 'ø ${formatFactorValue(type, recent)} statt '
        '${formatFactorValue(type, base)}';
  }
}

class SymptomChange {
  const SymptomChange({
    required this.symptomId,
    required this.symptomName,
    required this.kind,
    required this.recentDays,
    required this.recentObserved,
    required this.baseRate,
    required this.avgRecent,
    required this.avgBase,
    required this.magnitude,
    required this.reasons,
  });

  final String symptomId;
  final String symptomName;
  final ChangeKind kind;
  final int recentDays;
  final int recentObserved;

  /// Anteil der Tage mit Symptom in den 4 Wochen davor.
  final double baseRate;
  final double? avgRecent;
  final double? avgBase;
  final double magnitude;
  final List<FactorShift> reasons;

  bool get isWorse =>
      kind == ChangeKind.more ||
      kind == ChangeKind.newSymptom ||
      kind == ChangeKind.stronger;

  String get title => switch (kind) {
    ChangeKind.more => '$symptomName häufiger als sonst',
    ChangeKind.less => '$symptomName seltener als sonst',
    ChangeKind.newSymptom => '$symptomName ist neu dabei',
    ChangeKind.stronger => '$symptomName stärker als sonst',
    ChangeKind.milder => '$symptomName schwächer als sonst',
  };

  String get detail => switch (kind) {
    ChangeKind.more || ChangeKind.less =>
      'An $recentDays von $recentObserved Tagen – sonst etwa '
          '${fmtNum(baseRate * 7)}× pro Woche.',
    ChangeKind.newSymptom =>
      'An $recentDays der letzten $recentObserved Tage – in den 4 Wochen '
          'davor gar nicht.',
    ChangeKind.stronger || ChangeKind.milder =>
      'Intensität ø ${fmtNum(avgRecent ?? 0.0)} statt '
          '${fmtNum(avgBase ?? 0.0)} (von 5).',
  };
}

class Association {
  const Association({
    required this.symptomId,
    required this.symptomName,
    required this.type,
    required this.lag,
    required this.high,
    required this.threshold,
    required this.rateSide,
    required this.rateOther,
    required this.z,
    required this.daysConsidered,
  });

  final String symptomId;
  final String symptomName;
  final FactorType type;

  /// 0 = gleicher Tag, 1 = Faktor am Vortag.
  final int lag;

  /// true = die obere Gruppe (mehr / "ja") ist die mit mehr Symptomen.
  final bool high;
  final double? threshold;

  /// Anteil der Tage mit Symptom in der auffälligen bzw. anderen Gruppe.
  final double rateSide;
  final double rateOther;

  /// Stärke des Unterschieds (Zwei-Anteile-z-Test, Betrag).
  final double z;
  final int daysConsidered;

  bool get isStrong => z >= 3.5 && daysConsidered >= 30;

  String get strengthLabel => isStrong ? 'deutlich' : 'erster Hinweis';

  String get sideLabel =>
      factorGroupLabel(type, high: high, threshold: threshold);
  String get otherLabel =>
      factorGroupLabel(type, high: !high, threshold: threshold);

  String get effect {
    if (rateOther <= 0) return 'deutlich häufiger';
    final ratio = rateSide / rateOther;
    if (ratio >= 2) return '${fmtNum(ratio)}× so oft';
    return '${((ratio - 1) * 100).round()}% häufiger';
  }

  /// Satz in drei Teilen, damit der Effekt hervorgehoben werden kann:
  /// "An Tagen mit Fast Food hattest du " + "68% häufiger" + " Kopfschmerzen."
  ({String before, String highlight, String after}) get sentence => (
    before:
        '${conditionPhrase(type, high: high, lag: lag, threshold: threshold)} '
        'hattest du ',
    highlight: effect,
    after: ' $symptomName.',
  );
}

class InsightReport {
  const InsightReport({
    required this.observedDays,
    required this.checkInDays,
    required this.changes,
    required this.associations,
    required this.hasWeather,
    required this.hasCycle,
  });

  final int observedDays;
  final int checkInDays;
  final List<SymptomChange> changes;
  final List<Association> associations;
  final bool hasWeather;
  final bool hasCycle;

  bool get enoughData => observedDays >= minObservedDays;
}

// ---------------------------------------------------------------------------
// Berechnung

InsightReport buildInsightReport({
  required List<SymptomEntry> entries,
  required List<FactorType> types,
  required Map<String, Map<DateTime, double>> logsByTypeId,
  required Map<String, Map<DateTime, double>> weather,
  required bool trackCycle,
  int windowDays = 90,
  DateTime? now,
}) {
  final today = dayKey(now ?? DateTime.now());
  final windowStart = addDays(today, -(windowDays - 1));
  bool inWindow(DateTime d) => !d.isBefore(windowStart) && !d.isAfter(today);

  // Faktor-Reihen: Check-in, Wetter, Zyklus
  final series = <FactorSeries>[];
  for (final t in types) {
    if (t.requiresCycle && !trackCycle) continue;
    final values = logsByTypeId[t.id];
    if (values != null && values.isNotEmpty)
      series.add(FactorSeries(t, values));
  }
  var hasWeather = false;
  for (final w in VirtualFactors.weather) {
    final values = weather[w.key];
    if (values != null && values.isNotEmpty) {
      series.add(FactorSeries(w, values));
      hasWeather = true;
    }
  }
  var hasCycle = false;
  if (trackCycle) {
    final period = types.where((t) => t.key == 'period').firstOrNull;
    final pre = derivePrePeriod(
      period == null ? const {} : (logsByTypeId[period.id] ?? const {}),
    );
    if (pre.isNotEmpty) {
      series.add(FactorSeries(VirtualFactors.prePeriod, pre));
      hasCycle = true;
    }
  }

  // Beobachtete Tage
  final checkInDays = {
    for (final m in logsByTypeId.values)
      for (final d in m.keys)
        if (inWindow(d)) dayKey(d),
  };
  final observed = {
    ...checkInDays,
    for (final e in entries)
      if (inWindow(e.occurredAt)) dayKey(e.occurredAt),
  };

  // Tage je Symptom
  final symptomDays = <String, Set<DateTime>>{};
  final names = <String, String>{};
  for (final e in entries) {
    if (!inWindow(e.occurredAt)) continue;
    symptomDays.putIfAbsent(e.symptomId, () => {}).add(dayKey(e.occurredAt));
    names[e.symptomId] = e.symptomName;
  }

  final associations = observed.length < minObservedDays
      ? <Association>[]
      : _findAssociations(observed, symptomDays, names, series);
  final changes = _detectChanges(
    today,
    observed,
    entries,
    series,
    associations,
  );

  return InsightReport(
    observedDays: observed.length,
    checkInDays: checkInDays.length,
    changes: changes,
    associations: associations,
    hasWeather: hasWeather,
    hasCycle: hasCycle,
  );
}

/// Aus den Periode-Tagen (1 = ja) abgeleitet: 1 an den 5 Tagen vor einem
/// Periodenbeginn, 0 an anderen Tagen zwischen erstem und letztem bekannten
/// Beginn. Danach ist unbekannt, wann die nächste Periode kommt → kein Wert.
Map<DateTime, double> derivePrePeriod(Map<DateTime, double> period) {
  final periodDays = {
    for (final e in period.entries)
      if (e.value >= 0.5) dayKey(e.key),
  };
  final starts =
      periodDays.where((d) => !periodDays.contains(addDays(d, -1))).toList()
        ..sort();
  if (starts.isEmpty) return const {};

  final result = <DateTime, double>{};
  var d = addDays(starts.first, -5);
  while (d.isBefore(starts.last)) {
    if (!periodDays.contains(d)) {
      final isPre = starts.any((s) {
        final diff = daysBetween(d, s);
        return diff >= 1 && diff <= 5;
      });
      result[d] = isPre ? 1.0 : 0.0;
    }
    d = addDays(d, 1);
  }
  return result;
}

double _twoProportionZ(int y1, int n1, int y2, int n2) {
  final p = (y1 + y2) / (n1 + n2);
  if (p <= 0 || p >= 1) return 0;
  final se = math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2));
  return (y1 / n1 - y2 / n2) / se;
}

List<Association> _findAssociations(
  Set<DateTime> observed,
  Map<String, Set<DateTime>> symptomDays,
  Map<String, String> names,
  List<FactorSeries> series,
) {
  final result = <Association>[];

  for (final symptom in symptomDays.entries) {
    if (symptom.value.length < 3) continue;

    for (final fs in series) {
      final isBool = fs.type.kind == FactorKind.boolean;
      // Abend-Faktoren & Wetter können auch am nächsten Tag wirken.
      final lags =
          fs.type.slot == FactorSlot.morning ||
              fs.type.key == 'pre_period' ||
              fs.type.key == 'period'
          ? const [0]
          : const [0, 1];

      Association? best;
      for (final lag in lags) {
        final xs = <double>[];
        final ys = <bool>[];
        for (final d in observed) {
          final v = fs.values[addDays(d, -lag)];
          if (v == null) continue;
          xs.add(v);
          ys.add(symptom.value.contains(d));
        }
        if (xs.length < 10) continue;

        final t = isBool ? 0.5 : median(xs);
        var nHigh = 0, yHigh = 0, nLow = 0, yLow = 0;
        for (var i = 0; i < xs.length; i++) {
          final isHigh = isBool ? xs[i] >= 0.5 : xs[i] > t;
          if (isHigh) {
            nHigh++;
            if (ys[i]) yHigh++;
          } else {
            nLow++;
            if (ys[i]) yLow++;
          }
        }
        if (nHigh < 4 || nLow < 4) continue;

        final pHigh = yHigh / nHigh;
        final pLow = yLow / nLow;
        final highWorse = pHigh > pLow;
        // "An Tagen OHNE Alkohol mehr Symptome" wäre kein sinnvoller Hinweis
        if (isBool && !highWorse) continue;

        final pSide = highWorse ? pHigh : pLow;
        final pOther = highWorse ? pLow : pHigh;
        final hits = highWorse ? yHigh : yLow;
        if (pSide - pOther < 0.2 || hits < 3) continue;

        // Streng, weil wir viele Faktor×Symptom-Kombinationen prüfen:
        // Mit z ≥ 2,8 bleibt es in Simulationen bei ~0,15 Scheinzusammen-
        // hängen pro Person (mit z ≥ 2,0 wären es ~1,5).
        final z = _twoProportionZ(yHigh, nHigh, yLow, nLow).abs();
        if (z < 2.8) continue;

        final candidate = Association(
          symptomId: symptom.key,
          symptomName: names[symptom.key] ?? '–',
          type: fs.type,
          lag: lag,
          high: highWorse,
          threshold: isBool ? null : t,
          rateSide: pSide,
          rateOther: pOther,
          z: z,
          daysConsidered: xs.length,
        );
        if (best == null || candidate.z > best.z) best = candidate;
      }
      if (best != null) result.add(best);
    }
  }

  result.sort((a, b) => b.z.compareTo(a.z));
  return result.take(6).toList();
}

List<SymptomChange> _detectChanges(
  DateTime today,
  Set<DateTime> observed,
  List<SymptomEntry> entries,
  List<FactorSeries> series,
  List<Association> associations,
) {
  final recentStart = addDays(today, -6);
  final baseStart = addDays(today, -34);
  final baseEnd = addDays(today, -7);
  bool isRecent(DateTime d) => !d.isBefore(recentStart) && !d.isAfter(today);
  bool isBase(DateTime d) => !d.isBefore(baseStart) && !d.isAfter(baseEnd);

  final obsRecent = observed.where(isRecent).length;
  final obsBase = observed.where(isBase).length;
  if (obsRecent < 4 || obsBase < 10) return const [];

  final daysR = <String, Set<DateTime>>{};
  final daysB = <String, Set<DateTime>>{};
  final intR = <String, List<double>>{};
  final intB = <String, List<double>>{};
  final names = <String, String>{};
  for (final e in entries) {
    final d = dayKey(e.occurredAt);
    names[e.symptomId] = e.symptomName;
    if (isRecent(d)) {
      daysR.putIfAbsent(e.symptomId, () => {}).add(d);
      intR.putIfAbsent(e.symptomId, () => []).add(e.intensity.toDouble());
    } else if (isBase(d)) {
      daysB.putIfAbsent(e.symptomId, () => {}).add(d);
      intB.putIfAbsent(e.symptomId, () => []).add(e.intensity.toDouble());
    }
  }

  final changes = <SymptomChange>[];
  for (final id in {...daysR.keys, ...daysB.keys}) {
    final dR = daysR[id]?.length ?? 0;
    final dB = daysB[id]?.length ?? 0;
    final rR = dR / obsRecent;
    final rB = dB / obsBase;
    final iR = intR[id] ?? const <double>[];
    final iB = intB[id] ?? const <double>[];

    // Statistischer Test + Mindestgröße, damit normale Schwankungen nicht
    // als Veränderung gemeldet werden (Simulation: ≤ 5 % Fehlalarme pro
    // Symptom und Woche).
    final z = _twoProportionZ(dR, obsRecent, dB, obsBase);
    ChangeKind? kind;
    var magnitude = (rR - rB).abs();
    if (dB == 0 && dR >= 3) {
      kind = ChangeKind.newSymptom;
    } else if (dR >= 3 && rR - rB >= 0.25 && z >= 2.0) {
      kind = ChangeKind.more;
    } else if (dB >= 4 && rB - rR >= 0.2 && z <= -2.0) {
      kind = ChangeKind.less;
    } else if (iR.length >= 3 && iB.length >= 4) {
      final diff = mean(iR) - mean(iB);
      if (diff >= 1) kind = ChangeKind.stronger;
      if (diff <= -1) kind = ChangeKind.milder;
      magnitude = diff.abs() / 4;
    }
    if (kind == null) continue;

    final worse =
        kind == ChangeKind.more ||
        kind == ChangeKind.newSymptom ||
        kind == ChangeKind.stronger;

    changes.add(
      SymptomChange(
        symptomId: id,
        symptomName: names[id] ?? '–',
        kind: kind,
        recentDays: dR,
        recentObserved: obsRecent,
        baseRate: rB,
        avgRecent: iR.isEmpty ? null : mean(iR),
        avgBase: iB.isEmpty ? null : mean(iB),
        magnitude: magnitude,
        reasons: _factorShifts(
          series,
          isRecent,
          isBase,
          associations.where((a) => a.symptomId == id).toList(),
          worse: worse,
        ),
      ),
    );
  }

  changes.sort((a, b) {
    if (a.isWorse != b.isWorse) return a.isWorse ? -1 : 1;
    return b.magnitude.compareTo(a.magnitude);
  });
  return changes.take(3).toList();
}

/// Welche Faktoren waren in den letzten 7 Tagen deutlich anders als davor?
List<FactorShift> _factorShifts(
  List<FactorSeries> series,
  bool Function(DateTime) isRecent,
  bool Function(DateTime) isBase,
  List<Association> symptomAssociations, {
  required bool worse,
}) {
  final shifts = <FactorShift>[];

  for (final fs in series) {
    final r = [
      for (final e in fs.values.entries)
        if (isRecent(e.key)) e.value,
    ];
    final b = [
      for (final e in fs.values.entries)
        if (isBase(e.key)) e.value,
    ];
    if (r.length < 3 || b.length < 5) continue;

    final mR = mean(r);
    final mB = mean(b);
    double score;
    if (fs.type.kind == FactorKind.boolean) {
      final diff = mR - mB;
      if (diff.abs() < 0.3) continue;
      score = diff.abs() * 2.5;
    } else {
      final sd = math.max(stdDev(b), fs.type.step);
      final z = (mR - mB) / sd;
      if (z.abs() < 0.8) continue;
      score = z.abs();
    }

    // Passt die Richtung zu einem bekannten Zusammenhang?
    // Verschlechterung: Faktor hat sich zur "ungünstigen" Seite bewegt.
    // Verbesserung: Faktor hat sich davon weg bewegt.
    final a = symptomAssociations
        .where((a) => a.type.id == fs.type.id)
        .firstOrNull;
    var matches = false;
    if (a != null) {
      final movedTowardBadSide = a.high ? mR > mB : mR < mB;
      matches = worse ? movedTowardBadSide : !movedTowardBadSide;
    }

    shifts.add(
      FactorShift(
        type: fs.type,
        recent: mR,
        base: mB,
        recentCount: r.length,
        score: score,
        matchesPattern: matches,
      ),
    );
  }

  shifts.sort((x, y) {
    if (x.matchesPattern != y.matchesPattern) {
      return x.matchesPattern ? -1 : 1;
    }
    return y.score.compareTo(x.score);
  });
  return shifts.take(3).toList();
}
