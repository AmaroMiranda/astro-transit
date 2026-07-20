/// Providers for the multi-day satellite pass planner + alert scheduling.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/models/celestial_position.dart';
import '../data/passes_repository.dart';
import 'satellite_pass.dart';

final passesRepositoryProvider = Provider<PassesRepository>((ref) {
  return PassesRepository(ref.watch(apiClientProvider));
});

/// Upcoming satellite transits (48 h, centerline within 30 km) for the current
/// observer. Refreshes when the observer moves.
final upcomingPassesProvider =
    FutureProvider<SatellitePassesResponse?>((ref) async {
  final observer = ref.watch(observerLocationProvider);
  if (observer == null) return null;
  final repo = ref.watch(passesRepositoryProvider);
  return repo.upcoming(observer: observer);
});

/// Keeps the scheduled local notifications in sync with the latest pass list
/// and the user's alert preferences. Watch this from the passes screen (or any
/// long-lived widget) — it re-schedules whenever passes / toggle / lead change.
final passAlertsSchedulerProvider = Provider<void>((ref) {
  final enabled = ref.watch(alertsEnabledProvider);
  final lead = ref.watch(alertLeadMinutesProvider);
  final passesAsync = ref.watch(upcomingPassesProvider);
  final notifications = ref.watch(notificationServiceProvider);

  final passes = passesAsync.valueOrNull?.passes;
  if (!enabled) {
    notifications.cancelPassAlerts();
    return;
  }
  if (passes == null) return;

  notifications.reschedulePassAlerts([
    for (final p in passes)
      (
        whenUtc: p.transitAtUtc.subtract(Duration(minutes: lead)),
        title:
            '${p.satelliteLabel} cruza ${p.body == CelestialBody.sun ? "o Sol" : "a Lua"}',
        body: p.atObserver
            ? 'Trânsito no seu local em $lead min — prepare o equipamento!'
            : 'Faixa a ${((p.corridor?.distanceFromObserverM ?? 0) / 1000).toStringAsFixed(0)} km '
                'em $lead min. Veja a linha central no app.',
      ),
  ]);
});
