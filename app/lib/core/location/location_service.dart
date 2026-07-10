/// Observer location acquisition (RF-001).
///
/// Wraps `geolocator` behind a narrow interface so the rest of the app depends
/// only on [ObserverLocation] streams/futures, not the plugin directly.
library;

import 'package:geolocator/geolocator.dart';

import '../../shared/models/observer_location.dart';

class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
}

class LocationServiceDisabled implements Exception {
  const LocationServiceDisabled();
}

class LocationService {
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabled();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }
    return true;
  }

  Future<ObserverLocation> currentLocation() async {
    await ensurePermission();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    return ObserverLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeM: position.altitude,
      horizontalAccuracyM: position.accuracy,
    );
  }

  /// Position stream for active tracking (RF-001: recalculate on movement).
  /// [distanceFilterM] follows the SPEC's active/passive thresholds (10 m / 50 m).
  Stream<ObserverLocation> watch({double distanceFilterM = 10.0}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterM.round(),
      ),
    ).map(
      (p) => ObserverLocation(
        latitude: p.latitude,
        longitude: p.longitude,
        altitudeM: p.altitude,
        horizontalAccuracyM: p.accuracy,
      ),
    );
  }
}
