/// Mirrors `SatellitePassOut` / `SatellitePassesOut` from the backend.
library;

import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';

class SatellitePass {
  final String satelliteId;
  final String satelliteLabel;
  final CelestialBody body;
  final DateTime transitAtUtc;
  final TransitClass transitClass;
  final double durationS;
  final double elevationDeg;
  final double azimuthDeg;
  final double slantRangeM;
  final double minSeparationDeg;
  final double tleAgeHours;
  final TransitCorridor? corridor;

  const SatellitePass({
    required this.satelliteId,
    required this.satelliteLabel,
    required this.body,
    required this.transitAtUtc,
    required this.transitClass,
    required this.durationS,
    required this.elevationDeg,
    required this.azimuthDeg,
    required this.slantRangeM,
    required this.minSeparationDeg,
    required this.tleAgeHours,
    this.corridor,
  });

  /// True when the transit is visible from the observer's own position
  /// (otherwise it happens along the nearby centerline — travel required).
  bool get atObserver =>
      transitClass != TransitClass.none && transitClass != TransitClass.approach;

  factory SatellitePass.fromJson(Map<String, dynamic> json) {
    final rawCorridor = json['corridor'] as Map<String, dynamic>?;
    return SatellitePass(
      satelliteId: json['satellite_id'] as String,
      satelliteLabel: json['satellite_label'] as String,
      body: celestialBodyFromWire(json['body'] as String),
      transitAtUtc: DateTime.parse(json['transit_at_utc'] as String),
      transitClass: transitClassFromWire(json['transit_class'] as String),
      durationS: (json['duration_s'] as num).toDouble(),
      elevationDeg: (json['elevation_deg'] as num).toDouble(),
      azimuthDeg: (json['azimuth_deg'] as num).toDouble(),
      slantRangeM: (json['slant_range_m'] as num).toDouble(),
      minSeparationDeg: (json['min_separation_deg'] as num).toDouble(),
      tleAgeHours: (json['tle_age_hours'] as num).toDouble(),
      corridor: rawCorridor != null ? TransitCorridor.fromJson(rawCorridor) : null,
    );
  }
}

class SatellitePassesResponse {
  final DateTime generatedAtUtc;
  final double hours;
  final List<SatellitePass> passes;

  const SatellitePassesResponse({
    required this.generatedAtUtc,
    required this.hours,
    required this.passes,
  });

  factory SatellitePassesResponse.fromJson(Map<String, dynamic> json) {
    return SatellitePassesResponse(
      generatedAtUtc: DateTime.parse(json['generated_at_utc'] as String),
      hours: (json['hours'] as num).toDouble(),
      passes: (json['passes'] as List<dynamic>)
          .map((p) => SatellitePass.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}
