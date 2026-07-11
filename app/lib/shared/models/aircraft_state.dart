/// Mirrors `AircraftOut` / `NearbyOut` from the backend (`GET /v1/aircraft/nearby`).
library;

class AircraftState {
  final String icao24;
  final String? callsign;
  final double latitude;
  final double longitude;
  final double altitudeM;
  final double groundSpeedMps;
  final double trackDeg;
  final double verticalRateMps;
  final bool onGround;
  final String category;
  final double ageS;

  const AircraftState({
    required this.icao24,
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.groundSpeedMps,
    required this.trackDeg,
    required this.verticalRateMps,
    required this.onGround,
    required this.category,
    required this.ageS,
    this.callsign,
  });

  factory AircraftState.fromJson(Map<String, dynamic> json) {
    return AircraftState(
      icao24: json['icao24'] as String,
      callsign: (json['callsign'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['callsign'] as String).trim(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitudeM: (json['altitude_m'] as num).toDouble(),
      groundSpeedMps: (json['ground_speed_mps'] as num).toDouble(),
      trackDeg: (json['track_deg'] as num).toDouble(),
      verticalRateMps: (json['vertical_rate_mps'] as num).toDouble(),
      onGround: json['on_ground'] as bool,
      category: json['category'] as String,
      ageS: (json['age_s'] as num).toDouble(),
    );
  }
}

class NearbyAircraftResponse {
  final String provider;
  final bool dataDegraded;
  final List<AircraftState> aircraft;

  const NearbyAircraftResponse({
    required this.provider,
    required this.dataDegraded,
    required this.aircraft,
  });

  factory NearbyAircraftResponse.fromJson(Map<String, dynamic> json) {
    return NearbyAircraftResponse(
      provider: json['provider'] as String,
      dataDegraded: json['data_degraded'] as bool,
      aircraft: (json['aircraft'] as List<dynamic>)
          .map((a) => AircraftState.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}
