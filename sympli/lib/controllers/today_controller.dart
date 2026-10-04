import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/models/symptom_entry.dart';

/// All today's entries, ascending by time
final todayEntriesProvider = FutureProvider<List<SymptomEntry>>((ref) async {
  final client = Supabase.instance.client;
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day + 1);

  final rows = await client
      .from('entries')
      .select('id, symptom_id, occurred_at, intensity, note, symptoms(name)')
      .gte('occurred_at', start.toUtc().toIso8601String())
      .lt('occurred_at', end.toUtc().toIso8601String())
      .order('occurred_at');

  return rows.map<SymptomEntry>(SymptomEntry.fromMap).toList();
});
