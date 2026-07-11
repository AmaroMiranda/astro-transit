/// Talks to `GET /v1/aircraft/nearby` (section 14) for live map markers.
library;

import '../../../core/network/api_client.dart';
import '../../../shared/models/aircraft_state.dart';

class AircraftRepository {
  final ApiClient _client;

  AircraftRepository(this._client);

  Future<NearbyAircraftResponse> nearby({
    required double latitude,
    required double longitude,
    double radiusKm = 80.0,
  }) async {
    final response = await _client.dio.get(
      '/v1/aircraft/nearby',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': radiusKm,
      },
    );
    return NearbyAircraftResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
