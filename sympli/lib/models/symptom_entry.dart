class SymptomEntry {
  const SymptomEntry({
    required this.id,
    required this.symptomId,
    required this.symptomName,
    required this.occurredAt,
    required this.intensity,
    this.note,
  });

  final String id;
  final String symptomId;
  final String symptomName;

  /// always local time
  final DateTime occurredAt;

  /// 1 light, 5 strong
  final int intensity;
  final String? note;

  factory SymptomEntry.fromMap(Map<String, dynamic> row) {
    final symptom = row['symptoms'];
    return SymptomEntry(
      id: row['id'].toString(),
      symptomId: row['symptom_id']?.toString() ?? '',
      symptomName: symptom is Map ? (symptom['name'] as String? ?? '–') : '–',
      occurredAt: DateTime.parse(row['occurred_at'] as String).toLocal(),
      intensity: (row['intensity'] as num?)?.toInt() ?? 3,
      note: row['note'] as String?,
    );
  }
}
