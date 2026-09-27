import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/models/symptom_entry.dart';

/// Alle Einträge des heutigen (lokalen) Tages, aufsteigend nach Uhrzeit.
///
/// Nach dem Speichern eines neuen Eintrags wird der Provider in der
/// AppShell per `ref.invalidate(todayEntriesProvider)` neu geladen.
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

/// Hell/Dunkel-Umschalter oben rechts im Tages-Screen.
/// Startet mit der Geräte-Einstellung.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Wechselt ausgehend von der aktuell *sichtbaren* Helligkeit.
  void toggle(Brightness current) {
    state = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
