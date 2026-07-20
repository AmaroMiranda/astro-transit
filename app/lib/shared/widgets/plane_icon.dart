/// Vector airliner silhouette shared by the map markers and the radar painter.
///
/// Drawn as a `Path` (top view, nose pointing up in a 20x20 box centred at the
/// origin) instead of a font glyph: it rotates cleanly to the aircraft's track,
/// scales without blurring, and does not depend on icon-font tree-shaking.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Airliner top-view silhouette in a 20x20 box centred at (0, 0), nose up.
Path buildPlanePath() {
  final path = Path()
    ..moveTo(0.0, -9.8)                    // nose
    ..cubicTo(0.9, -9.2, 1.2, -7.8, 1.2, -6.2)
    ..lineTo(1.2, -2.6)                    // fuselage to wing root
    ..lineTo(9.2, 1.6)                     // wing leading edge
    ..lineTo(9.2, 3.4)                     // wing tip chord
    ..lineTo(1.2, 1.4)                     // wing trailing edge
    ..lineTo(1.0, 6.2)                     // rear fuselage
    ..lineTo(3.6, 8.2)                     // tailplane leading edge
    ..lineTo(3.6, 9.6)                     // tail tip
    ..lineTo(0.0, 8.6)                     // tail root
    ..lineTo(-3.6, 9.6)
    ..lineTo(-3.6, 8.2)
    ..lineTo(-1.0, 6.2)
    ..lineTo(-1.2, 1.4)
    ..lineTo(-9.2, 3.4)
    ..lineTo(-9.2, 1.6)
    ..lineTo(-1.2, -2.6)
    ..lineTo(-1.2, -6.2)
    ..cubicTo(-1.2, -7.8, -0.9, -9.2, 0.0, -9.8)
    ..close();
  return path;
}

final Path _planePath = buildPlanePath();

/// Paints the shared silhouette rotated to ``headingDeg`` (0 = north/up,
/// clockwise) and scaled to fit ``size``.
///
/// ``outlineColor`` draws a cheap stroked contour under the fill — the way to
/// separate the plane from the basemap. ``glowColor`` adds a blurred halo;
/// blurs force a GPU saveLayer each, so reserve it for the FEW highlighted
/// markers (dozens of blurred common planes froze the map on busy skies).
void paintPlane(
  Canvas canvas,
  Offset center, {
  required double headingDeg,
  required Color color,
  required double size,
  Color? outlineColor,
  Color? glowColor,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(headingDeg * math.pi / 180.0);
  final scale = size / 20.0;
  canvas.scale(scale, scale);
  if (glowColor != null) {
    canvas.drawPath(
      _planePath,
      Paint()
        ..color = glowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }
  if (outlineColor != null) {
    canvas.drawPath(
      _planePath,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
  }
  canvas.drawPath(_planePath, Paint()..color = color);
  canvas.restore();
}

/// Widget wrapper for map markers. Wrapped in a [RepaintBoundary] so each
/// marker rasterizes once and is only *translated* during pan/zoom — with
/// dozens of planes on screen this is the difference between fluid and frozen.
class PlaneIcon extends StatelessWidget {
  final double headingDeg;
  final Color color;
  final double size;
  final Color? outlineColor;

  const PlaneIcon({
    super.key,
    required this.headingDeg,
    required this.color,
    required this.size,
    this.outlineColor,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _PlaneIconPainter(headingDeg, color, outlineColor),
      ),
    );
  }
}

class _PlaneIconPainter extends CustomPainter {
  final double headingDeg;
  final Color color;
  final Color? outlineColor;

  _PlaneIconPainter(this.headingDeg, this.color, this.outlineColor);

  @override
  void paint(Canvas canvas, Size size) {
    paintPlane(
      canvas,
      Offset(size.width / 2, size.height / 2),
      headingDeg: headingDeg,
      color: color,
      size: size.shortestSide,
      outlineColor: outlineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _PlaneIconPainter old) =>
      old.headingDeg != headingDeg ||
      old.color != color ||
      old.outlineColor != outlineColor;
}
