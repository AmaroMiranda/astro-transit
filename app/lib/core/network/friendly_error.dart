/// Translates network/parsing exceptions into user-facing copy (SPEC section
/// 18 — errors should explain what's wrong in plain language, never dump a
/// raw exception onto the screen).
library;

import 'package:dio/dio.dart';

String friendlyErrorMessage(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'O servidor demorou para responder. Verifique sua conexão e '
            'tente novamente.';
      case DioExceptionType.connectionError:
        return 'Não foi possível conectar ao servidor. Verifique sua '
            'conexão com a internet.';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return 'O servidor retornou um erro${code != null ? ' ($code)' : ''}. '
            'Tente novamente em instantes.';
      case DioExceptionType.cancel:
        return 'A consulta foi cancelada.';
      default:
        return 'Não foi possível consultar o servidor. Tente novamente.';
    }
  }
  return 'Ocorreu um erro inesperado. Tente novamente.';
}
