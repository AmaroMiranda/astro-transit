/// Busca por nome de lugar (geocoding) via Nominatim, o serviço gratuito do
/// OpenStreetMap. Sem chave de API.
///
/// A política de uso do Nominatim exige um User-Agent identificável e no
/// máximo 1 requisição por segundo — o app respeita ambos: UA próprio e a
/// busca só dispara ao SUBMETER o campo (não a cada tecla).
library;

import 'package:dio/dio.dart';

class GeocodeResult {
  final String displayName;
  final double latitude;
  final double longitude;

  const GeocodeResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

class GeocodingService {
  final Dio _dio;

  GeocodingService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
              headers: const {
                // Nominatim recusa requisições sem UA identificável.
                'User-Agent': 'AstroTransit/1.0 (transit finder app)',
              },
            ));

  /// Até [limit] lugares que casam com [query]. Lista vazia se nada casar;
  /// lança em erro de rede (o chamador traduz para mensagem amigável).
  Future<List<GeocodeResult>> search(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final res = await _dio.get<List<dynamic>>(
      'https://nominatim.openstreetmap.org/search',
      queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'limit': limit,
        'addressdetails': 0,
      },
    );
    final data = res.data ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map((m) => GeocodeResult(
              displayName: (m['display_name'] as String?) ?? q,
              latitude: double.parse(m['lat'] as String),
              longitude: double.parse(m['lon'] as String),
            ))
        .toList();
  }
}
