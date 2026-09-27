import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sympli/helpers/entry_stats.dart';
import 'package:sympli/models/factor.dart';

/// Wetterdaten von Open-Meteo (kostenlos, kein API-Key, nur ungefährer Ort).
class WeatherService {
  WeatherService._();

  /// Ortssuche für die Einstellungen, z.B. "Münster".
  static Future<List<GeoPlace>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': q,
      'count': '6',
      'language': 'de',
      'format': 'json',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Geocoding ${res.statusCode}');

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? const [];
    return [
      for (final r in results.cast<Map<String, dynamic>>())
        GeoPlace(
          name: r['name'] as String? ?? '',
          region: r['admin1'] as String?,
          country: r['country'] as String?,
          latitude: (r['latitude'] as num).toDouble(),
          longitude: (r['longitude'] as num).toDouble(),
        ),
    ];
  }

  /// Tageswerte der letzten ~92 Tage bis heute, je Faktor-Key:
  /// - `weather_pressure`: Luftdruckänderung zum Vortag (hPa, Betrag)
  /// - `weather_temp`: Höchsttemperatur (°C)
  /// - `weather_rain`: Niederschlag (mm)
  static Future<Map<String, Map<DateTime, double>>> fetchDaily(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(3),
      'longitude': longitude.toStringAsFixed(3),
      'hourly': 'pressure_msl',
      'daily': 'temperature_2m_max,precipitation_sum',
      'past_days': '92',
      'forecast_days': '1',
      'timezone': 'auto',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Wetter ${res.statusCode}');
    final body = jsonDecode(res.body) as Map<String, dynamic>;

    // Luftdruck: Tagesmittel aus Stundenwerten, dann Änderung zum Vortag
    final hourly = body['hourly'] as Map<String, dynamic>? ?? const {};
    final hTimes = (hourly['time'] as List?) ?? const [];
    final hPressure = (hourly['pressure_msl'] as List?) ?? const [];
    final sums = <DateTime, double>{};
    final counts = <DateTime, int>{};
    for (var i = 0; i < hTimes.length && i < hPressure.length; i++) {
      final p = hPressure[i];
      if (p == null) continue;
      final day = dayKey(DateTime.parse(hTimes[i] as String));
      sums[day] = (sums[day] ?? 0.0) + (p as num).toDouble();
      counts[day] = (counts[day] ?? 0) + 1;
    }
    final means = {for (final d in sums.keys) d: sums[d]! / counts[d]!};
    final pressureChange = <DateTime, double>{};
    for (final d in means.keys) {
      final prev = means[addDays(d, -1)];
      if (prev != null) pressureChange[d] = (means[d]! - prev).abs();
    }

    final daily = body['daily'] as Map<String, dynamic>? ?? const {};
    final dTimes = (daily['time'] as List?) ?? const [];
    Map<DateTime, double> dailySeries(String name) {
      final values = (daily[name] as List?) ?? const [];
      return {
        for (var i = 0; i < dTimes.length && i < values.length; i++)
          if (values[i] != null)
            dayKey(DateTime.parse(dTimes[i] as String)):
                (values[i] as num).toDouble(),
      };
    }

    return {
      VirtualFactors.pressure.key: pressureChange,
      VirtualFactors.temperature.key: dailySeries('temperature_2m_max'),
      VirtualFactors.rain.key: dailySeries('precipitation_sum'),
    };
  }
}

class GeoPlace {
  const GeoPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.region,
    this.country,
  });

  final String name;
  final String? region;
  final String? country;
  final double latitude;
  final double longitude;

  String get label => [name, region, country]
      .where((s) => s != null && s.isNotEmpty)
      .join(', ');
}
