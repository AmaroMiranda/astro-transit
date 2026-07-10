/// Root-level providers: things every feature may need (SPEC section 9.2 —
/// each screen should observe only the state fragment it needs, but a few
/// singletons — the API client, location service — are naturally global).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design_system/app_theme.dart';
import 'location/location_service.dart';
import 'network/api_client.dart';
import '../features/predictions/data/prediction_repository.dart';
import '../shared/models/observer_location.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: kApiBaseUrl);
});

final predictionRepositoryProvider = Provider<PredictionRepository>((ref) {
  return PredictionRepository(ref.watch(apiClientProvider));
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// The observer's current location. Null until the first fix arrives.
final observerLocationProvider =
    StateNotifierProvider<ObserverLocationController, ObserverLocation?>(
  (ref) => ObserverLocationController(ref.watch(locationServiceProvider)),
);

class ObserverLocationController extends StateNotifier<ObserverLocation?> {
  final LocationService _service;

  ObserverLocationController(this._service) : super(null);

  Future<void> refresh() async {
    state = await _service.currentLocation();
  }

  void setManual(ObserverLocation location) {
    state = location;
  }
}

final themeModeProvider = StateProvider<AppThemeMode>((ref) => AppThemeMode.dark);

/// Search radius in km (RF-004): min 20, default 80, max 250.
final searchRadiusKmProvider = StateProvider<double>((ref) => 80.0);

/// Which celestial bodies the user wants to track (RF-002).
final selectedTargetsProvider = StateProvider<Set<String>>((ref) => {'sun', 'moon'});
