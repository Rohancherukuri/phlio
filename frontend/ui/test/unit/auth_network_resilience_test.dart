import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/core/storage/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failureType in [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout
  ]) {
    test('Login retries $failureType once with longer timeouts', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient(tokenStorage: TokenStorage());
      var calls = 0;
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            calls++;
            expect(r.receiveTimeout, const Duration(seconds: 45));
            if (calls == 1) {
              h.reject(
                DioException(
                  requestOptions: r,
                  type: failureType,
                ),
                true,
              );
            } else {
              h.resolve(Response(requestOptions: r, statusCode: 200, data: {}));
            }
          },
        ),
      );
      await api.dio.post(
        '/auth/login',
        data: {'identifier': 'demo', 'password': 'example'},
      );
      expect(calls, 2);
      api.dio.close();
    });
  }
  for (final status in [null, 401]) {
    test('Refresh ${status ?? 'timeout'} preserves session unless rejected',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = TokenStorage();
      await storage.saveTokens(
        const AuthTokens(accessToken: 'old', refreshToken: 'refresh'),
      );
      final refresh = Dio();
      refresh.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.reject(
            DioException(
              requestOptions: r,
              type: status == null
                  ? DioExceptionType.receiveTimeout
                  : DioExceptionType.badResponse,
              response: status == null
                  ? null
                  : Response(requestOptions: r, statusCode: status),
            ),
          ),
        ),
      );
      var expired = false;
      final api = ApiClient(
        tokenStorage: storage,
        refreshClient: refresh,
        onSessionExpired: () => expired = true,
      );
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.reject(
            DioException(
              requestOptions: r,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: r, statusCode: 401),
            ),
            true,
          ),
        ),
      );
      await expectLater(api.dio.get('/auth/me'), throwsA(isA<DioException>()));
      expect(await storage.accessToken, status == null ? 'old' : null);
      expect(expired, status != null);
      api.dio.close();
      refresh.close();
    });
  }
  test('Invalid login is never retried', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ApiClient(tokenStorage: TokenStorage());
    var calls = 0;
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          calls++;
          h.reject(
            DioException(
              requestOptions: r,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: r, statusCode: 401),
            ),
            true,
          );
        },
      ),
    );
    await expectLater(
      api.dio.post('/auth/login'),
      throwsA(isA<DioException>()),
    );
    expect(calls, 1);
    api.dio.close();
  });
}
