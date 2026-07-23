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
import '../../../core/utils/geo.dart';
import '../../../core/providers.dart';
import '../../../core/utils/compass.dart';
import '../../../shared/models/aircraft_state.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/observer_location.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../../shared/widgets/plane_icon.dart';
import '../../predictions/domain/prediction_providers.dart';
import '../data/geocoding_service.dart';
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
  // Estilo do basemap: escolha DELIBERADA do usuário no botão do mapa, não
  // acoplada ao tema do app (mapa de rua claro é mais legível para achar um
  // lugar mesmo com o app em modo escuro). Começa escuro, casando o visual.
  bool _mapDark = true;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _geocoder = GeocodingService();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final results = await _geocoder.search(q, limit: 1);
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nenhum lugar encontrado para "$q".')),
        );
        return;
      }
      final r = results.first;
      final point = ll.LatLng(r.latitude, r.longitude);
      _searchFocus.unfocus();
      _mapController.move(point, math.max(_mapController.camera.zoom, 12));
      // Deixa o resultado pronto para virar observador (mesma UX do toque):
      // entra em modo de seleção com o ponto já previsto, e o usuário confirma.
      setState(() {
        _pickMode = true;
        _previewPoint = point;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível buscar o local agora.')),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

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
    final predictions =
        predictionAsync.valueOrNull?.predictions ?? const <TransitPrediction>[];
    // Aircraft that have a probable transit — used to mark them apart from the
    // rest of the traffic on the map (identified by ICAO24).
    final candidateIcaos = <String>{
      for (final p in predictions)
        if (!p.isSatellite) p.candidate.icao24,
    };
    final predictionsWithCorridor =
        predictions.where((p) => p.corridor != null).toList();
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
              // Basemap: alternável pelo usuário (botão no mapa), independente
              // do tema do app. ESCURO = CARTO Dark Matter (casa o visual do
              // app). CLARO = OpenStreetMap padrão — ruas, cidades e relevo,
              // "cara de mapa" de verdade, o que o usuário pediu. Cada um tem
              // sua atribuição obrigatória (trocada junto, abaixo).
              if (_mapDark)
                TileLayer(
                  key: const ValueKey('carto-dark'),
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  retinaMode: RetinaMode.isHighDensity(context),
                  userAgentPackageName: 'com.astrotransit.astrotransit',
                )
              else
                TileLayer(
                  key: const ValueKey('osm-standard'),
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
                  // Trajetória projetada de cada aeronave candidata: uma seta a
                  // partir da posição atual, ao longo do rumo (track), ~40 km à
                  // frente (RF: "linha mostrando a trajetória do avião
                  // candidato"). É uma extrapolação em rumo constante — mostra
                  // PARA ONDE ele vai, não uma previsão de rota curva.
                  for (final a in aircraft)
                    if (candidateIcaos.contains(a.icao24))
                      Polyline(
                        points: _trajectory(
                            ll.LatLng(a.latitude, a.longitude), a.trackDeg, 40),
                        color: AstroColors.aircraftCandidate
                            .withValues(alpha: 0.75),
                        strokeWidth: 2.5,
                      ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Common traffic first, so highlighted candidates draw on top.
                  // width/height dão espaço à etiqueta do ID abaixo do ícone;
                  // alignment.topCenter mantém o ÍCONE ancorado na posição real
                  // (a etiqueta cresce para baixo, não desloca o avião).
                  for (final a in aircraft)
                    if (!candidateIcaos.contains(a.icao24))
                      Marker(
                        point: ll.LatLng(a.latitude, a.longitude),
                        width: 74,
                        height: 52,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          onTap: () => _showAircraftInfo(context, a),
                          child: _LabeledAircraft(aircraft: a, candidate: false),
                        ),
                      ),
                  // Aircraft with a probable transit: cyan glow ring + plane.
                  for (final a in aircraft)
                    if (candidateIcaos.contains(a.icao24))
                      Marker(
                        point: ll.LatLng(a.latitude, a.longitude),
                        width: 86,
                        height: 64,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          onTap: () => _showAircraftInfo(context, a),
                          child: _LabeledAircraft(aircraft: a, candidate: true),
                        ),
                      ),
                  // Satellite crossing points (ISS, Tiangong) at their transit point.
                  for (final p in predictionsWithCorridor)
                    if (p.isSatellite)
                      Marker(
                        point: ll.LatLng(
                          p.corridor!.centerLatitude,
                          p.corridor!.centerLongitude,
                        ),
                        width: 46,
                        height: 46,
                        child: GestureDetector(
                          onTap: () => _showPredictionInfo(context, p),
                          child: const _SatelliteMarker(),
                        ),
                      ),
                  // Aircraft transit ground-crossing points.
                  for (final p in predictionsWithCorridor)
                    if (!p.isSatellite)
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
                      width: 40,
                      height: 40,
                      child: _ObserverMarker(
                        manual: ref
                            .read(observerLocationProvider.notifier)
                            .isManual,
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
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  if (_mapDark) TextSourceAttribution('© CARTO'),
                ],
              ),
            ],
          ),
          // Barra de busca por local (Nominatim/OSM). Fica sempre no topo; os
          // banners informativos passam a aparecer ABAIXO dela (top: 72).
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: _SearchBar(
                controller: _searchController,
                focusNode: _searchFocus,
                busy: _searching,
                onSubmit: _runSearch,
              ),
            ),
          ),
          if (observer == null && _previewPoint == null)
            Positioned(
              top: 72,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: _Banner(
                  icon: Icons.touch_app_outlined,
                  message: 'Toque no mapa ou busque um lugar para escolher '
                      'de onde observar.',
                ),
              ),
            ),
          if (predictionAsync.hasError)
            Positioned(
              top: 72,
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
              top: 72,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Alterna o estilo do basemap (escuro CARTO / claro OSM),
                  // independente do tema do app.
                  FloatingActionButton.small(
                    heroTag: 'map-style',
                    tooltip: _mapDark ? 'Mapa claro' : 'Mapa escuro',
                    onPressed: () => setState(() => _mapDark = !_mapDark),
                    child: Icon(
                        _mapDark ? Icons.light_mode : Icons.dark_mode),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
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
                ],
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
          else if (predictions.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: _TransitListCard(
                  predictions: predictions,
                  onFocus: _focusPrediction,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAircraftInfo(BuildContext context, AircraftState aircraft) {
    // Uma folha de detalhes, NÃO um SnackBar. O SnackBar antigo enfileirava:
    // cada toque agendava mais um, cada um por 3s, e como o ScaffoldMessenger
    // é o da raiz do app a fila sobrevivia à navegação — por isso o "id
    // aparecia a quantidade de vezes que cliquei e continuava aparecendo
    // depois de sair do mapa". Um bottom sheet substitui o anterior em vez de
    // empilhar, fecha ao sair, e ainda cabe muito mais detalhe (RF: "ao clicar
    // no avião, mostrar mais detalhes disponíveis").
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AircraftDetailSheet(aircraft: aircraft),
    );
  }

  /// Pan/zoom the map to a probable transit and open its detail sheet. Aircraft
  /// are focused on their live position; satellites on their transit ground point.
  void _focusPrediction(TransitPrediction p) {
    ll.LatLng? target;
    if (!p.isSatellite) {
      final aircraft =
          ref.read(nearbyAircraftProvider).valueOrNull ?? const <AircraftState>[];
      for (final a in aircraft) {
        if (a.icao24 == p.candidate.icao24) {
          target = ll.LatLng(a.latitude, a.longitude);
          break;
        }
      }
    }
    target ??= p.corridor != null
        ? ll.LatLng(p.corridor!.centerLatitude, p.corridor!.centerLongitude)
        : null;
    if (target != null) {
      final zoom = math.max(_mapController.camera.zoom, 11.0);
      _mapController.move(target, zoom);
    }
    _showPredictionInfo(context, p);
  }

  /// Pontos de uma reta de rumo constante partindo de [from] no [trackDeg],
  /// estendida por [km]. Vários segmentos para acompanhar a curvatura no mapa.
  static List<ll.LatLng> _trajectory(ll.LatLng from, double trackDeg, double km) {
    final pts = <ll.LatLng>[from];
    const steps = 6;
    for (var i = 1; i <= steps; i++) {
      final g = destinationPoint(
          from.latitude, from.longitude, trackDeg, km * i / steps);
      pts.add(ll.LatLng(g.$1, g.$2));
    }
    return pts;
  }

  void _showPredictionInfo(BuildContext context, TransitPrediction p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PredictionDetailSheet(prediction: p),
    );
  }
}

