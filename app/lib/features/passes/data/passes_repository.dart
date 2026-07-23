/// Talks to `GET /v1/satellites/passes` — multi-day ISS/Tiangong transit planning.
library;

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/observer_location.dart';
import '../domain/satellite_pass.dart';
import '../domain/visible_pass.dart';

class PassesRepository {
  final ApiClient _client;

  PassesRepository(this._client);

  /// Passagens VISÍVEIS a olho nu (para registro), incluindo as que também são
  /// trânsito (marcadas com `isTransit`).
  Future<VisiblePassesResponse> visible({
    required ObserverLocation observer,
    double hours = 240.0, // 10 dias (padrão dos preditores) — a ISS tem
    // temporadas de visibilidade; janela curta esconde passagens de dias à
    // frente e a lista fica vazia sem motivo aparente.
  }) async {
    final response = await _client.dio.get(
      '/v1/satellites/visible-passes',
      queryParameters: {
        'latitude': observer.latitude,
        'longitude': observer.longitude,
        'altitude_m': observer.altitudeM,
        'hours': hours,
      },
      // A 1ª varredura de 10 dias no free tier leva ~1 min (CPU estrangulada);
      // depois o backend cacheia e responde em ~0,4 s. O backend não trava mais
      // durante o cálculo (roda em thread), então vale esperar em vez de
      // desistir aos 30 s do timeout padrão e mostrar erro para o usuário.
      options: Options(receiveTimeout: const Duration(seconds: 75)),
    );
    return VisiblePassesResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

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
