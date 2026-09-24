// Talks to `/api/v1/auth/*`. Throws `DioException` on failure — the
// repository (`../repositories/auth_repository_impl.dart`) is the layer
// that catches it and converts it to a `Result`/`Failure`, so this class
// stays a simple, honest description of "what HTTP calls this feature
// makes" with no error-handling policy baked in.

import '../../../../core/network/api_client.dart';
import '../models/auth_response_model.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthResponseModel> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required List<String> interests,
  }) async {
    final response = await _apiClient.dio.post(
      '/auth/register',
      data: {
        'full_name': fullName,
        'username': username,
        'email': email,
        'password': password,
        'interests': interests,
      },
    );
    return AuthResponseModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AuthResponseModel> login({required String identifier, required String password}) async {
    final response = await _apiClient.dio.post(
      '/auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    return AuthResponseModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<UserModel> getCurrentUser() async {
    final response = await _apiClient.dio.get('/auth/me');
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }
}