/// Caixa de busca por local no topo do mapa. Dispara a busca só ao submeter
/// (teclado "buscar") — respeita o limite de 1 req/s do Nominatim e não
/// martela o serviço a cada tecla.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSubmit;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText: 'Buscar cidade, endereço, lugar…',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Limpar',
                onPressed: () => controller.clear(),
              ),
          ],
        ),
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

String _bodyLabel(CelestialBody body) =>
    body == CelestialBody.moon ? 'Lua' : 'Sol';

String _timeToTransitLabel(double seconds) {
  final s = seconds.round();
  if (s < 60) return 'em ${s}s';
  final m = s ~/ 60;
  final rem = s % 60;
  return rem == 0 ? 'em ${m}min' : 'em ${m}min ${rem}s';
}

/// Highlighted marker for an aircraft with a probable transit: a glowing ring
/// around the shared plane silhouette, in the candidate colour. The "glow" is
/// a radial gradient (no blur/saveLayer) and the whole marker is a
/// RepaintBoundary — map gestures only translate the cached raster.
/// Nome curto para exibir junto ao avião (RF: "o id do avião deve aparecer
/// junto com ele"). Prefere o callsign (o que o usuário vê no FlightRadar);
/// cai no hex ICAO24 quando não há callsign.
String aircraftShortId(AircraftState a) =>
    a.callsign ?? a.icao24.toUpperCase();

