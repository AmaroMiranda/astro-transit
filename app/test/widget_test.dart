import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astrotransit/core/onboarding_state.dart';
import 'package:astrotransit/main.dart';

void main() {
  testWidgets('App boots into onboarding on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    await bootstrapOnboardingState(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AstroTransitApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bem-vindo ao AstroTransit'), findsOneWidget);
  });
}
