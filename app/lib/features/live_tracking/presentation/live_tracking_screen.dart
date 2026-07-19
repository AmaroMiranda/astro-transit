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
import '../../../core/network/friendly_error.dart';
import '../../../core/providers.dart';
import '../../../core/utils/compass.dart';
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

  /// Absolute UTC instant of the event, anchored to the server's epoch
  /// (`generated_at_utc + time_to_transit_s`). The countdown is *derived* from
  /// this each frame — a decrementing counter drifts with frame drops, GC and
  /// backgrounding, and never accounts for message latency (P0.5).
  DateTime? _transitAtUtc;
  bool _cancelled = false;
  Timer? _tickTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    // 10 Hz repaint only — the source of truth for time is _transitAtUtc.
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _transitAtUtc != null) setState(() {});
    });
  }

  double get _countdown {
    final at = _transitAtUtc;
    if (at == null) return 0;
    final ms = at.difference(DateTime.now().toUtc()).inMilliseconds;
    return ms <= 0 ? 0 : ms / 1000.0;
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
        final data = event.data;
        final predictions = data?.predictions ?? [];
        if (predictions.isNotEmpty) {
          final first = predictions.first;
          setState(() {
            _prediction = first;
            _transitAtUtc = data!.generatedAtUtc.add(
              Duration(
                milliseconds:
                    (first.candidate.timeToTransitS * 1000).round(),
              ),
            );
            _cancelled = false;
            _error = null;
          });
        } else if (_prediction != null) {
          // The event we were tracking is gone (transit_cancelled /
          // no_candidates): stop the countdown instead of letting the user
          // point a camera at an event that no longer exists (P0.4).
          setState(() {
            _prediction = null;
            _transitAtUtc = null;
            _cancelled = true;
          });
        }
      },
      onError: (e) => setState(() => _error = friendlyErrorMessage(e)),
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
    final countdown = _countdown;
    final isFinal = prediction != null && countdown <= 30;

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
              : _cancelled
                  ? _CancelledState(onBack: () => context.pop())
                  : prediction == null
                      ? const _WaitingState()
                      : _CountdownView(
                          prediction: prediction,
                          countdown: countdown,
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

class _WaitingState extends StatelessWidget {
  const _WaitingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text(
          'Procurando candidatos na sua região…',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}

class _CancelledState extends StatelessWidget {
  final VoidCallback onBack;

  const _CancelledState({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.flight_takeoff, color: AstroColors.warning, size: 40),
        const SizedBox(height: 12),
        const Text(
          'Trânsito cancelado',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'A trajetória mudou e o cruzamento não deve mais acontecer. '
            'Seguimos monitorando novos candidatos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onBack, child: const Text('Voltar')),
      ],
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
        // FittedBox: o contador grande (até 88px) nunca estoura a largura em
        // telas estreitas ou com fonte do sistema ampliada.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(1).padLeft(4, '0')}',
            maxLines: 1,
            style: AppTheme.countdownStyle(context, color: Colors.white)
                .copyWith(fontSize: isFinal ? 88 : 64),
          ),
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
          '${compassLabel(c.aircraftAzimuthDeg)}',
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
