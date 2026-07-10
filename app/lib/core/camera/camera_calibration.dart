/// Manual field-of-view calibration (RF-024).
///
/// The compass is not precise enough for final alignment (RF-023/024), so the
/// MVP has the user aim the device at the body directly; the overlay only
/// needs the camera's angular field of view to place the aircraft mark
/// relative to the (assumed centered) body — no absolute heading required.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHorizontalFovKey = 'astrotransit.camera_horizontal_fov_deg';

/// Typical smartphone main-camera horizontal FOV; a reasonable default until
/// the user calibrates their specific device/lens.
const kDefaultHorizontalFovDeg = 68.0;

final horizontalFovProvider = StateProvider<double>((ref) => kDefaultHorizontalFovDeg);

Future<void> bootstrapCameraCalibration(ProviderContainer container) async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getDouble(_kHorizontalFovKey);
  if (stored != null) {
    container.read(horizontalFovProvider.notifier).state = stored;
  }
  container.listen(horizontalFovProvider, (previous, next) {
    prefs.setDouble(_kHorizontalFovKey, next);
  });
}
