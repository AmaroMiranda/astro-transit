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
            connectTimeout: const Duration(seconds: 10),
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
/// Override with `--dart-define=API_BASE_URL=https://api.example.com` when
/// building for a real deployment. Defaults to the Android emulator's alias
/// for the host machine's localhost, which is only reachable in local
/// development.
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
