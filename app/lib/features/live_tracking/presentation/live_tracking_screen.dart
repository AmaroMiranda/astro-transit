/// Countdown / follow-along mode (RF-018, section 16.5-16.6).
///
/// In the final seconds the UI sheds secondary controls to reduce cognitive
/// load (section 16.6): larger countdown, fewer words, camera/map still one
/// tap away.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/app_theme.dart';
import '../../../core/providers.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../predictions/data/prediction_repository.dart';

class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  StreamSubscription<LiveTransitEvent>? _sub;
  dynamic _channel;
  TransitPrediction? _prediction;
  Timer? _tickTimer;
  double _localCountdown = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    // Smooth local countdown between server updates (section 11.4: 10 Hz UI
    // tick locally, independent of the server's real update cadence).
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _localCountdown = (_localCountdown - 0.1).clamp(0, 999999));
    });
  }

  void _connect() {
    final observer = ref.read(observerLocationProvider);
    if (observer == null) {
      setState(() => _error = 'Localização indisponível.');
      return;
    }
    final repo = ref.read(predictionRepositoryProvider);
    final result = repo.watchLive(observer: observer);
    _channel = result.channel;
    _sub = result.events.listen(
      (event) {
        if (event.event == 'error') {
          setState(() => _error = event.detail);
          return;
        }
        final predictions = event.data?.predictions ?? [];
        if (predictions.isNotEmpty) {
          setState(() {
            _prediction = predictions.first;
            _localCountdown = predictions.first.candidate.timeToTransitS;
            _error = null;
          });
        }
      },
      onError: (e) => setState(() => _error = '$e'),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prediction = _prediction;
    final isFinal = _localCountdown <= 30;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: isFinal
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              title: const Text('Acompanhando'),
            ),
      body: SafeArea(
        child: Center(
          child: _error != null
              ? _ErrorState(message: _error!, onBack: () => context.pop())
              : prediction == null
                  ? const CircularProgressIndicator()
                  : _CountdownView(
                      prediction: prediction,
                      countdown: _localCountdown,
                      isFinal: isFinal,
                    ),
        ),
      ),
      floatingActionButton: !isFinal
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/camera'),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Câmera'),
            ),
    );
  }
}

class _CountdownView extends StatelessWidget {
  final TransitPrediction prediction;
  final double countdown;
  final bool isFinal;

  const _CountdownView({
    required this.prediction,
    required this.countdown,
    required this.isFinal,
  });

  @override
  Widget build(BuildContext context) {
    final c = prediction.candidate;
    final isMoon = c.body == CelestialBody.moon;
    final bodyColor = isMoon ? AstroColors.moon : AstroColors.sun;
    final minutes = (countdown / 60).floor();
    final seconds = countdown % 60;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isMoon ? 'LUA' : 'SOL',
          style: TextStyle(
            color: bodyColor,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(1).padLeft(4, '0')}',
          style: AppTheme.countdownStyle(context, color: Colors.white)
              .copyWith(fontSize: isFinal ? 88 : 64),
        ),
        const SizedBox(height: 24),
        // North-up arrow toward the aircraft's azimuth (compass calibration
        // for true device-relative pointing lands with AR in a later phase).
        Transform.rotate(
          angle: c.aircraftAzimuthDeg * 3.1415926535 / 180.0,
          child: const Icon(Icons.navigation, color: Colors.white70, size: 32),
        ),
        Text(
          '${c.aircraftAzimuthDeg.toStringAsFixed(0)}° · '
          '${_compassLabel(c.aircraftAzimuthDeg)}',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        if (!isFinal) ...[
          const SizedBox(height: 20),
          Text(
            transitClassLabel(c.transitClass),
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Confiança ${confidenceCategoryLabel(prediction.confidence.category)} '
            '(${prediction.confidence.score.toStringAsFixed(0)}%)',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ],
    );
  }

  String _compassLabel(double azimuthDeg) {
    const labels = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];
    final index = (((azimuthDeg % 360) + 22.5) / 45).floor() % 8;
    return labels[index];
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onBack;

  const _ErrorState({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.white54, size: 40),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onBack, child: const Text('Voltar')),
      ],
    );
  }
}
