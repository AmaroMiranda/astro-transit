/// Talks to `GET /v1/satellites/passes` — multi-day ISS/Tiangong transit planning.
library;

import '../../../core/network/api_client.dart';
import '../../../shared/models/observer_location.dart';
import '../domain/satellite_pass.dart';

class PassesRepository {
  final ApiClient _client;

  PassesRepository(this._client);

  Future<SatellitePassesResponse> upcoming({
    required ObserverLocation observer,
    double hours = 48.0,
    double maxDistanceKm = 30.0,
  }) async {
    final response = await _client.dio.get(
      '/v1/satellites/passes',
      queryParameters: {
        'latitude': observer.latitude,
        'longitude': observer.longitude,
        'altitude_m': observer.altitudeM,
        'hours': hours,
        'max_distance_km': maxDistanceKm,
      },
    );
    return SatellitePassesResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
