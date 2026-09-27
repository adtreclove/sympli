/// Wie ein Faktor erfasst wird.
enum FactorKind {
  number,
  scale,
  boolean;

  static FactorKind parse(String? v) => switch (v) {
    'scale' => FactorKind.scale,
    'boolean' => FactorKind.boolean,
    _ => FactorKind.number,
  };
}

/// Wann ein Faktor abgefragt wird. [auto] = wird berechnet (Wetter, Zyklus).
enum FactorSlot {
  morning,
  evening,
  auto;

  static FactorSlot parse(String? v) => switch (v) {
    'morning' => FactorSlot.morning,
    'auto' => FactorSlot.auto,
    _ => FactorSlot.evening,
  };
}

/// Ein Einflussfaktor (Zeile aus `factor_types` oder ein berechneter
/// Faktor wie Luftdruck).
class FactorType {
  const FactorType({
    required this.id,
    required this.key,
    required this.name,
    required this.kind,
    required this.slot,
    this.unit,
    this.min = 0,
    this.max = 10,
    this.step = 1,
    this.defaultValue,
    this.sortOrder = 100,
    this.requiresCycle = false,
  });

  final String id;

  /// Stabiler Bezeichner, z.B. `sleep_hours`. Bei eigenen Faktoren = id.
  final String key;
  final String name;
  final FactorKind kind;
  final FactorSlot slot;
  final String? unit;
  final double min;
  final double max;
  final double step;
  final double? defaultValue;
  final int sortOrder;
  final bool requiresCycle;

  factory FactorType.fromMap(Map<String, dynamic> row) {
    double? n(Object? v) => v == null ? null : num.tryParse('$v')?.toDouble();

    final kind = FactorKind.parse(row['kind'] as String?);
    final isScale = kind == FactorKind.scale;
    final isBool = kind == FactorKind.boolean;

    return FactorType(
      id: row['id'].toString(),
      key: (row['key'] as String?) ?? row['id'].toString(),
      name: row['name'] as String? ?? '–',
      kind: kind,
      slot: FactorSlot.parse(row['slot'] as String?),
      unit: row['unit'] as String?,
      min: n(row['min_value']) ?? (isScale ? 1.0 : 0.0),
      max: n(row['max_value']) ?? (isScale ? 5.0 : (isBool ? 1.0 : 100.0)),
      step: n(row['step']) ?? 1,
      defaultValue: n(row['default_value']),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 100,
      requiresCycle: row['requires_cycle'] as bool? ?? false,
    );
  }
}

/// Berechnete Faktoren – nicht in der Datenbank, nur in der Auswertung.
class VirtualFactors {
  VirtualFactors._();

  static const pressure = FactorType(
    id: 'weather_pressure',
    key: 'weather_pressure',
    name: 'Luftdruckänderung',
    unit: 'hPa',
    kind: FactorKind.number,
    slot: FactorSlot.auto,
    step: 1,
  );
  static const temperature = FactorType(
    id: 'weather_temp',
    key: 'weather_temp',
    name: 'Höchsttemperatur',
    unit: '°C',
    kind: FactorKind.number,
    slot: FactorSlot.auto,
    step: 1,
  );
  static const rain = FactorType(
    id: 'weather_rain',
    key: 'weather_rain',
    name: 'Niederschlag',
    unit: 'mm',
    kind: FactorKind.number,
    slot: FactorSlot.auto,
    step: 1,
  );
  static const prePeriod = FactorType(
    id: 'pre_period',
    key: 'pre_period',
    name: 'Tage vor der Periode',
    kind: FactorKind.boolean,
    slot: FactorSlot.auto,
    max: 1,
  );

  static const weather = [pressure, temperature, rain];
}

/// Persönliche Einstellungen (`user_settings`).
class UserSettings {
  const UserSettings({
    this.trackCycle = false,
    this.city,
    this.latitude,
    this.longitude,
  });

  final bool trackCycle;
  final String? city;
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

  factory UserSettings.fromMap(Map<String, dynamic> row) => UserSettings(
    trackCycle: row['track_cycle'] as bool? ?? false,
    city: row['city'] as String?,
    latitude: (row['latitude'] as num?)?.toDouble(),
    longitude: (row['longitude'] as num?)?.toDouble(),
  );

  UserSettings copyWith({bool? trackCycle}) => UserSettings(
    trackCycle: trackCycle ?? this.trackCycle,
    city: city,
    latitude: latitude,
    longitude: longitude,
  );

  UserSettings withLocation(String? city, double? lat, double? lon) =>
      UserSettings(
        trackCycle: trackCycle,
        city: city,
        latitude: lat,
        longitude: lon,
      );
}
