import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide FactorType;
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/controllers/today_controller.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/models/factor.dart';
import 'package:sympli/services/weather_service.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Alle sichtbaren Faktoren (Standard + eigene), sortiert.
final factorTypesProvider = FutureProvider<List<FactorType>>((ref) async {
  final rows = await _db
      .from('factor_types')
      .select(
        'id, key, name, unit, kind, slot, min_value, max_value, step, '
        'default_value, sort_order, requires_cycle',
      )
      .order('sort_order')
      .order('name');
  return rows.map<FactorType>(FactorType.fromMap).toList();
});

/// Erfasste Faktor-Werte, je Faktor-ID und Tag.
class FactorLogs {
  const FactorLogs(this.byType);

  final Map<String, Map<DateTime, double>> byType;

  double? value(String typeId, DateTime day) => byType[typeId]?[dayKey(day)];

  /// Tage, an denen irgendein Check-in-Wert erfasst wurde.
  Set<DateTime> get days => {for (final m in byType.values) ...m.keys};

  /// Letzter bekannter Wert vor [day] – als Startwert im Check-in.
  double? lastBefore(String typeId, DateTime day) {
    final values = byType[typeId];
    if (values == null) return null;
    DateTime? best;
    for (final d in values.keys) {
      if (d.isBefore(dayKey(day)) && (best == null || d.isAfter(best))) {
        best = d;
      }
    }
    return best == null ? null : values[best];
  }
}

final factorLogsProvider = FutureProvider<FactorLogs>((ref) async {
  final start = addDays(dayKey(DateTime.now()), -(historyDays - 1));
  final rows = await _db
      .from('factor_logs')
      .select('factor_type_id, log_date, value')
      .gte('log_date', isoDate(start));

  final byType = <String, Map<DateTime, double>>{};
  for (final row in rows) {
    final value = num.tryParse('${row['value']}');
    if (value == null) continue;
    byType.putIfAbsent(row['factor_type_id'].toString(), () => {})[dayKey(
      DateTime.parse(row['log_date'] as String),
    )] = value
        .toDouble();
  }
  return FactorLogs(byType);
});

/// Speichert die Check-in-Werte eines Tages. `null` löscht einen Wert.
Future<void> saveFactorValues(DateTime day, Map<String, double?> values) async {
  final userId = _db.auth.currentUser!.id;
  final date = isoDate(day);

  final upserts = [
    for (final e in values.entries)
      if (e.value != null)
        {
          'user_id': userId,
          'factor_type_id': e.key,
          'log_date': date,
          'value': e.value,
        },
  ];
  final deletes = [
    for (final e in values.entries)
      if (e.value == null) e.key,
  ];

  if (upserts.isNotEmpty) {
    await _db
        .from('factor_logs')
        .upsert(upserts, onConflict: 'user_id,factor_type_id,log_date');
  }
  if (deletes.isNotEmpty) {
    await _db
        .from('factor_logs')
        .delete()
        .eq('user_id', userId)
        .eq('log_date', date)
        .inFilter('factor_type_id', deletes);
  }
}

// ---------------------------------------------------------------------------
// Einstellungen

class UserSettingsNotifier extends AsyncNotifier<UserSettings> {
  @override
  Future<UserSettings> build() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const UserSettings();
    final row = await _db
        .from('user_settings')
        .select('track_cycle, city, latitude, longitude')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? const UserSettings() : UserSettings.fromMap(row);
  }

  Future<void> save(UserSettings settings) async {
    await _db.from('user_settings').upsert({
      'user_id': _db.auth.currentUser!.id,
      'track_cycle': settings.trackCycle,
      'city': settings.city,
      'latitude': settings.latitude,
      'longitude': settings.longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    state = AsyncData(settings);
  }
}

final userSettingsProvider =
    AsyncNotifierProvider<UserSettingsNotifier, UserSettings>(
      UserSettingsNotifier.new,
    );

/// Wetter der letzten ~90 Tage am eingestellten Ort (leer ohne Ort).
final weatherProvider = FutureProvider<Map<String, Map<DateTime, double>>>((
  ref,
) async {
  final settings = await ref.watch(userSettingsProvider.future);
  if (!settings.hasLocation) return const {};
  return WeatherService.fetchDaily(settings.latitude!, settings.longitude!);
});

/// Nach dem Abmelden: alle nutzerbezogenen Daten verwerfen, damit beim
/// nächsten Login nichts vom vorherigen Konto übrig bleibt.
void invalidateUserData(WidgetRef ref) {
  ref.invalidate(todayEntriesProvider);
  ref.invalidate(recentEntriesProvider);
  ref.invalidate(factorTypesProvider);
  ref.invalidate(factorLogsProvider);
  ref.invalidate(userSettingsProvider);
  ref.invalidate(weatherProvider);
}
