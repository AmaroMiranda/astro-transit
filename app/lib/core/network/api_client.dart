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
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );

  String get wsBaseUrl =>
      dio.options.baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}

/// Default backend location for local development.
/// Android emulator maps 10.0.2.2 to the host machine's localhost.
const kDevBaseUrl = 'http://10.0.2.2:8000';
