import 'package:dio/dio.dart';

String apiErrorMessage(
  Object error, {
  required String fallback,
}) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;
    final detailText = _detailText(detail);

    if (detailText != null) return detailText;
    if (status == 401) return 'Tu sesion expiro. Vuelve a iniciar sesion.';
    if (status == 403) return 'No tienes permiso para realizar esta accion.';
    if (status == 422) return 'Revisa los datos ingresados.';
    if (status != null) {
      return 'No pudimos completar la solicitud. Codigo $status.';
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'La conexion demoro demasiado. Intenta nuevamente.';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'No pudimos conectar con el servidor.';
    }
  }

  return fallback;
}

String? _detailText(dynamic detail) {
  if (detail == null) return null;
  if (detail is String && detail.trim().isNotEmpty) return detail.trim();
  if (detail is List && detail.isNotEmpty) {
    final messages = detail
        .map((item) {
          if (item is Map && item['msg'] != null) return item['msg'].toString();
          return item.toString();
        })
        .where((msg) => msg.trim().isNotEmpty)
        .toList();
    return messages.isEmpty ? null : messages.join(' ');
  }
  if (detail is Map) {
    for (final key in ['message', 'msg', 'error']) {
      final value = detail[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
  }
  return null;
}
