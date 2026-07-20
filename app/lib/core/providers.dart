/// Root-level providers: things every feature may need (SPEC section 9.2 —
/// each screen should observe only the state fragment it needs, but a few
/// singletons — the API client, location service — are naturally global).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_system/app_theme.dart';
import 'location/location_service.dart';
import 'network/api_client.dart';
import 'notifications/notification_service.dart';
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

/// What went wrong fetching a location, and what — if anything — the user
/// can do about it right now (SPEC section 18: errors should offer a way
/// forward, not just a diagnosis).
enum LocationErrorAction { openLocationSettings, openAppSettings, retry, none }

class LocationRefreshError {
  final String message;
  final LocationErrorAction action;

  const LocationRefreshError({required this.message, required this.action});
}

class ObserverLocationController extends StateNotifier<ObserverLocation?> {
  final LocationService _service;

  /// True once the user has explicitly picked a point on the map — in that
  /// mode, automatic GPS refreshes (e.g. on next app open) must not silently
  /// overwrite the chosen point.
  bool isManual = false;

  ObserverLocationController(this._service) : super(null);

  Future<void> refresh() async {
    state = await _service.currentLocation();
    isManual = false;
  }

  /// Like [refresh], but never throws: returns a user-facing error on
  /// failure (null on success). This is what UI callers should use — the
  /// throwing variant in a bare `onPressed` was an unhandled async exception
  /// waiting to happen.
  Future<LocationRefreshError?> tryRefresh() async {
    try {
      state = await _service.currentLocation();
      isManual = false;
      return null;
    } on LocationPermissionDenied {
      return const LocationRefreshError(
        message: 'Permissão de localização negada. Conceda o acesso para '
            'buscar trânsitos a partir da sua posição — ou escolha um ponto '
            'manualmente no mapa.',
        action: LocationErrorAction.retry,
      );
    } on LocationPermissionDeniedForever {
      return const LocationRefreshError(
        message: 'A permissão de localização foi negada permanentemente. '
            'Ative-a nas configurações do aplicativo, ou escolha um ponto '
            'manualmente no mapa.',
        action: LocationErrorAction.openAppSettings,
      );
    } on LocationServiceDisabled {
      return const LocationRefreshError(
        message: 'A localização do aparelho está desativada. Ative o GPS '
            'para buscar a partir da sua posição.',
        action: LocationErrorAction.openLocationSettings,
      );
    } on LocationTimedOut {
      return const LocationRefreshError(
        message: 'O GPS demorou demais para responder. Tente em campo '
            'aberto ou escolha um ponto manualmente no mapa.',
        action: LocationErrorAction.retry,
      );
    } catch (_) {
      return const LocationRefreshError(
        message: 'Não foi possível obter sua localização. Tente novamente.',
        action: LocationErrorAction.retry,
      );
    }
  }

  /// Sets an explicit, user-chosen observer point (e.g. tapped on the map),
  /// decoupled from the device's GPS.
  void setManual(ObserverLocation location) {
    state = location;
    isManual = true;
  }
}

final themeModeProvider = StateProvider<AppThemeMode>((ref) => AppThemeMode.dark);

/// Search radius in km (RF-004): min 20, default 80, max 250.
final searchRadiusKmProvider = StateProvider<double>((ref) => 80.0);

/// Which celestial bodies the user wants to track (RF-002).
final selectedTargetsProvider = StateProvider<Set<String>>((ref) => {'sun', 'moon'});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

/// Opt-in transit alerts (satellite passes + live candidates). Off by default:
/// the user enables it in Configurações, which triggers the permission prompt.
final alertsEnabledProvider = StateProvider<bool>((ref) => false);

/// How many minutes before a scheduled pass the alert should fire.
final alertLeadMinutesProvider = StateProvider<int>((ref) => 10);

const _kThemeModeKey = 'astrotransit.theme_mode';
const _kSearchRadiusKey = 'astrotransit.search_radius_km';
const _kSelectedTargetsKey = 'astrotransit.selected_targets';
const _kAlertsEnabledKey = 'astrotransit.alerts_enabled';
const _kAlertLeadKey = 'astrotransit.alert_lead_minutes';

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
  final storedAlerts = prefs.getBool(_kAlertsEnabledKey);
  if (storedAlerts != null) {
    container.read(alertsEnabledProvider.notifier).state = storedAlerts;
  }
  final storedLead = prefs.getInt(_kAlertLeadKey);
  if (storedLead != null) {
    container.read(alertLeadMinutesProvider.notifier).state = storedLead;
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
  container.listen(alertsEnabledProvider, (previous, next) {
    prefs.setBool(_kAlertsEnabledKey, next);
  });
  container.listen(alertLeadMinutesProvider, (previous, next) {
    prefs.setInt(_kAlertLeadKey, next);
  });
}
