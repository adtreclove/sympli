import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/controllers/factors_controller.dart';
import 'package:sympli/controllers/history_controller.dart';
import 'package:sympli/controllers/today_controller.dart';
import 'package:sympli/models/factor.dart';
import 'package:sympli/services/weather_service.dart';

SupabaseClient get _db => Supabase.instance.client;

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

/// Weather the last 90 days (only if location is enabled)
final weatherProvider = FutureProvider<Map<String, Map<DateTime, double>>>((
  ref,
) async {
  final settings = await ref.watch(userSettingsProvider.future);
  if (!settings.hasLocation) return const {};
  return WeatherService.fetchDaily(settings.latitude!, settings.longitude!);
});

/// Invalidate user data providers after logout
void invalidateUserData(WidgetRef ref) {
  ref.invalidate(todayEntriesProvider);
  ref.invalidate(recentEntriesProvider);
  ref.invalidate(factorTypesProvider);
  ref.invalidate(factorLogsProvider);
  ref.invalidate(userSettingsProvider);
  ref.invalidate(weatherProvider);
}
