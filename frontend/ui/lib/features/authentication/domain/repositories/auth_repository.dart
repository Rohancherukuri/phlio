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
    String? dateOfBirth,
    String? phoneNumber,
    String? country,
  });

  Future<Result<(UserEntity, AuthTokensEntity)>> login({
    required String identifier,
    required String password,
  });

  Future<Result<UserEntity>> getCurrentUser();

  /// The profile saved on this device for the current session (no network),
  /// so the app can open instantly at launch; null when there is none.
  Future<UserEntity?> cachedUser();

  /// Saves [user] as the current session's profile (see [cachedUser]).
  Future<void> rememberUser(UserEntity user);

  /// Clears any locally-persisted session. Always succeeds locally — there
  /// is no server-side "logout" endpoint in this build stage since access
  /// tokens are short-lived and stateless (see backend security notes).
  Future<void> logout();

  Future<bool> hasActiveSession();
}
