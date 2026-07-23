/// Camera overlay (RF-022, RF-024, RF-027).
///
/// The user aims the device at the body manually (guided by the direction
/// arrow in live tracking) — the overlay does not attempt AR/compass fusion
/// (RF-023 is a later-phase feature; RF-024 notes the compass alone isn't
/// precise enough for final alignment). Circles are computed from a single
/// pixels-per-degree scale derived from the preview width, so they stay
/// geometrically perfect regardless of aspect ratio, orientation or crop.
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_calibration.dart';
import '../../../core/design_system/app_theme.dart';
import '../../../core/design_system/astro_button_bar.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../predictions/domain/prediction_providers.dart';
import '../domain/overlay_geometry.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _isRecording = false;
  bool _safetyAcknowledged = false;
  bool _cameraInitStarted = false;

  // The camera (and its permission prompts) must not be touched until any
  // required solar safety acknowledgement has happened (RF-017) — so
  // initialization is triggered from build() once the gate is clear, not
  // unconditionally from initState().
  void _startCameraInitIfNeeded() {
    if (_cameraInitStarted) return;
    _cameraInitStarted = true;
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Nenhuma câmera disponível neste dispositivo.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      setState(() => _error = 'Falha ao iniciar a câmera: $e');
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (_isRecording) {
        await controller.stopVideoRecording();
        setState(() => _isRecording = false);
      } else {
        await controller.startVideoRecording();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      setState(() => _error = 'Falha na gravação: $e');
    }
  }

  @override
  void dispose() {
    _disposeCamera();
    super.dispose();
  }

  // Recording must be stopped explicitly before disposal — otherwise the
  // in-progress video file is left unfinalized (CameraController.dispose
  // does not flush an active recording on its own).
  Future<void> _disposeCamera() async {
    final controller = _controller;
    if (controller == null) return;
    if (_isRecording) {
      try {
        await controller.stopVideoRecording();
      } catch (_) {
        // Best-effort: still dispose the controller below.
      }
    }
    await controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextPrediction = ref.watch(nextPredictionProvider);
    final bodies = ref.watch(predictionProvider).valueOrNull?.bodies ?? [];
    CelestialPosition? targetBody;
    if (nextPrediction != null) {
      for (final b in bodies) {
        if (b.target == nextPrediction.candidate.body) {
          targetBody = b;
          break;
        }
      }
    }
    final isSolarMode = nextPrediction?.candidate.body == CelestialBody.sun ||
        (nextPrediction == null &&
            bodies.any((b) => b.target == CelestialBody.sun && b.isVisible));

    if (isSolarMode && !_safetyAcknowledged) {
      return _SolarSafetyGate(onAcknowledged: () {
        setState(() => _safetyAcknowledged = true);
      });
    }

    _startCameraInitIfNeeded();

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Câmera')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: CameraPreview(controller)),
          LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _OverlayPainter(
                  prediction: nextPrediction,
                  targetBody: targetBody,
                  horizontalFovDeg: ref.watch(horizontalFovProvider),
                ),
              );
            },
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.tune, color: Colors.white),
                    onPressed: () => _showCalibrationSheet(context),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: FloatingActionButton(
                  backgroundColor:
                      _isRecording ? AstroColors.error : Colors.white,
                  onPressed: _toggleRecording,
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
                    color: _isRecording ? Colors.white : Colors.red,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCalibrationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (context) => const _CalibrationSheet(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final TransitPrediction? prediction;
  final CelestialPosition? targetBody;
  final double horizontalFovDeg;

  _OverlayPainter({
    required this.prediction,
    required this.targetBody,
    required this.horizontalFovDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = OverlayGeometry.forPreview(
      previewSize: size,
      horizontalFovDeg: horizontalFovDeg,
    );
    final center = Offset(size.width / 2, size.height / 2);

    // Horizon reference line.
    final horizonPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      horizonPaint,
    );

    final candidate = prediction?.candidate;
    final body = targetBody;
    if (candidate == null || body == null) {
      _paintCrosshair(canvas, center, Colors.white54);
      return;
    }

    final bodyColor = candidate.body == CelestialBody.moon
        ? AstroColors.moon
        : AstroColors.sun;

    // Body circle, centered — geometrically perfect regardless of aspect
    // ratio or crop (RF-022): both axes use the same pixels-per-degree.
    final bodyRadius = geometry.radiusForAngularRadius(candidate.bodyRadiusDeg);
    canvas.drawCircle(
      center,
      bodyRadius,
      Paint()
        ..color = bodyColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Aircraft mark, offset from the body by its true angular separation.
    final deltaAz = candidate.aircraftAzimuthDeg - body.azimuthDeg;
    final deltaAlt = candidate.aircraftAltitudeDeg - body.altitudeDeg;
    final aircraftOffset = geometry.offsetForAngularDelta(
      deltaAzimuthDeg: deltaAz,
      deltaAltitudeDeg: deltaAlt,
      atAltitudeDeg: body.altitudeDeg,
    );
    final aircraftRadius = geometry.radiusForAngularRadius(candidate.aircraftRadiusDeg);
    canvas.drawCircle(
      center + aircraftOffset,
      aircraftRadius < 3 ? 3 : aircraftRadius,
      Paint()..color = AstroColors.aircraftCandidate,
    );

    _paintCrosshair(canvas, center, Colors.white38);
  }

  void _paintCrosshair(Canvas canvas, Offset center, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const armLength = 14.0;
    canvas.drawLine(center - const Offset(armLength, 0), center + const Offset(armLength, 0), paint);
    canvas.drawLine(center - const Offset(0, armLength), center + const Offset(0, armLength), paint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) {
    return oldDelegate.prediction != prediction ||
        oldDelegate.horizontalFovDeg != horizontalFovDeg;
  }
}

class _SolarSafetyGate extends StatelessWidget {
  final VoidCallback onAcknowledged;

  const _SolarSafetyGate({required this.onAcknowledged});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: AstroColors.error, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Nunca observe ou fotografe o Sol com equipamento óptico sem '
                'filtro solar apropriado.\nÓculos de sol não oferecem proteção '
                'suficiente.',
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              AstroButtonBar(
                buttons: [
                  FilledButton(
                    onPressed: onAcknowledged,
                    child: const Text(
                      'Estou ciente e vou seguir as recomendações',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalibrationSheet extends ConsumerWidget {
  const _CalibrationSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fov = ref.watch(horizontalFovProvider);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calibração do campo de visão', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Ajuste o campo de visão horizontal da sua câmera para que os '
            'círculos do overlay correspondam ao tamanho real do Sol/Lua no '
            'enquadramento (RF-024).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('${fov.toStringAsFixed(0)}°'),
          Slider(
            value: fov,
            min: 30,
            max: 100,
            divisions: 70,
            label: '${fov.toStringAsFixed(0)}°',
            onChanged: (v) => ref.read(horizontalFovProvider.notifier).state = v,
          ),
        ],
      ),
    );
  }
}
