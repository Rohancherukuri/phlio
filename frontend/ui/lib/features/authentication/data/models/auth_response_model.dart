// DTO for `POST /auth/register` and `POST /auth/login` responses, which
// bundle a user profile with a fresh token pair (see
// `backend/app/api/v1/auth.py::AuthResponse`).

import '../../domain/entities/auth_tokens_entity.dart';
import 'user_model.dart';

class AuthResponseModel {
  const AuthResponseModel({required this.user, required this.tokens});

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    final tokensJson = json['tokens'] as Map<String, dynamic>;
    return AuthResponseModel(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      tokens: AuthTokensEntity(
        accessToken: tokensJson['access_token'] as String,
        refreshToken: tokensJson['refresh_token'] as String,
      ),
    );
  }

  final UserModel user;
  final AuthTokensEntity tokens;
}
