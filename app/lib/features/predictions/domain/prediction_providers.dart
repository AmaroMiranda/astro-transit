import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';

/// One-shot prediction fetch, refreshed whenever the observer, radius or
/// selected targets change (SPEC section 10, steps 1-16).
final predictionProvider = FutureProvider<PredictionResponse?>((ref) async {
  final observer = ref.watch(observerLocationProvider);
  if (observer == null) return null;

  final radiusKm = ref.watch(searchRadiusKmProvider);
  final targetNames = ref.watch(selectedTargetsProvider);
  final targets = targetNames.map(celestialBodyFromWire).toList();
  if (targets.isEmpty) return null;

  final repo = ref.watch(predictionRepositoryProvider);
  return repo.predict(observer: observer, targets: targets, maxRadiusKm: radiusKm);
});

/// The soonest actionable prediction, if any — what the dashboard headlines
/// (SPEC section 16.2 "Próxima oportunidade").
final nextPredictionProvider = Provider<TransitPrediction?>((ref) {
  final response = ref.watch(predictionProvider).valueOrNull;
  if (response == null || response.predictions.isEmpty) return null;
  return response.predictions.first;
});
