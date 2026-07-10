import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:astrotransit/features/camera/domain/overlay_geometry.dart';

void main() {
  group('OverlayGeometry', () {
    test('pixels-per-degree derives from width and horizontal FOV', () {
      final geo = OverlayGeometry.forPreview(
        previewSize: const Size(1000, 2000),
        horizontalFovDeg: 50.0,
      );
      expect(geo.pixelsPerDegree, closeTo(20.0, 1e-9));
    });

    test('body radius scales linearly with angular radius', () {
      final geo = OverlayGeometry.forPreview(
        previewSize: const Size(1000, 2000),
        horizontalFovDeg: 50.0,
      );
      expect(geo.radiusForAngularRadius(0.26), closeTo(0.26 * 20.0, 1e-9));
    });

    test('circle radius is independent of preview height (RF-022)', () {
      final tall = OverlayGeometry.forPreview(
        previewSize: const Size(1000, 3000),
        horizontalFovDeg: 50.0,
      );
      final short = OverlayGeometry.forPreview(
        previewSize: const Size(1000, 1200),
        horizontalFovDeg: 50.0,
      );
      // Same width and FOV -> identical scale regardless of height/aspect ratio.
      expect(tall.pixelsPerDegree, equals(short.pixelsPerDegree));
    });

    test('aircraft directly right of body maps to positive dx, zero dy', () {
      final geo = OverlayGeometry.forPreview(
        previewSize: const Size(1000, 2000),
        horizontalFovDeg: 50.0,
      );
      final offset = geo.offsetForAngularDelta(
        deltaAzimuthDeg: 2.0,
        deltaAltitudeDeg: 0.0,
        atAltitudeDeg: 0.0,
      );
      expect(offset.dx, greaterThan(0));
      expect(offset.dy, closeTo(0, 1e-9));
    });

    test('aircraft above body maps to negative dy (screen y grows downward)', () {
      final geo = OverlayGeometry.forPreview(
        previewSize: const Size(1000, 2000),
        horizontalFovDeg: 50.0,
      );
      final offset = geo.offsetForAngularDelta(
        deltaAzimuthDeg: 0.0,
        deltaAltitudeDeg: 2.0,
        atAltitudeDeg: 0.0,
      );
      expect(offset.dy, lessThan(0));
    });

    test('azimuth offset shrinks with cos(altitude) at high altitude', () {
      final geo = OverlayGeometry.forPreview(
        previewSize: const Size(1000, 2000),
        horizontalFovDeg: 50.0,
      );
      final atHorizon = geo.offsetForAngularDelta(
        deltaAzimuthDeg: 2.0,
        deltaAltitudeDeg: 0.0,
        atAltitudeDeg: 0.0,
      );
      final atHighAlt = geo.offsetForAngularDelta(
        deltaAzimuthDeg: 2.0,
        deltaAltitudeDeg: 0.0,
        atAltitudeDeg: 60.0,
      );
      expect(atHighAlt.dx.abs(), lessThan(atHorizon.dx.abs()));
    });
  });
}
