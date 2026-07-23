/// Foto da aeronave pela API pública da Planespotters (grátis, sem chave),
/// indexada pelo hex ICAO24 — o mesmo identificador que já recebemos do ADS-B.
///
/// A foto é um extra: se a aeronave não tiver foto no acervo, ou a rede falhar,
/// devolvemos `null` e a folha de detalhes simplesmente não mostra a seção.
/// Nunca deixamos a busca da foto travar ou quebrar o modal (timeout curto,
/// tudo em try/catch).
///
/// Termos da Planespotters: a foto exige crédito ao fotógrafo e link para a
/// página — por isso guardamos `photographer` e `link`.
library;

import 'package:dio/dio.dart';

class AircraftPhoto {
  final String imageUrl;
  final String photographer;
  final String link;

  const AircraftPhoto({
    required this.imageUrl,
    required this.photographer,
    required this.link,
  });
}

class AircraftPhotoRepository {
  // Dio próprio: a Planespotters é um host externo (não o nosso backend), e
  // queremos um timeout curto para a foto nunca segurar a folha de detalhes.
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      headers: const {
        'Accept': 'application/json',
        // A Planespotters rejeita User-Agent genérico: exige um que identifique
        // o app e um contato. Sem isto a resposta vem com {"error": ...} e
        // nenhuma foto.
        'User-Agent':
            'AstroTransit/1.5 (+https://github.com/AmaroMiranda/astro_transit)',
      },
    ),
  );

  /// Busca a foto pelo hex ICAO24. Devolve `null` quando não há foto ou a
  /// consulta falha — o chamador trata isso como "sem foto".
  Future<AircraftPhoto?> byIcao24(String icao24) async {
    final hex = icao24.trim().toLowerCase();
    if (hex.isEmpty) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://api.planespotters.net/pub/photos/hex/$hex',
      );
      final data = res.data;
      final photos = data?['photos'];
      if (photos is! List || photos.isEmpty) return null;
      final p = photos.first as Map<String, dynamic>;

      // Preferimos a miniatura grande (320px) — nítida o bastante para o card
      // e leve para a rede móvel. Caímos na miniatura pequena se faltar.
      final src = _srcOf(p['thumbnail_large']) ?? _srcOf(p['thumbnail']);
      if (src == null || src.isEmpty) return null;

      return AircraftPhoto(
        imageUrl: src,
        photographer: (p['photographer'] as String?)?.trim().isNotEmpty == true
            ? (p['photographer'] as String).trim()
            : 'Autor desconhecido',
        link: (p['link'] as String?)?.trim() ?? 'https://www.planespotters.net',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _srcOf(dynamic thumb) {
    if (thumb is Map<String, dynamic>) {
      final src = thumb['src'];
      if (src is String) return src;
    }
    return null;
  }
}
