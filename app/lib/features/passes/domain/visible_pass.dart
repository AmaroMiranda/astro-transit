/// Espelha `VisiblePassOut` / `VisiblePassesOut` do backend.
///
/// Uma passagem VISÍVEL é quando a estação pode ser vista a olho nu (iluminada
/// pelo Sol, com o observador no escuro) — dá para registrá-la mesmo sem
/// trânsito. `isTransit` marca as que também cruzam o Sol/Lua.
library;

import '../../../shared/models/celestial_position.dart';

class VisiblePass {
  final String satelliteId;
  final String satelliteLabel;
  final DateTime startUtc;
  final DateTime culminationUtc;
  final DateTime endUtc;
  final double durationS;
  final double maxElevationDeg;
  final double startAzimuthDeg;
  final double endAzimuthDeg;
  final double approxMagnitude;
  final double tleAgeHours;
  final bool isTransit;
  final CelestialBody? transitBody;

  const VisiblePass({
    required this.satelliteId,
    required this.satelliteLabel,
    required this.startUtc,
    required this.culminationUtc,
    required this.endUtc,
    required this.durationS,
    required this.maxElevationDeg,
    required this.startAzimuthDeg,
    required this.endAzimuthDeg,
    required this.approxMagnitude,
    required this.tleAgeHours,
    required this.isTransit,
    this.transitBody,
  });

  factory VisiblePass.fromJson(Map<String, dynamic> json) {
    final body = json['transit_body'] as String?;
    return VisiblePass(
      satelliteId: json['satellite_id'] as String,
      satelliteLabel: json['satellite_label'] as String,
      startUtc: DateTime.parse(json['start_utc'] as String),
      culminationUtc: DateTime.parse(json['culmination_utc'] as String),
      endUtc: DateTime.parse(json['end_utc'] as String),
      durationS: (json['duration_s'] as num).toDouble(),
      maxElevationDeg: (json['max_elevation_deg'] as num).toDouble(),
      startAzimuthDeg: (json['start_azimuth_deg'] as num).toDouble(),
      endAzimuthDeg: (json['end_azimuth_deg'] as num).toDouble(),
      approxMagnitude: (json['approx_magnitude'] as num).toDouble(),
      tleAgeHours: (json['tle_age_hours'] as num).toDouble(),
      isTransit: json['is_transit'] as bool,
      transitBody: body != null ? celestialBodyFromWire(body) : null,
    );
  }
}

class VisiblePassesResponse {
  final DateTime generatedAtUtc;
  final double hours;
  final List<VisiblePass> passes;

  const VisiblePassesResponse({
    required this.generatedAtUtc,
    required this.hours,
    required this.passes,
  });

  factory VisiblePassesResponse.fromJson(Map<String, dynamic> json) {
    return VisiblePassesResponse(
      generatedAtUtc: DateTime.parse(json['generated_at_utc'] as String),
      hours: (json['hours'] as num).toDouble(),
      passes: (json['passes'] as List<dynamic>)
          .map((p) => VisiblePass.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}
