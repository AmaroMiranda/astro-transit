/// Live aircraft polling for the interactive map (RF-021-style "aviões no
/// mapa"). Polls on a fixed cadence rather than opening a second WebSocket —
/// simpler, and the map doesn't need sub-second freshness.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/models/aircraft_state.dart';
import '../data/aircraft_photo_repository.dart';
import '../data/aircraft_repository.dart';

const _kPollInterval = Duration(seconds: 6);

/// Quanto tempo uma aeronave continua no radar depois de sumir de um poll.
/// Cobre ~2 ciclos e meio de polling: absorve o jitter natural de cobertura
/// ADS-B e polls degradados (um provedor que estourou o timeout, ou uma falha
/// de rede transitória) sem o alvo piscar. Um avião só some de vez se ficar
/// ausente por TODO esse intervalo.
const _kTrackTtl = Duration(seconds: 15);

final aircraftRepositoryProvider = Provider<AircraftRepository>((ref) {
  return AircraftRepository(ref.watch(apiClientProvider));
});

final aircraftPhotoRepositoryProvider = Provider<AircraftPhotoRepository>((ref) {
  return AircraftPhotoRepository();
});

/// Foto da aeronave (Planespotters) por hex ICAO24. Sem `autoDispose`: a foto
/// de uma matrícula não muda, então mantemos em cache enquanto o app vive —
/// reabrir a folha do mesmo avião não refaz a consulta.
final aircraftPhotoProvider =
    FutureProvider.family<AircraftPhoto?, String>((ref, icao24) async {
  return ref.watch(aircraftPhotoRepositoryProvider).byIcao24(icao24);
});

/// Aircraft near the current observer, refreshed every few seconds.
///
/// Usa "coasting" de alvos (padrão de radar): mantemos o último estado de cada
/// aeronave por [_kTrackTtl] após vê-la pela última vez. Assim, um avião que
/// some de UM poll — por falha de rede transitória, provedor degradado, ou um
/// buraco momentâneo de cobertura ADS-B — NÃO pisca no mapa/radar; ele só
/// desaparece se ficar ausente por todo o TTL.
///
/// Isto corrige o bug do "avião aparecendo e sumindo": antes, qualquer poll
/// lento/falho fazia `yield []`, apagando TODAS as aeronaves por um ciclo até
/// o próximo poll bem-sucedido trazê-las de volta.
final nearbyAircraftProvider =
    StreamProvider.autoDispose<List<AircraftState>>((ref) async* {
  final repo = ref.watch(aircraftRepositoryProvider);
  final observer = ref.watch(observerLocationProvider);
  final radiusKm = ref.watch(searchRadiusKmProvider);

  if (observer == null) {
    yield const [];
    return;
  }

  // icao24 -> (último estado conhecido, instante em que foi visto).
  final tracks = <String, ({AircraftState state, DateTime seen})>{};

  while (true) {
    try {
      final result = await repo.nearby(
        latitude: observer.latitude,
        longitude: observer.longitude,
        radiusKm: radiusKm,
      );
      final now = DateTime.now();
      for (final a in result.aircraft) {
        tracks[a.icao24] = (state: a, seen: now);
      }
    } catch (_) {
      // Poll transitório falhou: NÃO apagamos os alvos. Eles seguem no radar
      // com a última posição conhecida e envelhecem pelo TTL abaixo.
    }

    // Remove alvos ausentes há mais que o TTL (também esvazia o radar de vez
    // se o backend ficar realmente indisponível por > _kTrackTtl).
    final cutoff = DateTime.now().subtract(_kTrackTtl);
    tracks.removeWhere((_, t) => t.seen.isBefore(cutoff));

    yield tracks.values.map((t) => t.state).toList();
    await Future<void>.delayed(_kPollInterval);
  }
});
