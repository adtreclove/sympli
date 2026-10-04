import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide FactorType;
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/models/factor.dart';

SupabaseClient get _db => Supabase.instance.client;

/// All visible factors sorted
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

/// noted facrot values
class FactorLogs {
  const FactorLogs(this.byType);

  final Map<String, Map<DateTime, double>> byType;

  double? value(String typeId, DateTime day) => byType[typeId]?[dayKey(day)];

  /// Days with check in
  Set<DateTime> get days => {for (final m in byType.values) ...m.keys};

  /// Last known value before [day], as start value
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

/// Saves check in values for a day. `null` deletes a value.
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
