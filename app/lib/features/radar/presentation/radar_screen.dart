/// Radar view (RF-020): observer at the center, celestial bodies and
/// candidate aircraft plotted by azimuth/altitude. Painted with a
/// `CustomPainter` per SPEC section 11.3 performance guidance (avoid heavy
/// widget trees for frequently-updated visuals).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/app_theme.dart';
import '../../../core/providers.dart';
import '../../map/domain/aircraft_providers.dart';
import '../../predictions/domain/prediction_providers.dart';
import '../../../shared/models/aircraft_state.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../../shared/widgets/plane_icon.dart';

class RadarScreen extends ConsumerWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observer = ref.watch(observerLocationProvider);
    final predictionAsync = ref.watch(predictionProvider);
    final aircraftAsync = ref.watch(nearbyAircraftProvider);

    if (observer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Radar')),
        body: const Center(child: Text('Localização indisponível.')),
      );
    }

    final response = predictionAsync.valueOrNull;
    final bodies = response?.bodies ?? const <CelestialPosition>[];
    final predictions = response?.predictions ?? const <TransitPrediction>[];
    final candidateIcaos =
        predictions.map((p) => p.candidate.icao24).toSet();
    // Every aircraft above the horizon with a known bearing (satellites/candidates
    // that lack a live ADS-B fix are drawn from the predictions instead).
    final aircraft = (aircraftAsync.valueOrNull ?? const <AircraftState>[])
        .where((a) => a.altitudeDeg != null && a.altitudeDeg! > 0)
        .toList();

    final loading = predictionAsync.isLoading && aircraftAsync.isLoading;
    final visibleCount = aircraft.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Radar')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _RadarPainter(
                          bodies: bodies,
                          aircraft: aircraft,
                          predictions: predictions,
                          candidateIcaos: candidateIcaos,
                        ),
                      ),
                    ),
                    if (loading)
                      const Center(child: CircularProgressIndicator()),
                    if (!loading && visibleCount == 0)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Nenhuma aeronave acima do horizonte agora.',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<CelestialPosition> bodies;
  final List<AircraftState> aircraft;
  final List<TransitPrediction> predictions;
  final Set<String> candidateIcaos;

  _RadarPainter({
    required this.bodies,
    required this.aircraft,
    required this.predictions,
    required this.candidateIcaos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 24;

    _paintBackground(canvas, center, radius);
    _paintRings(canvas, center, radius);
    _paintCompassLabels(canvas, center, radius);

    for (final body in bodies) {
      if (!body.isVisible) continue;
      final color = body.target == CelestialBody.moon
          ? AstroColors.moon
          : AstroColors.sun;
      _paintBody(
        canvas,
        _project(center, radius, body.azimuthDeg, body.altitudeDeg),
        color: color,
        radius: 11,
      );
    }

    // All live aircraft above the horizon: common traffic dim, transit
    // candidates highlighted (drawn on top).
    for (final a in aircraft) {
      if (candidateIcaos.contains(a.icao24)) continue;
      paintPlane(
        canvas,
        _project(center, radius, a.azimuthDeg!, a.altitudeDeg!),
        headingDeg: a.trackDeg,
        color: AstroColors.aircraftCommon,
        size: 15,
      );
    }
    for (final a in aircraft) {
      if (!candidateIcaos.contains(a.icao24)) continue;
      final pos = _project(center, radius, a.azimuthDeg!, a.altitudeDeg!);
      canvas.drawCircle(
        pos,
        13,
        Paint()
          ..color = AstroColors.aircraftCandidate.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      paintPlane(
        canvas,
        pos,
        headingDeg: a.trackDeg,
        color: AstroColors.aircraftCandidate,
        size: 20,
      );
    }

    // Satellites (ISS/Tiangong) and any candidate without a live ADS-B fix are
    // plotted from the prediction geometry.
    final plottedIcaos = aircraft.map((a) => a.icao24).toSet();
    for (final prediction in predictions) {
      final c = prediction.candidate;
      if (!prediction.isSatellite && plottedIcaos.contains(c.icao24)) continue;
      final pos =
          _project(center, radius, c.aircraftAzimuthDeg, c.aircraftAltitudeDeg);
      if (prediction.isSatellite) {
        _paintSatellite(canvas, pos);
      } else {
        paintPlane(
          canvas,
          pos,
          headingDeg: 0,
          color: AstroColors.aircraftCandidate,
          size: 20,
          glowColor: AstroColors.aircraftCandidate.withValues(alpha: 0.5),
        );
      }
    }
  }

  /// Azimuth/altitude -> position on the disc (zenith at centre, horizon at rim).
  Offset _project(
    Offset center, double radius, double azimuthDeg, double altitudeDeg,
  ) {
    final clampedAlt = altitudeDeg.clamp(0.0, 90.0);
    final r = radius * (1 - clampedAlt / 90.0);
    final angle = _deg2rad(azimuthDeg) - math.pi / 2;
    return center + Offset(math.cos(angle), math.sin(angle)) * r;
  }

  void _paintBackground(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF10203A), Color(0xFF081020), AstroColors.deepSpace],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  void _paintRings(Canvas canvas, Offset center, double radius) {
    final ringPaint = Paint()
      ..color = AstroColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Elevation rings: horizon (rim), 30 deg, 60 deg.
    for (final fraction in [1.0, 2.0 / 3.0, 1.0 / 3.0]) {
      canvas.drawCircle(center, radius * fraction, ringPaint);
    }
    // Outer rim slightly brighter.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF35507E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Subtle N-S / E-W cross hairs.
    final crossPaint = Paint()
      ..color = AstroColors.border.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.drawLine(center - Offset(0, radius), center + Offset(0, radius), crossPaint);
    canvas.drawLine(center - Offset(radius, 0), center + Offset(radius, 0), crossPaint);

    // Azimuth ticks every 30 deg on the rim.
    final tickPaint = Paint()
      ..color = const Color(0xFF43608F)
      ..strokeWidth = 1.6;
    for (var az = 0; az < 360; az += 30) {
      final angle = _deg2rad(az.toDouble()) - math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + dir * (radius - 6), center + dir * radius, tickPaint);
    }

    // Elevation labels on the vertical axis.
    for (final (fraction, label) in [(2.0 / 3.0, '30°'), (1.0 / 3.0, '60°')]) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Color(0xFF5C7196), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        center + Offset(3, -radius * fraction - tp.height - 1),
      );
    }

    // Observer marker (zenith) at the centre.
    canvas.drawCircle(center, 3.4, Paint()..color = Colors.white70);
    canvas.drawCircle(
      center,
      6.5,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  static const _compassLabels = [(0.0, 'N'), (90.0, 'L'), (180.0, 'S'), (270.0, 'O')];

  void _paintCompassLabels(Canvas canvas, Offset center, double radius) {
    for (final (azimuth, label) in _compassLabels) {
      final angle = _deg2rad(azimuth) - math.pi / 2;
      final pos = center +
          Offset(math.cos(angle), math.sin(angle)) * (radius + 14);
      final isNorth = azimuth == 0.0;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isNorth ? AstroColors.transitCyan : AstroColors.telemetry,
            fontSize: isNorth ? 13 : 12,
            fontWeight: isNorth ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// Sun/Moon: soft glow halo + solid disc.
  void _paintBody(
    Canvas canvas, Offset pos, {required Color color, required double radius}
  ) {
    canvas.drawCircle(
      pos,
      radius * 2.2,
      Paint()
        ..color = color.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(pos, radius, Paint()..color = color);
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// Satellite: glowing dot with solar-panel bars (drawn, not a font glyph).
  void _paintSatellite(Canvas canvas, Offset pos) {
    const color = AstroColors.satellite;
    canvas.drawCircle(
      pos,
      12,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final panel = Paint()..color = color;
    canvas.drawRect(
      Rect.fromCenter(center: pos - const Offset(8, 0), width: 7, height: 4),
      panel,
    );
    canvas.drawRect(
      Rect.fromCenter(center: pos + const Offset(8, 0), width: 7, height: 4),
      panel,
    );
    canvas.drawCircle(pos, 3.6, panel);
    canvas.drawCircle(
      pos,
      3.6,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.bodies != bodies ||
        oldDelegate.aircraft != aircraft ||
        oldDelegate.predictions != predictions;
  }
}

double _deg2rad(double deg) => deg * math.pi / 180.0;

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendItem(color: AstroColors.moon, label: 'Lua'),
        _LegendItem(color: AstroColors.sun, label: 'Sol'),
        _LegendItem(color: AstroColors.aircraftCommon, label: 'Aeronave'),
        _LegendItem(color: AstroColors.aircraftCandidate, label: 'Candidata'),
        _LegendItem(color: AstroColors.satellite, label: 'Satélite'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AstroColors.orbitalSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AstroColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AstroColors.telemetry),
          ),
        ],
      ),
    );
  }
}
