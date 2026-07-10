/// Local history record (RF-028). Persisted as JSON via SharedPreferences for
/// the MVP; a proper embedded DB (Drift/Isar) is a drop-in swap later since
/// this type has no persistence-layer dependencies of its own.
enum HistoryStatus { captured, missed, notObserved, cloudBlocked, mispredicted }

String historyStatusLabel(HistoryStatus s) {
  switch (s) {
    case HistoryStatus.captured:
      return 'Capturado';
    case HistoryStatus.missed:
      return 'Perdido';
    case HistoryStatus.notObserved:
      return 'Não observado';
    case HistoryStatus.cloudBlocked:
      return 'Bloqueado por nuvens';
    case HistoryStatus.mispredicted:
      return 'Previsão incorreta';
  }
}

class HistoryEntry {
  final String id;
  final DateTime dateTimeUtc;
  final double latitude;
  final double longitude;
  final String body; // 'sun' | 'moon'
  final String? icao24;
  final String? callsign;
  final double minSeparationDeg;
  final double confidenceScore;
  final String provider;
  final HistoryStatus status;

  const HistoryEntry({
    required this.id,
    required this.dateTimeUtc,
    required this.latitude,
    required this.longitude,
    required this.body,
    required this.minSeparationDeg,
    required this.confidenceScore,
    required this.provider,
    required this.status,
    this.icao24,
    this.callsign,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date_time_utc': dateTimeUtc.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'body': body,
        'icao24': icao24,
        'callsign': callsign,
        'min_separation_deg': minSeparationDeg,
        'confidence_score': confidenceScore,
        'provider': provider,
        'status': status.name,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id'] as String,
      dateTimeUtc: DateTime.parse(json['date_time_utc'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      body: json['body'] as String,
      icao24: json['icao24'] as String?,
      callsign: json['callsign'] as String?,
      minSeparationDeg: (json['min_separation_deg'] as num).toDouble(),
      confidenceScore: (json['confidence_score'] as num).toDouble(),
      provider: json['provider'] as String,
      status: HistoryStatus.values.firstWhere((s) => s.name == json['status']),
    );
  }
}
