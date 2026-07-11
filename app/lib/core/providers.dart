/// Root-level providers: things every feature may need (SPEC section 9.2 —
/// each screen should observe only the state fragment it needs, but a few
/// singletons — the API client, location service — are naturally global).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Like [refresh], but never throws: returns a user-facing error message on
  /// failure (null on success). This is what UI callers should use — the
  /// throwing variant in a bare `onPressed` was an unhandled async exception
  /// waiting to happen.
  Future<String?> tryRefresh() async {
    try {
      state = await _service.currentLocation();
      return null;
    } on LocationPermissionDenied {
      return 'Permissão de localização negada. Conceda o acesso nas '
          'configurações do aparelho para buscar trânsitos.';
    } on LocationServiceDisabled {
      return 'A localização do aparelho está desativada. Ative o GPS e '
          'tente novamente.';
    } catch (_) {
      return 'Não foi possível obter sua localização. Tente novamente.';
    }
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

const _kThemeModeKey = 'astrotransit.theme_mode';
const _kSearchRadiusKey = 'astrotransit.search_radius_km';
const _kSelectedTargetsKey = 'astrotransit.selected_targets';

/// Persists theme, search radius and selected targets across app restarts —
/// otherwise every preference on the settings screen silently resets each
/// launch, which is surprising for a screen whose whole purpose is to save
/// a choice.
Future<void> bootstrapUserPreferences(ProviderContainer container) async {
  final prefs = await SharedPreferences.getInstance();

  final storedTheme = prefs.getString(_kThemeModeKey);
  if (storedTheme != null) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == storedTheme) {
        container.read(themeModeProvider.notifier).state = mode;
        break;
      }
    }
  }
  final storedRadius = prefs.getDouble(_kSearchRadiusKey);
  if (storedRadius != null) {
    container.read(searchRadiusKmProvider.notifier).state = storedRadius;
  }
  final storedTargets = prefs.getStringList(_kSelectedTargetsKey);
  if (storedTargets != null) {
    container.read(selectedTargetsProvider.notifier).state = storedTargets.toSet();
  }

  container.listen(themeModeProvider, (previous, next) {
    prefs.setString(_kThemeModeKey, next.name);
  });
  container.listen(searchRadiusKmProvider, (previous, next) {
    prefs.setDouble(_kSearchRadiusKey, next);
  });
  container.listen(selectedTargetsProvider, (previous, next) {
    prefs.setStringList(_kSelectedTargetsKey, next.toList());
  });
}
