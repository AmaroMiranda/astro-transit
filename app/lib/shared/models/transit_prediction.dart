/// Mirrors `TransitPredictionOut` / `TransitCandidateOut` from the backend
/// (RF-012, RF-016).
library;

import 'celestial_position.dart';

enum TransitClass { central, nearCentral, partial, graze, approach, none }

TransitClass transitClassFromWire(String value) {
  switch (value) {
    case 'central':
      return TransitClass.central;
    case 'near_central':
      return TransitClass.nearCentral;
    case 'partial':
      return TransitClass.partial;
    case 'graze':
      return TransitClass.graze;
    case 'approach':
      return TransitClass.approach;
    default:
      return TransitClass.none;
  }
}

String transitClassLabel(TransitClass c) {
  switch (c) {
    case TransitClass.central:
      return 'Trânsito central';
    case TransitClass.nearCentral:
      return 'Trânsito quase central';
    case TransitClass.partial:
      return 'Trânsito parcial';
    case TransitClass.graze:
      return 'Passagem pela borda';
    case TransitClass.approach:
      return 'Aproximação';
    case TransitClass.none:
      return 'Sem trânsito';
  }
}

enum ConfidenceCategory { veryLow, low, moderate, high, veryHigh }

ConfidenceCategory confidenceCategoryFromWire(String value) {
  switch (value) {
    case 'very_low':
      return ConfidenceCategory.veryLow;
    case 'low':
      return ConfidenceCategory.low;
    case 'moderate':
      return ConfidenceCategory.moderate;
    case 'high':
      return ConfidenceCategory.high;
    default:
      return ConfidenceCategory.veryHigh;
  }
}

String confidenceCategoryLabel(ConfidenceCategory c) {
  switch (c) {
    case ConfidenceCategory.veryLow:
      return 'Muito baixa';
    case ConfidenceCategory.low:
      return 'Baixa';
    case ConfidenceCategory.moderate:
      return 'Moderada';
    case ConfidenceCategory.high:
      return 'Alta';
    case ConfidenceCategory.veryHigh:
      return 'Muito alta';
  }
}

class ConfidenceFactor {
  final String name;
  final double penalty;
  final String detail;

  const ConfidenceFactor({
    required this.name,
    required this.penalty,
    required this.detail,
  });

  factory ConfidenceFactor.fromJson(Map<String, dynamic> json) {
    return ConfidenceFactor(
      name: json['name'] as String,
      penalty: (json['penalty'] as num).toDouble(),
      detail: json['detail'] as String,
    );
  }
}

class Confidence {
  final double score;
  final ConfidenceCategory category;
  final List<ConfidenceFactor> factors;

  const Confidence({
    required this.score,
    required this.category,
    required this.factors,
  });

  factory Confidence.fromJson(Map<String, dynamic> json) {
    return Confidence(
      score: (json['score'] as num).toDouble(),
      category: confidenceCategoryFromWire(json['category'] as String),
      factors: (json['factors'] as List<dynamic>)
          .map((f) => ConfidenceFactor.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TransitCandidate {
  final String icao24;
  final CelestialBody body;
  final double timeToTransitS;
  final double minSeparationDeg;
  final double bodyRadiusDeg;
  final double aircraftRadiusDeg;
  final TransitClass transitClass;
  final double aircraftAzimuthDeg;
  final double aircraftAltitudeDeg;

  const TransitCandidate({
    required this.icao24,
    required this.body,
    required this.timeToTransitS,
    required this.minSeparationDeg,
    required this.bodyRadiusDeg,
    required this.aircraftRadiusDeg,
    required this.transitClass,
    required this.aircraftAzimuthDeg,
    required this.aircraftAltitudeDeg,
  });

  factory TransitCandidate.fromJson(Map<String, dynamic> json) {
    return TransitCandidate(
      icao24: json['icao24'] as String,
      body: celestialBodyFromWire(json['body'] as String),
      timeToTransitS: (json['time_to_transit_s'] as num).toDouble(),
      minSeparationDeg: (json['min_separation_deg'] as num).toDouble(),
      bodyRadiusDeg: (json['body_radius_deg'] as num).toDouble(),
      aircraftRadiusDeg: (json['aircraft_radius_deg'] as num).toDouble(),
      transitClass: transitClassFromWire(json['transit_class'] as String),
      aircraftAzimuthDeg: (json['aircraft_azimuth_deg'] as num).toDouble(),
      aircraftAltitudeDeg: (json['aircraft_altitude_deg'] as num).toDouble(),
    );
  }
}

class TransitCorridor {
  final double centerLatitude;
  final double centerLongitude;
  final double halfWidthM;
  final double distanceFromObserverM;
  final double bearingFromObserverDeg;

  const TransitCorridor({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.halfWidthM,
    required this.distanceFromObserverM,
    required this.bearingFromObserverDeg,
  });

  factory TransitCorridor.fromJson(Map<String, dynamic> json) {
    return TransitCorridor(
      centerLatitude: (json['center_latitude'] as num).toDouble(),
      centerLongitude: (json['center_longitude'] as num).toDouble(),
      halfWidthM: (json['half_width_m'] as num).toDouble(),
      distanceFromObserverM: (json['distance_from_observer_m'] as num).toDouble(),
      bearingFromObserverDeg: (json['bearing_from_observer_deg'] as num).toDouble(),
    );
  }
}

class TransitPrediction {
  final TransitCandidate candidate;
  final Confidence confidence;
  final String? callsign;
  final double aircraftDistanceM;
  final double dataAgeS;
  final TransitCorridor? corridor;

  const TransitPrediction({
    required this.candidate,
    required this.confidence,
    required this.aircraftDistanceM,
    required this.dataAgeS,
    this.callsign,
    this.corridor,
  });

  factory TransitPrediction.fromJson(Map<String, dynamic> json) {
    final rawCorridor = json['corridor'] as Map<String, dynamic>?;
    return TransitPrediction(
      candidate:
          TransitCandidate.fromJson(json['candidate'] as Map<String, dynamic>),
      confidence:
          Confidence.fromJson(json['confidence'] as Map<String, dynamic>),
      callsign: json['callsign'] as String?,
      aircraftDistanceM: (json['aircraft_distance_m'] as num).toDouble(),
      dataAgeS: (json['data_age_s'] as num).toDouble(),
      corridor: rawCorridor != null ? TransitCorridor.fromJson(rawCorridor) : null,
    );
  }
}

class PredictionResponse {
  final DateTime generatedAtUtc;
  final String provider;
  final bool dataDegraded;
  final int aircraftConsidered;
  final List<CelestialPosition> bodies;
  final List<TransitPrediction> predictions;

  const PredictionResponse({
    required this.generatedAtUtc,
    required this.provider,
    required this.dataDegraded,
    required this.aircraftConsidered,
    required this.bodies,
    required this.predictions,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    return PredictionResponse(
      generatedAtUtc: DateTime.parse(json['generated_at_utc'] as String),
      provider: json['provider'] as String,
      dataDegraded: json['data_degraded'] as bool,
      aircraftConsidered: json['aircraft_considered'] as int,
      bodies: (json['bodies'] as List<dynamic>)
          .map((b) => CelestialPosition.fromJson(b as Map<String, dynamic>))
          .toList(),
      predictions: (json['predictions'] as List<dynamic>)
          .map((p) => TransitPrediction.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}
