import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/models/symptom_entry.dart';

/// Wie weit Verlauf & Muster zurückschauen.
const historyDays = 90;

/// Alle Einträge der letzten [historyDays] Tage (inkl. heute), aufsteigend.
/// Verlauf (7/30 Tage) und Muster rechnen daraus – eine Abfrage für beide.
final recentEntriesProvider = FutureProvider<List<SymptomEntry>>((ref) async {
  final client = Supabase.instance.client;
  final start = addDays(dayKey(DateTime.now()), -(historyDays - 1));

  final rows = await client
      .from('entries')
      .select('id, symptom_id, occurred_at, intensity, note, symptoms(name)')
      .gte('occurred_at', start.toUtc().toIso8601String())
      .order('occurred_at');

  return rows.map<SymptomEntry>(SymptomEntry.fromMap).toList();
});
