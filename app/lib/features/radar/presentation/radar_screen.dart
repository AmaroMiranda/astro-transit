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
import '../../../core/utils/geo.dart';
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
                          observerLat: observer.latitude,
                          observerLon: observer.longitude,
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
  final double observerLat;
  final double observerLon;

  _RadarPainter({
    required this.bodies,
    required this.aircraft,
    required this.predictions,
    required this.candidateIcaos,
    required this.observerLat,
    required this.observerLon,
  });

  static String _shortId(AircraftState a) =>
      a.callsign ?? a.icao24.toUpperCase();

  /// Etiqueta do ID desenhada logo abaixo do avião no radar.
  void _paintIdLabel(Canvas canvas, Offset pos, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Fundo semitransparente para legibilidade sobre o gradiente do radar.
    final bg = Rect.fromLTWH(
        pos.dx - tp.width / 2 - 3, pos.dy + 11, tp.width + 6, tp.height + 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy + 12));
  }

  /// Trajetória APARENTE de uma aeronave candidata projetada na cúpula do céu.
  ///
  /// O rumo (track) é sobre o SOLO; a direção em que o avião se move pelo CÉU
  /// depende de onde ele está em relação ao observador. Então: extrapolamos a
  /// posição no solo em rumo constante e reprojetamos cada ponto para
  /// azimute/altitude topocêntricos.
  ///
  /// AUTOVALIDAÇÃO: o backend já nos dá o az/alt ATUAL da aeronave. Recalculamos
  /// o az/alt da posição atual com a MESMA fórmula; se não bater (erro > 2°), a
  /// fórmula não é confiável para este ponto e devolvemos null — melhor não
  /// desenhar do que desenhar um traço errado.
  List<(double, double)>? _skyTrajectory(AircraftState a) {
    final refAz = a.azimuthDeg, refAlt = a.altitudeDeg;
    if (refAz == null || refAlt == null) return null;
    final check = _topocentric(a.latitude, a.longitude, a.altitudeM);
    final azErr = ((check.$1 - refAz + 540) % 360) - 180;
    if (azErr.abs() > 2.0 || (check.$2 - refAlt).abs() > 2.0) return null;

    final out = <(double, double)>[(refAz, refAlt)];
    for (var i = 1; i <= 5; i++) {
      final g = destinationPoint(
          a.latitude, a.longitude, a.trackDeg, 12.0 * i); // 12 km/passo
      final p = topocentric(
          observerLat, observerLon, g.$1, g.$2, a.altitudeM);
      if (p.$2 < 0) break; // desceu abaixo do horizonte
      out.add(p);
    }
    return out;
  }

  (double, double) _topocentric(double lat, double lon, double altM) =>
      topocentric(observerLat, observerLon, lat, lon, altM);

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
      final pos = _project(center, radius, a.azimuthDeg!, a.altitudeDeg!);
      paintPlane(
        canvas,
        pos,
        headingDeg: a.trackDeg,
        color: AstroColors.aircraftCommon,
        size: 15,
      );
      _paintIdLabel(canvas, pos, _shortId(a), const Color(0xFF8CA0BE));
    }
    for (final a in aircraft) {
      if (!candidateIcaos.contains(a.icao24)) continue;
      final pos = _project(center, radius, a.azimuthDeg!, a.altitudeDeg!);
      // Trajetória aparente no céu: projeta posições futuras (rumo constante)
      // para az/alt e liga os pontos. Só é desenhada se a fórmula topocêntrica
      // reproduzir o az/alt ATUAL que o backend já forneceu — do contrário
      // seria um traço enganoso, e aí não desenhamos nada (ver _skyTrajectory).
      final traj = _skyTrajectory(a);
      if (traj != null && traj.length >= 2) {
        final path = Path()
          ..moveTo(_project(center, radius, traj.first.$1, traj.first.$2).dx,
              _project(center, radius, traj.first.$1, traj.first.$2).dy);
        for (final t in traj.skip(1)) {
          final p = _project(center, radius, t.$1, t.$2);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = AstroColors.aircraftCandidate.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
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
      _paintIdLabel(canvas, pos, _shortId(a), AstroColors.aircraftCandidate);
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

    // Indicador do OBSERVADOR (você), no centro = zênite. Antes era um
    // pontinho branco de 3px, fácil de confundir com o cruzamento dos eixos;
    // o usuário pediu um indicador claro de "onde estou". Agora: ponto ciano
    // com halo e a etiqueta "Você" logo abaixo.
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = AstroColors.transitCyan.withValues(alpha: 0.22),
    );
    canvas.drawCircle(center, 4.5, Paint()..color = AstroColors.transitCyan);
    canvas.drawCircle(
      center,
      4.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Você',
        style: TextStyle(
          color: AstroColors.transitCyan,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center + Offset(-tp.width / 2, 10));
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
