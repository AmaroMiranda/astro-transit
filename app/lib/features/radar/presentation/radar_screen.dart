/// Radar view (RF-020): observer at the center, celestial bodies and
/// candidate aircraft plotted by azimuth/altitude. Painted with a
/// `CustomPainter` per SPEC section 11.3 performance guidance (avoid heavy
/// widget trees for frequently-updated visuals).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/app_theme.dart';
import '../../../core/network/friendly_error.dart';
import '../../predictions/domain/prediction_providers.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';

class RadarScreen extends ConsumerWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictionAsync = ref.watch(predictionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Radar')),
      body: predictionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyErrorMessage(e))),
        data: (response) {
          if (response == null) {
            return const Center(child: Text('Localização indisponível.'));
          }
          final candidateIcaos =
              response.predictions.map((p) => p.candidate.icao24).toSet();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _RadarPainter(
                          bodies: response.bodies,
                          predictions: response.predictions,
                          candidateIcaos: candidateIcaos,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Legend(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<CelestialPosition> bodies;
  final List<TransitPrediction> predictions;
  final Set<String> candidateIcaos;

  _RadarPainter({
    required this.bodies,
    required this.predictions,
    required this.candidateIcaos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 24;

    _paintRings(canvas, center, radius);
    _paintCompassLabels(canvas, center, radius);

    for (final body in bodies) {
      if (!body.isVisible) continue;
      _paintPoint(
        canvas,
        center,
        radius,
        azimuthDeg: body.azimuthDeg,
        altitudeDeg: body.altitudeDeg,
        color: body.target == CelestialBody.moon
            ? AstroColors.moon
            : AstroColors.sun,
        size: 14,
        icon: body.target == CelestialBody.moon
            ? Icons.nightlight_round
            : Icons.wb_sunny,
      );
    }

    for (final prediction in predictions) {
      final c = prediction.candidate;
      _paintPoint(
        canvas,
        center,
        radius,
        azimuthDeg: c.aircraftAzimuthDeg,
        altitudeDeg: c.aircraftAltitudeDeg,
        color: AstroColors.aircraftCandidate,
        size: 10,
        icon: Icons.flight,
      );
    }
  }

  void _paintRings(Canvas canvas, Offset center, double radius) {
    final ringPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final fraction in [0.33, 0.66, 1.0]) {
      canvas.drawCircle(center, radius * fraction, ringPaint);
    }
    // Observer marker.
    canvas.drawCircle(center, 4, Paint()..color = Colors.white70);
  }

  static const _compassLabels = [(0.0, 'N'), (90.0, 'L'), (180.0, 'S'), (270.0, 'O')];

  void _paintCompassLabels(Canvas canvas, Offset center, double radius) {
    for (final (azimuth, label) in _compassLabels) {
      final angle = _deg2rad(azimuth) - math.pi / 2;
      final pos = center +
          Offset(math.cos(angle), math.sin(angle)) * (radius + 14);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// Projects azimuth/altitude onto the 2D radar disc. Altitude maps to
  /// radial distance (zenith at the center, horizon at the rim) so the whole
  /// visible sky fits on screen — a deliberate simplification vs. a literal
  /// polar plot, chosen for legibility (SPEC RF-020).
  void _paintPoint(
    Canvas canvas,
    Offset center,
    double radius,
    {required double azimuthDeg,
    required double altitudeDeg,
    required Color color,
    required double size,
    required IconData icon}
  ) {
    final clampedAlt = altitudeDeg.clamp(0.0, 90.0);
    final r = radius * (1 - clampedAlt / 90.0);
    final angle = _deg2rad(azimuthDeg) - math.pi / 2;
    final pos = center + Offset(math.cos(angle), math.sin(angle)) * r;

    canvas.drawCircle(pos, size, Paint()..color = color.withValues(alpha: 0.25));
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 1.6,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      pos - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.bodies != bodies || oldDelegate.predictions != predictions;
  }
}

double _deg2rad(double deg) => deg * math.pi / 180.0;

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      children: [
        _LegendItem(color: AstroColors.moon, label: 'Lua'),
        _LegendItem(color: AstroColors.sun, label: 'Sol'),
        _LegendItem(color: AstroColors.aircraftCandidate, label: 'Aeronave candidata'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
