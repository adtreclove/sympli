import 'package:flutter/material.dart';
import 'package:sympli/models/factor.dart';

/// 7.5 → "7,5", 7.0 → "7"
String fmtNum(double v, {int decimals = 1}) {
  final rounded = double.parse(v.toStringAsFixed(decimals));
  final s = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(decimals);
  return s.replaceAll('.', ',');
}

/// Wert eines Faktors zum Anzeigen, z.B. "7,5 Std.", "3/5", "ja".
String formatFactorValue(FactorType f, double v) => switch (f.kind) {
  FactorKind.boolean => v >= 0.5 ? 'ja' : 'nein',
  FactorKind.scale => '${fmtNum(v)}/${fmtNum(f.max)}',
  FactorKind.number => f.unit == null ? fmtNum(v) : '${fmtNum(v)} ${f.unit}',
};

/// Beschriftung der Skalen-Enden im Check-in.
({String low, String high}) scaleEndLabels(FactorType f) => switch (f.key) {
  'stress' => (low: 'entspannt', high: 'sehr gestresst'),
  'sleep_quality' => (low: 'schlecht', high: 'erholsam'),
  'nutrition' => (low: 'ungesund', high: 'ausgewogen'),
  _ => (low: 'niedrig', high: 'hoch'),
};

/// Kurze Frage/Beschriftung im Check-in.
String factorPrompt(FactorType f) => switch (f.key) {
  'sleep_hours' => 'Wie lange hast du geschlafen?',
  'sleep_quality' => 'Wie gut hast du geschlafen?',
  'stress' => 'Wie gestresst warst du?',
  'movement' => 'Wie viel hast du dich bewegt?',
  'nutrition' => 'Wie hast du gegessen?',
  'fast_food' => 'Fast Food gegessen?',
  'alcohol' => 'Alkohol getrunken?',
  'caffeine' => 'Kaffee, Tee, Energy (Tassen)',
  'period' => 'Hast du heute deine Periode?',
  _ => f.name,
};

IconData factorIcon(FactorType f) => switch (f.key) {
  'sleep_hours' || 'sleep_quality' => Icons.bedtime_outlined,
  'stress' => Icons.bolt_outlined,
  'movement' => Icons.directions_walk_rounded,
  'nutrition' => Icons.restaurant_outlined,
  'fast_food' => Icons.fastfood_outlined,
  'alcohol' => Icons.wine_bar_outlined,
  'caffeine' => Icons.coffee_outlined,
  'period' || 'pre_period' => Icons.water_drop_outlined,
  'weather_pressure' => Icons.speed_rounded,
  'weather_temp' => Icons.thermostat_rounded,
  'weather_rain' => Icons.umbrella_outlined,
  _ => Icons.tune_rounded,
};

/// Bedingung für einen Satz wie "An Tagen {Bedingung} traten …".
/// [high] = obere Gruppe (Wert > Schwelle bzw. "ja").
String factorCondition(FactorType f, {required bool high, double? threshold}) {
  final t = threshold ?? 0.0;
  switch (f.kind) {
    case FactorKind.boolean:
      return switch (f.key) {
        'pre_period' => high ? 'kurz vor der Periode' : 'außerhalb der Tage vor der Periode',
        _ => high ? 'mit ${f.name}' : 'ohne ${f.name}',
      };
    case FactorKind.scale:
      final (hi, lo) = switch (f.key) {
        'stress' => ('viel Stress', 'wenig Stress'),
        'sleep_quality' => ('guter Schlafqualität', 'schlechter Schlafqualität'),
        'nutrition' => ('ausgewogener Ernährung', 'ungesunder Ernährung'),
        _ => ('${f.name} über ${fmtNum(t)}', '${f.name} bis ${fmtNum(t)}'),
      };
      final known = const ['stress', 'sleep_quality', 'nutrition'].contains(f.key);
      if (!known) return 'mit ${high ? hi : lo}';
      return high
          ? 'mit $hi (über ${fmtNum(t)})'
          : 'mit $lo (bis ${fmtNum(t)})';
    case FactorKind.number:
      final noun = switch (f.key) {
        'sleep_hours' => 'Schlaf',
        'movement' => 'Bewegung',
        'caffeine' => 'Koffein',
        'weather_pressure' => 'Luftdruckänderung',
        'weather_temp' => '',
        'weather_rain' => 'Regen',
        _ => f.name,
      };
      final amount = [
        fmtNum(t),
        if (f.unit != null) f.unit!,
        if (noun.isNotEmpty) noun,
      ].join(' ');
      return high ? 'mit mehr als $amount' : 'mit höchstens $amount';
  }
}

/// Kurzlabel unter den Mini-Balken, z.B. "> 6,5 Std." oder "mit".
String factorGroupLabel(FactorType f, {required bool high, double? threshold}) {
  final t = threshold ?? 0.0;
  switch (f.kind) {
    case FactorKind.boolean:
      if (f.key == 'pre_period') return high ? 'davor' : 'sonst';
      return high ? 'mit' : 'ohne';
    case FactorKind.scale:
      return high ? '> ${fmtNum(t)}' : '≤ ${fmtNum(t)}';
    case FactorKind.number:
      final unit = f.unit == null ? '' : ' ${f.unit}';
      return high ? '> ${fmtNum(t)}$unit' : '≤ ${fmtNum(t)}$unit';
  }
}

/// Satzanfang + Bedingung, z.B. "An Tagen mit Fast Food",
/// "Am Tag nach Alkohol", "Nach Nächten mit höchstens 6 Std. Schlaf".
String conditionPhrase(
  FactorType f, {
  required bool high,
  required int lag,
  double? threshold,
}) {
  final cond = factorCondition(f, high: high, threshold: threshold);
  if (f.slot == FactorSlot.morning) return 'Nach Nächten $cond';
  if (lag == 0) return 'An Tagen $cond';
  final bare = cond.startsWith('mit ') ? cond.substring(4) : cond;
  return 'Am Tag nach $bare';
}
