// Maps Dio's exception hierarchy onto the app's `Failure` type, so
// everything above the networking layer only ever deals with `Failure` —
// see core/result/result.dart. This is the single place that knows how to
// read the backend's `{ "error": { "code": ..., "message": ... } }`
// envelope (see backend/app/common/schemas.py's `ErrorResponse`).

import 'package:dio/dio.dart';
import '../result/result.dart';

Failure mapDioErrorToFailure(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
      return const Failure.network();
    case DioExceptionType.badCertificate:
      return const Failure(
          code: 'bad_certificate', message: 'Could not verify the server.');
    case DioExceptionType.cancel:
      return const Failure(
          code: 'cancelled', message: 'Request was cancelled.');
    case DioExceptionType.badResponse:
      return _mapErrorResponse(error);
    case DioExceptionType.unknown:
      return const Failure.unknown();
  }
}

Failure _mapErrorResponse(DioException error) {
  final data = error.response?.data;
  if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
    final errorBody = data['error'] as Map<String, dynamic>;
    return Failure(
      code: errorBody['code'] as String? ?? 'unknown_error',
      message: errorBody['message'] as String? ?? 'Something went wrong.',
    );
  }

  final statusCode = error.response?.statusCode;
  return switch (statusCode) {
    401 =>
      const Failure(code: 'unauthorized', message: 'Please sign in again.'),
    403 => const Failure(
        code: 'forbidden', message: "You don't have permission to do that."),
    404 => const Failure(code: 'not_found', message: 'Not found.'),
    _ => Failure.unknown(
        'The server returned an unexpected error (HTTP $statusCode).'),
  };
}
