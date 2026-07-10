/// Mirrors `CelestialPositionOut` from the backend (RF-002, RF-003).
enum CelestialBody { sun, moon }

CelestialBody celestialBodyFromWire(String value) =>
    value == 'sun' ? CelestialBody.sun : CelestialBody.moon;

String celestialBodyToWire(CelestialBody body) =>
    body == CelestialBody.sun ? 'sun' : 'moon';

class CelestialPosition {
  final CelestialBody target;
  final double azimuthDeg;
  final double altitudeDeg;
  final double angularRadiusDeg;
  final double distanceM;
  final double? illumination;
  final DateTime timestampUtc;

  const CelestialPosition({
    required this.target,
    required this.azimuthDeg,
    required this.altitudeDeg,
    required this.angularRadiusDeg,
    required this.distanceM,
    required this.timestampUtc,
    this.illumination,
  });

  bool get isVisible => altitudeDeg > 0;

  factory CelestialPosition.fromJson(Map<String, dynamic> json) {
    return CelestialPosition(
      target: celestialBodyFromWire(json['target'] as String),
      azimuthDeg: (json['azimuth_deg'] as num).toDouble(),
      altitudeDeg: (json['altitude_deg'] as num).toDouble(),
      angularRadiusDeg: (json['angular_radius_deg'] as num).toDouble(),
      distanceM: (json['distance_m'] as num).toDouble(),
      illumination: (json['illumination'] as num?)?.toDouble(),
      timestampUtc: DateTime.parse(json['timestamp_utc'] as String),
    );
  }
}
