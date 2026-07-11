/// Home screen (SPEC section 16.2 / 16.3).
///
/// Headlines the next opportunity when one exists; otherwise shows the
/// "no transit likely" state with useful next actions, never a bare
/// technical panel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/app_theme.dart';
import '../../../core/network/friendly_error.dart';
import '../../../core/providers.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../predictions/domain/prediction_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observer = ref.watch(observerLocationProvider);
    final predictionAsync = ref.watch(predictionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AstroTransit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => context.push('/camera'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(observerLocationProvider.notifier).refresh();
          ref.invalidate(predictionProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusBar(observer: observer),
            const SizedBox(height: 16),
            predictionAsync.when(
              loading: () => const _LoadingCard(),
              error: (err, _) => _ErrorCard(message: friendlyErrorMessage(err)),
              data: (response) {
                if (observer == null) {
                  return const _NoLocationCard();
                }
                if (response == null || response.predictions.isEmpty) {
                  return _NoEventCard(
                    aircraftConsidered: response?.aircraftConsidered ?? 0,
                  );
                }
                return _NextOpportunityCard(prediction: response.predictions.first);
              },
            ),
            const SizedBox(height: 16),
            if (predictionAsync.valueOrNull != null)
              _BodiesRow(bodies: predictionAsync.valueOrNull!.bodies),
            const SizedBox(height: 16),
            _QuickActions(),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final dynamic observer;

  const _StatusBar({required this.observer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocation = observer != null;
    return Row(
      children: [
        Icon(
          hasLocation ? Icons.gps_fixed : Icons.gps_off,
          size: 16,
          color: hasLocation
              ? AstroColors.success
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          hasLocation
              ? 'Localização ativa (±${observer.horizontalAccuracyM?.toStringAsFixed(0) ?? "?"} m)'
              : 'Localização não obtida',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _NextOpportunityCard extends StatelessWidget {
  final TransitPrediction prediction;

  const _NextOpportunityCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = prediction.candidate;
    final bodyLabel = c.body == CelestialBody.moon ? 'Lua' : 'Sol';
    final bodyColor =
        c.body == CelestialBody.moon ? AstroColors.moon : AstroColors.sun;
    final minutes = (c.timeToTransitS / 60).floor();
    final seconds = (c.timeToTransitS % 60).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PRÓXIMA OPORTUNIDADE',
                style: theme.textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1.5, color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  c.body == CelestialBody.moon
                      ? Icons.nightlight_round
                      : Icons.wb_sunny,
                  color: bodyColor,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(bodyLabel, style: theme.textTheme.headlineSmall),
                const Spacer(),
                Text(
                  '${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                  style: AppTheme.countdownStyle(context,
                          color: theme.colorScheme.onSurface)
                      .copyWith(fontSize: 32),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(transitClassLabel(c.transitClass),
                style: theme.textTheme.bodyLarge),
            if (prediction.callsign != null)
              Text(prediction.callsign!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            _ConfidenceChip(confidence: prediction.confidence),
            const SizedBox(height: 4),
            Text(
              'Aeronave a ${(prediction.aircraftDistanceM / 1000).toStringAsFixed(1)} km · '
              'atualizado há ${prediction.dataAgeS.toStringAsFixed(0)}s',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/live-tracking'),
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('Acompanhar'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/radar'),
                  icon: const Icon(Icons.radar),
                  label: const Text('Radar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  final Confidence confidence;

  const _ConfidenceChip({required this.confidence});

  Color _color(BuildContext context) {
    switch (confidence.category) {
      case ConfidenceCategory.veryLow:
      case ConfidenceCategory.low:
        return AstroColors.error;
      case ConfidenceCategory.moderate:
        return AstroColors.warning;
      case ConfidenceCategory.high:
      case ConfidenceCategory.veryHigh:
        return AstroColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Confiança ${confidenceCategoryLabel(confidence.category).toLowerCase()} '
        '· ${confidence.score.toStringAsFixed(0)}%',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _NoEventCard extends StatelessWidget {
  final int aircraftConsidered;

  const _NoEventCard({required this.aircraftConsidered});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nenhum trânsito provável nos próximos minutos.',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Continuamos monitorando $aircraftConsidered aeronave(s) candidata(s) '
              'na região.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/radar'),
                  icon: const Icon(Icons.radar),
                  label: const Text('Abrir radar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.tune),
                  label: const Text('Aumentar raio'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoLocationCard extends StatelessWidget {
  const _NoLocationCard();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Não foi possível obter sua localização.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(observerLocationProvider.notifier).refresh(),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Não foi possível consultar previsões.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BodiesRow extends StatelessWidget {
  final List<CelestialPosition> bodies;

  const _BodiesRow({required this.bodies});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: bodies
          .map((b) => Expanded(child: _BodyTile(position: b)))
          .toList()
          .expand((w) => [w, const SizedBox(width: 12)])
          .toList()
        ..removeLast(),
    );
  }
}

class _BodyTile extends StatelessWidget {
  final CelestialPosition position;

  const _BodyTile({required this.position});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMoon = position.target == CelestialBody.moon;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isMoon ? Icons.nightlight_round : Icons.wb_sunny,
              color: isMoon ? AstroColors.moon : AstroColors.sun,
            ),
            const SizedBox(height: 8),
            Text(isMoon ? 'Lua' : 'Sol', style: theme.textTheme.titleSmall),
            Text(
              position.isVisible
                  ? 'Alt. ${position.altitudeDeg.toStringAsFixed(0)}° · '
                      'Az. ${position.azimuthDeg.toStringAsFixed(0)}°'
                  : 'Abaixo do horizonte',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.push('/map'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Mapa'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.push('/history'),
            icon: const Icon(Icons.history),
            label: const Text('Histórico'),
          ),
        ),
      ],
    );
  }
}
