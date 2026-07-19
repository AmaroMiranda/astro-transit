/// Thin Dio wrapper for the AstroTransit backend.
///
/// The base URL is the only configuration point — no API keys live in the
/// client (RNF-006 / section 24: never embed secrets in the app).
library;

import 'package:dio/dio.dart';

class ApiClient {
  final Dio dio;

  ApiClient({required String baseUrl})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            // The hosted backend runs on Render's free tier, which hibernates
            // after ~15 min idle and can take 30-60s to accept the first
            // connection again. A 10s connect timeout gave up during that cold
            // start, so nothing loaded until the user retried repeatedly.
            connectTimeout: const Duration(seconds: 45),
            // The prediction endpoint fans out to ADS-B providers with retry
            // and failover (RF-006): primary timeout + retry + secondary can
            // legitimately take 10-15s. An 8s receive timeout made the app
            // give up right before slow-but-successful responses arrived.
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 10),
          ),
        );

  String get wsBaseUrl =>
      dio.options.baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}

/// Backend base URL, resolved at build time (RNF-006: no secrets/endpoints
/// baked in as mutable app state — this is a compile-time constant, not a
/// runtime-editable setting).
///
/// Defaults to the hosted backend on Render, so release builds work out of
/// the box. For local development against a backend on your machine, override
/// with `--dart-define=API_BASE_URL=http://10.0.2.2:8000` (Android emulator's
/// alias for the host's localhost).
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://astrotransit-backend.onrender.com',
);