/// Etiqueta do ID: pílula compacta legível sobre qualquer basemap (fundo
/// semitransparente + contorno), sem blur — dezenas delas no mapa não podem
/// custar um saveLayer cada (ver nota de performance do projeto).
class _IdLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _IdLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9,
          height: 1.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Avião + etiqueta do ID empilhados, para uso no MarkerLayer. Largura ampla
/// (a etiqueta é mais larga que o ícone) e alinhado ao topo para a etiqueta
/// não empurrar o ícone da posição real.
class _LabeledAircraft extends StatelessWidget {
  final AircraftState aircraft;
  final bool candidate;

  const _LabeledAircraft(
      {required this.aircraft, required this.candidate});

  @override
  Widget build(BuildContext context) {
    final icon = candidate
        ? _CandidateAircraftMarker(trackDeg: aircraft.trackDeg)
        : PlaneIcon(
            headingDeg: aircraft.trackDeg,
            color: AstroColors.aircraftCommon,
            size: 26,
            outlineColor: Colors.black.withValues(alpha: 0.45),
          );
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: candidate ? 46 : 34, height: candidate ? 46 : 34, child: icon),
          const SizedBox(height: 1),
          _IdLabel(
            text: aircraftShortId(aircraft),
            color: candidate
                ? AstroColors.aircraftCandidate
                : const Color(0xFFB9C6DE),
          ),
        ],
      ),
    );
  }
}

class _CandidateAircraftMarker extends StatelessWidget {
  final double trackDeg;

  const _CandidateAircraftMarker({required this.trackDeg});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AstroColors.aircraftCandidate.withValues(alpha: 0.30),
              AstroColors.aircraftCandidate.withValues(alpha: 0.0),
            ],
            stops: const [0.55, 1.0],
          ),
          border: Border.all(color: AstroColors.aircraftCandidate, width: 1.6),
        ),
        child: Center(
          child: PlaneIcon(
            headingDeg: trackDeg,
            color: AstroColors.aircraftCandidate,
            size: 26,
          ),
        ),
      ),
    );
  }
}

/// Satellite transit ground point: purple glow chip (gradient, not blur).
class _SatelliteMarker extends StatelessWidget {
  const _SatelliteMarker();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AstroColors.satellite.withValues(alpha: 0.30),
              AstroColors.satellite.withValues(alpha: 0.0),
            ],
            stops: const [0.55, 1.0],
          ),
          border: Border.all(color: AstroColors.satellite, width: 1.6),
        ),
        child: const Center(
          child:
              Icon(Icons.satellite_alt, color: AstroColors.satellite, size: 22),
        ),
      ),
    );
  }
}

/// Observer position: dot with a soft halo (amber when manually picked).
class _ObserverMarker extends StatelessWidget {
  final bool manual;

  const _ObserverMarker({required this.manual});

  @override
  Widget build(BuildContext context) {
    final color = manual ? AstroColors.warning : AstroColors.transitCyan;
    return Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.55),
              blurRadius: 12,
              spreadRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom card listing *only* the objects with a probable transit — aircraft and
/// satellites (ISS/Tiangong) alike. Tapping a row focuses it on the map.
class _TransitListCard extends StatelessWidget {
  final List<TransitPrediction> predictions;
  final void Function(TransitPrediction) onFocus;

