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

/// Aircraft near the current observer, refreshed every few seconds. Emits an
/// empty list (rather than an error state) on a transient network failure so
/// the map doesn't flash an error every time one poll is slow — the next
/// poll just tries again.
final nearbyAircraftProvider =
    StreamProvider.autoDispose<List<AircraftState>>((ref) async* {
  final repo = ref.watch(aircraftRepositoryProvider);
  final observer = ref.watch(observerLocationProvider);
  final radiusKm = ref.watch(searchRadiusKmProvider);

  if (observer == null) {
    yield const [];
    return;
  }

  while (true) {
    try {
      final result = await repo.nearby(
        latitude: observer.latitude,
        longitude: observer.longitude,
        radiusKm: radiusKm,
      );
      yield result.aircraft;
    } catch (_) {
      yield const [];
    }
    await Future<void>.delayed(_kPollInterval);
  }
});
