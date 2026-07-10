/// Pure geometry for the camera overlay (RF-022).
///
/// The body (Sun/Moon) is assumed centered in the frame — the user aims the
/// device manually, guided by the direction shown in live tracking. Given
/// only the camera's horizontal field of view and the preview's pixel size,
/// this computes:
///   - a single pixels-per-degree scale (so circles stay geometrically
///     perfect regardless of the preview's aspect ratio or crop — RF-022);
///   - the aircraft's screen offset from center, from its angular offset
///     relative to the body;
///   - the body's on-screen radius, from its true apparent angular radius.
library;

import 'dart:math' as math;
import 'dart:ui';

class OverlayGeometry {
  final double pixelsPerDegree;

  const OverlayGeometry._(this.pixelsPerDegree);

  /// [previewSize] is the camera preview's pixel dimensions as laid out on
  /// screen; [horizontalFovDeg] is the calibrated horizontal field of view.
  /// The scale is derived from the horizontal axis only, so vertical framing
  /// differences (aspect ratio, crop) never distort circles into ellipses.
  factory OverlayGeometry.forPreview({
    required Size previewSize,
    required double horizontalFovDeg,
  }) {
    final pixelsPerDegree = previewSize.width / horizontalFovDeg;
    return OverlayGeometry._(pixelsPerDegree);
  }

  double radiusForAngularRadius(double angularRadiusDeg) {
    return angularRadiusDeg * pixelsPerDegree;
  }

  /// Screen-space offset (dx east+, dy up+) of a target whose azimuth/altitude
  /// differ from the (centered) body's by [deltaAzimuthDeg]/[deltaAltitudeDeg].
  Offset offsetForAngularDelta({
    required double deltaAzimuthDeg,
    required double deltaAltitudeDeg,
    required double atAltitudeDeg,
  }) {
    // Azimuth degrees compress toward the poles by cos(altitude); at the
    // shallow altitudes typical of these transits this keeps the horizontal
    // placement accurate rather than assuming a flat-sky projection.
    final cosAlt = math.cos(atAltitudeDeg * math.pi / 180.0);
    final dx = deltaAzimuthDeg * cosAlt * pixelsPerDegree;
    final dy = -deltaAltitudeDeg * pixelsPerDegree; // screen y grows downward
    return Offset(dx, dy);
  }
}
