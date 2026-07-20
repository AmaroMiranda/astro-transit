/// Observer location acquisition (RF-001).
///
/// Wraps `geolocator` behind a narrow interface so the rest of the app depends
/// only on [ObserverLocation] streams/futures, not the plugin directly.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/models/observer_location.dart';

class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
}

class LocationPermissionDeniedForever implements Exception {
  const LocationPermissionDeniedForever();
}

class LocationServiceDisabled implements Exception {
  const LocationServiceDisabled();
}

class LocationTimedOut implements Exception {
  const LocationTimedOut();
}

class LocationService {
  static const _settingsChannel =
      MethodChannel('astrotransit/location_settings');

  /// Shows the platform's own "turn on device location" dialog inside the app
  /// (Google Play Services SettingsClient, wired in MainActivity.kt) instead
  /// of sending the user to the system settings screen. Returns true when the
  /// service ended up enabled.
  Future<bool> _tryEnableLocationService() async {
    try {
      final enabled =
          await _settingsChannel.invokeMethod<bool>('requestEnable');
      return enabled ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // iOS / tests: no native handler — caller falls back to settings flow.
      return false;
    }
  }

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      // In-app enable dialog first; only fail toward "open settings" when the
      // user declined it or the dialog isn't available on this device.
      if (!await _tryEnableLocationService()) {
        throw const LocationServiceDisabled();
      }
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedForever();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionDenied();
    }
    return true;
  }

  Future<ObserverLocation> currentLocation() async {
    await ensurePermission();
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Without a limit, getCurrentPosition() can hang forever when the
          // service reports "enabled" but no fix ever arrives (weak signal,
          // indoors, some emulators) — the UI would show a spinner
          // indefinitely with no error. A last-known-position fallback below
          // covers the common case where a fresh fix simply takes too long.
          timeLimit: Duration(seconds: 15),
        ),
      );
      return _toObserverLocation(position);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return _toObserverLocation(last);
      }
      throw const LocationTimedOut();
    }
  }

  ObserverLocation _toObserverLocation(Position position) {
    return ObserverLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeM: position.altitude,
      horizontalAccuracyM: position.accuracy,
    );
  }

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  Future<void> openAppSettings() => Geolocator.openAppSettings();

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
