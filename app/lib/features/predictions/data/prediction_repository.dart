/// Talks to `POST /v1/transits/predict` and `GET /v1/transits/live` (section 14).
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/observer_location.dart';
import '../../../shared/models/transit_prediction.dart';

class PredictionRepository {
  final ApiClient _client;

  PredictionRepository(this._client);

  Future<PredictionResponse> predict({
    required ObserverLocation observer,
    List<CelestialBody> targets = const [CelestialBody.sun, CelestialBody.moon],
    double horizonSeconds = 120.0,
    double maxRadiusKm = 80.0,
  }) async {
    final response = await _client.dio.post(
      '/v1/transits/predict',
      data: {
        'observer': observer.toJson(),
        'targets': targets.map(celestialBodyToWire).toList(),
        'horizon_seconds': horizonSeconds,
        'max_radius_km': maxRadiusKm,
      },
    );
    return PredictionResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Opens the live WebSocket and yields decoded prediction events.
  ///
  /// Callers own the returned channel's lifecycle and must call
  /// [WebSocketChannel.sink.close] when done tracking (SPEC RF-018 "cancelar
  /// acompanhamento").
  ({WebSocketChannel channel, Stream<LiveTransitEvent> events}) watchLive({
    required ObserverLocation observer,
    List<CelestialBody> targets = const [CelestialBody.sun, CelestialBody.moon],
    double horizonSeconds = 120.0,
    double maxRadiusKm = 80.0,
  }) {
    final channel = WebSocketChannel.connect(
      Uri.parse('${_client.wsBaseUrl}/v1/transits/live'),
    );
    channel.sink.add(
      jsonEncode({
        'observer': observer.toJson(),
        'targets': targets.map(celestialBodyToWire).toList(),
        'horizon_seconds': horizonSeconds,
        'max_radius_km': maxRadiusKm,
      }),
    );
    final events = channel.stream.map((raw) {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      return LiveTransitEvent.fromJson(decoded);
    });
    return (channel: channel, events: events);
  }
}

class LiveTransitEvent {
  final String event;
  final PredictionResponse? data;
  final String? detail;

  const LiveTransitEvent({required this.event, this.data, this.detail});

  factory LiveTransitEvent.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'] as Map<String, dynamic>?;
    return LiveTransitEvent(
      event: json['event'] as String,
      data: rawData != null ? PredictionResponse.fromJson(rawData) : null,
      detail: json['detail'] as String?,
    );
  }
}
