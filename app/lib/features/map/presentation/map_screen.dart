/// Map view (RF-021): observer position, transit corridor central line and
/// best nearby observation point, with recommended direction/distance
/// (RF-014, RF-015).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/design_system/app_theme.dart';
import '../../../core/providers.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../predictions/domain/prediction_providers.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observer = ref.watch(observerLocationProvider);
    final predictionAsync = ref.watch(predictionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mapa')),
      body: observer == null
          ? const Center(child: Text('Localização indisponível.'))
          : predictionAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (response) {
                final predictionsWithCorridor = (response?.predictions ?? [])
                    .where((p) => p.corridor != null)
                    .toList();
                final observerPoint = ll.LatLng(observer.latitude, observer.longitude);

                return Column(
                  children: [
                    Expanded(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: observerPoint,
                          initialZoom: 12,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.astrotransit.astrotransit',
                          ),
                          CircleLayer(
                            circles: [
                              for (final p in predictionsWithCorridor)
                                CircleMarker(
                                  point: ll.LatLng(
                                    p.corridor!.centerLatitude,
                                    p.corridor!.centerLongitude,
                                  ),
                                  radius: p.corridor!.halfWidthM,
                                  useRadiusInMeter: true,
                                  color: (p.candidate.body == CelestialBody.moon
                                          ? AstroColors.moon
                                          : AstroColors.sun)
                                      .withValues(alpha: 0.18),
                                  borderColor: p.candidate.body == CelestialBody.moon
                                      ? AstroColors.moon
                                      : AstroColors.sun,
                                  borderStrokeWidth: 2,
                                ),
                            ],
                          ),
                          PolylineLayer(
                            polylines: [
                              for (final p in predictionsWithCorridor)
                                Polyline(
                                  points: [
                                    observerPoint,
                                    ll.LatLng(
                                      p.corridor!.centerLatitude,
                                      p.corridor!.centerLongitude,
                                    ),
                                  ],
                                  color: AstroColors.aircraftCandidate,
                                  strokeWidth: 2,
                                  pattern: const StrokePattern.dotted(),
                                ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: observerPoint,
                                width: 36,
                                height: 36,
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                ),
                              ),
                              for (final p in predictionsWithCorridor)
                                Marker(
                                  point: ll.LatLng(
                                    p.corridor!.centerLatitude,
                                    p.corridor!.centerLongitude,
                                  ),
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.center_focus_strong,
                                    color: p.candidate.body == CelestialBody.moon
                                        ? AstroColors.moon
                                        : AstroColors.sun,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (predictionsWithCorridor.isNotEmpty)
                      _CorridorInfoCard(prediction: predictionsWithCorridor.first)
                    else
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Nenhuma faixa de trânsito disponível no momento.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _CorridorInfoCard extends StatelessWidget {
  final TransitPrediction prediction;

  const _CorridorInfoCard({required this.prediction});

  String _compassLabel(double azimuthDeg) {
    const labels = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];
    final index = (((azimuthDeg % 360) + 22.5) / 45).floor() % 8;
    return labels[index];
  }

  @override
  Widget build(BuildContext context) {
    final corridor = prediction.corridor!;
    final theme = Theme.of(context);
    final distanceKm = corridor.distanceFromObserverM / 1000.0;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Faixa do trânsito', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              distanceKm < 1
                  ? 'Ponto central a ${corridor.distanceFromObserverM.toStringAsFixed(0)} m '
                      '(${_compassLabel(corridor.bearingFromObserverDeg)})'
                  : 'Ponto central a ${distanceKm.toStringAsFixed(1)} km '
                      '(${_compassLabel(corridor.bearingFromObserverDeg)})',
            ),
            Text(
              'Largura aproximada da faixa: '
              '${(corridor.halfWidthM * 2).toStringAsFixed(0)} m',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Estimativa aproximada — não se desloque nos últimos segundos '
              'antes do trânsito.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