  const _TransitListCard({required this.predictions, required this.onFocus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.track_changes, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Trânsitos prováveis (${predictions.length})',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.32,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: predictions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _TransitListTile(
                  prediction: predictions[i],
                  onTap: () => onFocus(predictions[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitListTile extends StatelessWidget {
  final TransitPrediction prediction;
  final VoidCallback onTap;

  const _TransitListTile({required this.prediction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = prediction.candidate;
    final isMoon = c.body == CelestialBody.moon;
    final isSat = prediction.isSatellite;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        isSat ? Icons.satellite_alt : Icons.flight,
        color: isSat ? AstroColors.satellite : AstroColors.aircraftCandidate,
      ),
      title: Text(
        prediction.displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${transitClassLabel(c.transitClass)} · '
        '${_bodyLabel(c.body)} · ${_timeToTransitLabel(c.timeToTransitS)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isMoon ? AstroColors.moon : AstroColors.sun,
        ),
      ),
      trailing: Text(
        '${prediction.confidence.score.round()}%',
        style: theme.textTheme.labelLarge,
      ),
      onTap: onTap,
    );
  }
}

/// Detail sheet for a single probable transit (opened from the map or the list).
class _PredictionDetailSheet extends StatelessWidget {
  final TransitPrediction prediction;

  const _PredictionDetailSheet({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = prediction.candidate;
    final isSat = prediction.isSatellite;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSat ? Icons.satellite_alt : Icons.flight,
                  color: isSat
                      ? AstroColors.satellite
                      : AstroColors.aircraftCandidate,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(prediction.displayLabel,
                      style: theme.textTheme.titleMedium),
                ),
                Text('${prediction.confidence.score.round()}%',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${transitClassLabel(c.transitClass)} diante da '
              '${_bodyLabel(c.body)} · ${_timeToTransitLabel(c.timeToTransitS)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: c.body == CelestialBody.moon
                    ? AstroColors.moon
                    : AstroColors.sun,
              ),
            ),
            Text(
              'Confiança: ${confidenceCategoryLabel(prediction.confidence.category)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (isSat)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Satélite — posição calculada por efemérides orbitais (TLE).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (prediction.corridor != null) ...[
              const SizedBox(height: 12),
              _CorridorInfoCard(prediction: prediction),
            ],
          ],
        ),
      ),
    );
  }
}

/// Folha de detalhes de uma aeronave tocada no mapa. Mostra TODOS os campos
/// que o backend fornece (RF: "ao clicar no avião, mostrar mais detalhes
/// disponíveis") — antes isso era um SnackBar de uma linha que ainda por cima
/// se empilhava a cada toque.
class _AircraftDetailSheet extends StatelessWidget {
  final AircraftState aircraft;

  const _AircraftDetailSheet({required this.aircraft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = aircraft;
    final altitudeFt = (a.altitudeM * 3.28084).round();
    final speedKt = (a.groundSpeedMps * 1.94384).round();
    final vertFtMin = (a.verticalRateMps * 196.85).round();
    final id = a.callsign ?? a.icao24.toUpperCase();

    String climb() {
      if (a.onGround) return 'Em solo';
      if (vertFtMin.abs() < 100) return 'Nível';
      return vertFtMin > 0
          ? 'Subindo ${vertFtMin.abs()} ft/min'
          : 'Descendo ${vertFtMin.abs()} ft/min';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlaneIcon(
                  headingDeg: a.trackDeg,
                  color: AstroColors.aircraftCandidate,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(id, style: theme.textTheme.titleLarge),
                      Text(
                        '${_categoryLabel(a.category)} · ${a.icao24.toUpperCase()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DetailChip(
                    icon: Icons.height,
                    label: 'Altitude',
                    value: '$altitudeFt ft'),
                _DetailChip(
                    icon: Icons.speed,
                    label: 'Velocidade',
                    value: '$speedKt kt'),
                _DetailChip(
                    icon: Icons.navigation,
                    label: 'Rumo',
                    value: '${a.trackDeg.round()}° ${compassLabel(a.trackDeg)}'),
                _DetailChip(
                    icon: Icons.trending_up,
                    label: 'Vertical',
                    value: climb()),
                if (a.distanceM != null)
                  _DetailChip(
                      icon: Icons.social_distance,
                      label: 'Distância',
                      value: '${(a.distanceM! / 1000).toStringAsFixed(1)} km'),
                if (a.altitudeDeg != null)
                  _DetailChip(
                      icon: Icons.terrain,
                      label: 'Elevação',
                      value: '${a.altitudeDeg!.round()}°'),
                if (a.azimuthDeg != null)
                  _DetailChip(
                      icon: Icons.explore,
                      label: 'Azimute',
                      value:
                          '${a.azimuthDeg!.round()}° ${compassLabel(a.azimuthDeg!)}'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Dados ADS-B recebidos há ${a.ageS.round()} s · '
              'lat ${a.latitude.toStringAsFixed(4)}, '
              'lon ${a.longitude.toStringAsFixed(4)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static String _categoryLabel(String category) {
    switch (category) {
      case 'small':
        return 'Aeronave leve';
      case 'narrow_body':
        return 'Fuselagem estreita';
      case 'wide_body':
        return 'Fuselagem larga';
      case 'cargo':
        return 'Cargueiro';
      case 'helicopter':
        return 'Helicóptero';
      default:
        return 'Aeronave';
    }
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailChip(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}
