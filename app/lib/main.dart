import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design_system/app_theme.dart';
import 'core/onboarding_state.dart';
import 'core/providers.dart';
import 'core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  await bootstrapOnboardingState(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AstroTransitApp(),
    ),
  );
}

class AstroTransitApp extends ConsumerWidget {
  const AstroTransitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AstroTransit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forMode(themeMode),
      routerConfig: router,
    );
  }
}
