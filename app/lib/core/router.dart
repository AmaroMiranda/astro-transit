import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/dashboard/presentation/placeholder_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/live_tracking/presentation/live_tracking_screen.dart';
import '../features/map/presentation/map_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/radar/presentation/radar_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'onboarding_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final onboarded = ref.read(hasOnboardedProvider);
      final goingToOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded && !goingToOnboarding) return '/onboarding';
      if (onboarded && goingToOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => OnboardingScreen(
          onDone: () {
            ref.read(hasOnboardedProvider.notifier).state = true;
            context.go('/');
          },
        ),
      ),
      GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/radar', builder: (context, state) => const RadarScreen()),
      GoRoute(
        path: '/live-tracking',
        builder: (context, state) => const LiveTrackingScreen(),
      ),
      GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
      GoRoute(
        path: '/camera',
        builder: (context, state) => const PlaceholderScreen(
          title: 'Câmera',
          message: 'Overlay de câmera chega na etapa seguinte.',
        ),
      ),
    ],
  );
});
