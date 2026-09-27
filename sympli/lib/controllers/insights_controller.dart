import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sympli/controllers/factors_controller.dart';
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/helpers/insights.dart';

/// Veränderungen & Zusammenhänge – rechnet neu, sobald sich Einträge,
/// Check-ins, Einstellungen oder Wetter ändern.
final insightsProvider = FutureProvider<InsightReport>((ref) async {
  final entries = await ref.watch(recentEntriesProvider.future);
  final types = await ref.watch(factorTypesProvider.future);
  final logs = await ref.watch(factorLogsProvider.future);
  final settings = await ref.watch(userSettingsProvider.future);

  // Wetter ist ein Bonus: wenn Open-Meteo nicht erreichbar ist,
  // läuft die Auswertung trotzdem.
  Map<String, Map<DateTime, double>> weather = const {};
  try {
    weather = await ref.watch(weatherProvider.future);
  } catch (_) {}

  return buildInsightReport(
    entries: entries,
    types: types,
    logsByTypeId: logs.byType,
    weather: weather,
    trackCycle: settings.trackCycle,
    windowDays: historyDays,
  );
});
