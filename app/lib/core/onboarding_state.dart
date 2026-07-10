import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardedKey = 'astrotransit.has_onboarded';

/// Whether the user has completed onboarding (section 16.7). Defaults to
/// false; [bootstrapOnboardingState] loads the persisted value before the
/// app's first frame so the router's initial redirect is correct.
final hasOnboardedProvider = StateProvider<bool>((ref) => false);

Future<void> bootstrapOnboardingState(ProviderContainer container) async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getBool(_kOnboardedKey) ?? false;
  container.read(hasOnboardedProvider.notifier).state = value;
  container.listen(hasOnboardedProvider, (previous, next) {
    prefs.setBool(_kOnboardedKey, next);
  });
}
