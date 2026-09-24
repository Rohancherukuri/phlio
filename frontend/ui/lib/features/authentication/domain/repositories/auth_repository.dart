// Repository contract for the authentication feature.
//
// Implemented by `data/repositories/auth_repository_impl.dart`. Use cases
// and the presentation controller depend only on this interface, which
// makes both trivially testable with a fake/mock implementation.

import '../../../../core/result/result.dart';
import '../entities/auth_tokens_entity.dart';
import '../entities/user_entity.dart';

abstract interface class AuthRepository {
  Future<Result<(UserEntity, AuthTokensEntity)>> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required List<String> interests,
  });

  Future<Result<(UserEntity, AuthTokensEntity)>> login({
    required String identifier,
    required String password,
  });

  Future<Result<UserEntity>> getCurrentUser();

  /// Clears any locally-persisted session. Always succeeds locally — there
  /// is no server-side "logout" endpoint in this build stage since access
  /// tokens are short-lived and stateless (see backend security notes).
  Future<void> logout();

  Future<bool> hasActiveSession();
}
