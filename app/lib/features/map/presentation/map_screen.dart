/// Interactive map (RF-021): observer position (GPS or a manually-picked
/// point), live nearby aircraft, and the transit corridor central line for
/// any active prediction (RF-014, RF-015).
///
/// The observer is not locked to the device's GPS fix — tap "escolher no
/// mapa" (or the pin icon) to preview a point anywhere and confirm it as the
/// observer location, e.g. to check a transit from a spot you plan to visit,
/// or when GPS is unavailable.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/design_system/app_theme.dart';
import '../../../core/network/friendly_error.dart';
import '../../../core/providers.dart';
import '../../../core/utils/compass.dart';
import '../../../shared/models/aircraft_state.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/observer_location.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../predictions/domain/prediction_providers.dart';
import '../domain/aircraft_providers.dart';

class MapScreen extends ConsumerStatefulWidget {
  final bool initialPickMode;

  const MapScreen({super.key, this.initialPickMode = false});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  late bool _pickMode;
  ll.LatLng? _previewPoint;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // With no observer at all yet there's nothing else useful to show —
    // default straight into pick mode instead of an empty world map.
    _pickMode = widget.initialPickMode ||
        ref.read(observerLocationProvider) == null;
  }

  void _handleTap(TapPosition tapPosition, ll.LatLng point) {
    if (!_pickMode) return;
    setState(() => _previewPoint = point);
  }

  void _confirmPreview() {
    final point = _previewPoint;
    if (point == null) return;
    ref.read(observerLocationProvider.notifier).setManual(
          ObserverLocation(latitude: point.latitude, longitude: point.longitude),
        );
    ref.invalidate(predictionProvider);
    setState(() {
      _pickMode = false;
      _previewPoint = null;
    });
  }

  void _cancelPreview() {
    setState(() {
      _previewPoint = null;
      if (ref.read(observerLocationProvider) == null) {
        // still nothing to show without a point — stay in pick mode.
      } else {
        _pickMode = false;
      }
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final error = await ref.read(observerLocationProvider.notifier).tryRefresh();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (error == null) {
        _pickMode = false;
        _previewPoint = null;
      }
    });
    if (error == null) {
      ref.invalidate(predictionProvider);
      final observer = ref.read(observerLocationProvider)!;
      _mapController.move(
        ll.LatLng(observer.latitude, observer.longitude),
        13,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final observer = ref.watch(observerLocationProvider);
    final predictionAsync = ref.watch(predictionProvider);
    final aircraftAsync = ref.watch(nearbyAircraftProvider);

    final observerPoint = observer != null
        ? ll.LatLng(observer.latitude, observer.longitude)
        : const ll.LatLng(0, 0);
    final predictionsWithCorridor =
        (predictionAsync.valueOrNull?.predictions ?? [])
            .where((p) => p.corridor != null)
            .toList();
    final aircraft = aircraftAsync.valueOrNull ?? const <AircraftState>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa'),
        actions: [
          IconButton(
            icon: Icon(_pickMode
                ? Icons.close
                : Icons.edit_location_alt_outlined),
            tooltip: _pickMode ? 'Cancelar seleção' : 'Escolher local no mapa',
            onPressed: () => setState(() {
              if (_pickMode) {
                _previewPoint = null;
                _pickMode = false;
              } else {
                _pickMode = true;
              }
            }),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: observerPoint,
              initialZoom: observer != null ? 12 : 2,
              onTap: _handleTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                  if (observer != null)
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
                  for (final a in aircraft)
                    Marker(
                      point: ll.LatLng(a.latitude, a.longitude),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => _showAircraftInfo(context, a),
                        child: Transform.rotate(
                          angle: a.trackDeg * math.pi / 180,
                          child: const Icon(
                            Icons.navigation,
                            color: AstroColors.aircraftCommon,
                            size: 20,
                          ),
                        ),
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
                  if (observer != null)
                    Marker(
                      point: observerPoint,
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.my_location,
                        color: ref.read(observerLocationProvider.notifier).isManual
                            ? AstroColors.warning
                            : Colors.white,
                      ),
                    ),
                  if (_previewPoint != null)
                    Marker(
                      point: _previewPoint!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: AstroColors.warning,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (observer == null && _previewPoint == null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: _Banner(
                  icon: Icons.touch_app_outlined,
                  message: 'Toque em qualquer ponto do mapa para escolher '
                      'de onde observar.',
                ),
              ),
            ),
          if (predictionAsync.hasError)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: _Banner(
                  icon: Icons.cloud_off_outlined,
                  iconColor: AstroColors.error,
                  message: 'Faixa do trânsito indisponível: '
                      '${friendlyErrorMessage(predictionAsync.error!)}',
                ),
              ),
            )
          else if (aircraftAsync.valueOrNull != null &&
              aircraft.isEmpty &&
              observer != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: _Banner(
                  icon: Icons.flight_outlined,
                  message: 'Nenhuma aeronave encontrada na região agora.',
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: _previewPoint != null ? 96 : 12,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 4),
              child: FloatingActionButton.small(
                heroTag: 'use-my-location',
                onPressed: _locating ? null : _useMyLocation,
                child: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.gps_fixed),
              ),
            ),
          ),
          if (_previewPoint != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: AstroColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_previewPoint!.latitude.toStringAsFixed(4)}, '
                            '${_previewPoint!.longitude.toStringAsFixed(4)}',
                          ),
                        ),
                        TextButton(
                          onPressed: _cancelPreview,
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: _confirmPreview,
                          child: const Text('Confirmar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (predictionsWithCorridor.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: _CorridorInfoCard(prediction: predictionsWithCorridor.first),
              ),
            ),
        ],
      ),
    );
  }

  void _showAircraftInfo(BuildContext context, AircraftState aircraft) {
    final altitudeFt = (aircraft.altitudeM * 3.28084).round();
    final speedKt = (aircraft.groundSpeedMps * 1.94384).round();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${aircraft.callsign ?? aircraft.icao24} · '
          '$altitudeFt ft · $speedKt kt · ${compassLabel(aircraft.trackDeg)}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color iconColor;

  const _Banner({
    required this.icon,
    required this.message,
    this.iconColor = AstroColors.info,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _CorridorInfoCard extends StatelessWidget {
  final TransitPrediction prediction;

  const _CorridorInfoCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final corridor = prediction.corridor!;
    final theme = Theme.of(context);
    final distanceKm = corridor.distanceFromObserverM / 1000.0;

    return Card(
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
                      '(${compassLabel(corridor.bearingFromObserverDeg)})'
                  : 'Ponto central a ${distanceKm.toStringAsFixed(1)} km '
                      '(${compassLabel(corridor.bearingFromObserverDeg)})',
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
