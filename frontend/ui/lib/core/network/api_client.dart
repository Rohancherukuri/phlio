// The single configured `Dio` instance the whole app makes HTTP calls
// through. Two responsibilities live here and nowhere else:
//
//  1. Attaching `Authorization: Bearer <token>` to every request that
//     needs it (every path except the auth endpoints themselves).
//  2. Transparently refreshing an expired access token exactly once per
//     failed request, so a controller never has to think about token
//     lifetime — it just gets a `401 Failure` if refreshing also fails,
//     which is the app's true "please log in again" signal.
//
// Data sources (see e.g. `features/social/data/datasources`) depend on
// `ApiClient` and call `apiClient.dio.get(...)` directly — this class does
// not wrap every HTTP verb, it only owns cross-cutting request behaviour.

import 'package:dio/dio.dart';
import '../../app/config/app_config.dart';
import '../logging/app_logger.dart';
import '../storage/token_storage.dart';

final _logger = createLogger('phlio.api');

/// Paths that must NOT get an Authorization header attached (they either
/// don't require auth or, in the refresh endpoint's case, need to avoid a
/// circular dependency on the very token they're refreshing).
const _unauthenticatedPaths = ['/auth/login', '/auth/register', '/auth/refresh'];

/// Request-options key used to stash the start time for duration logging —
/// namespaced so it can't collide with anything the retry logic in
/// `_onError` also stores on `extra`.
const _startTimeExtraKey = 'phlio_request_start_time';

class ApiClient {
  ApiClient({required TokenStorage tokenStorage, this.onSessionExpired})
      : _tokenStorage = tokenStorage,
        dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
    if (AppConfig.enableRequestLogging) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.extra[_startTimeExtraKey] = DateTime.now();
            handler.next(options);
          },
          onResponse: (response, handler) {
            _logRequestOutcome(response.requestOptions, statusCode: response.statusCode);
            handler.next(response);
          },
          onError: (error, handler) {
            _logRequestOutcome(
              error.requestOptions,
              statusCode: error.response?.statusCode,
              errorMessage: error.message,
            );
            handler.next(error);
          },
        ),
      );
    }
  }

  final Dio dio;
  final TokenStorage _tokenStorage;

  /// Invoked when a request fails auth *and* refreshing the token also
  /// fails — the app-level signal to clear local session state and route
  /// back to login. Wired up once in `core/di/service_locator.dart`.
  void Function()? onSessionExpired;

  bool _isRefreshing = false;

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final isUnauthenticated = _unauthenticatedPaths.any(options.path.contains);
    if (!isUnauthenticated) {
      final token = await _tokenStorage.accessToken;
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final isUnauthorized = error.response?.statusCode == 401;
    final alreadyRetried = error.requestOptions.extra['retried'] == true;
    final isAuthEndpoint = _unauthenticatedPaths.any(error.requestOptions.path.contains);

    if (!isUnauthorized || alreadyRetried || isAuthEndpoint || _isRefreshing) {
      handler.next(error);
      return;
    }

    _isRefreshing = true;
    _logger.info('Access token expired — attempting refresh.');
    try {
      final refreshToken = await _tokenStorage.refreshToken;
      if (refreshToken == null) {
        _logger.warning('No refresh token available — forcing sign-out.');
        onSessionExpired?.call();
        handler.next(error);
        return;
      }

      final refreshResponse = await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl)).post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final newAccessToken = refreshResponse.data['access_token'] as String;
      await _tokenStorage.updateAccessToken(newAccessToken);
      _logger.info('Token refresh succeeded — retrying original request.');

      // Retry the original request once, with the fresh token attached.
      final retryOptions = error.requestOptions..extra['retried'] = true;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      final retryResponse = await dio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } on DioException catch (refreshError) {
      _logger.error('Token refresh failed — forcing sign-out.', error: refreshError);
      await _tokenStorage.clearTokens();
      onSessionExpired?.call();
      handler.next(error);
    } finally {
      _isRefreshing = false;
    }
  }
}

/// Logs one line per completed request: method, path, status (or error),
/// and duration — the same shape as the backend's
/// `app/middleware/request_logging.py`, so a "what happened" question can
/// be answered by reading either side's logs the same way.
void _logRequestOutcome(RequestOptions options, {int? statusCode, String? errorMessage}) {
  final startTime = options.extra[_startTimeExtraKey] as DateTime?;
  final durationMs = startTime != null ? DateTime.now().difference(startTime).inMilliseconds : null;
  final durationTag = durationMs != null ? ' (${durationMs}ms)' : '';
  final message = '${options.method} ${options.path} -> ${statusCode ?? 'ERR'}$durationTag';

  if (errorMessage != null) {
    _logger.warning('$message — $errorMessage');
  } else if ((statusCode ?? 0) >= 500) {
    _logger.error(message);
  } else {
    _logger.debug(message);
  }
}
