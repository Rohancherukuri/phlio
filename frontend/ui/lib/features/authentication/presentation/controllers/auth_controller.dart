// Authentication state management (Riverpod).
//
// `authControllerProvider` exposes `AsyncValue<UserEntity?>`:
//   - loading   -> still checking for a persisted session at app startup
//   - data(null)      -> no active session (show auth screens)
//   - data(UserEntity) -> signed in (show the main app shell)
//   - error     -> session check itself failed unexpectedly (treated as
//                  "unauthenticated" by the router, see app/router/app_router.dart)
//
// `login`/`register` are plain async methods returning `Result` so the
// screen can show a field-level or form-level error message inline,
// *in addition* to updating the shared session state on success.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/get_current_user_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/register_usecase.dart';

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => getIt<AuthRepository>());

final authControllerProvider =
    AsyncNotifierProvider<AuthController, UserEntity?>(AuthController.new);

class AuthController extends AsyncNotifier<UserEntity?> {
  late final LoginUseCase _loginUseCase;
  late final RegisterUseCase _registerUseCase;
  late final GetCurrentUserUseCase _getCurrentUserUseCase;
  late final LogoutUseCase _logoutUseCase;

  @override
  Future<UserEntity?> build() async {
    final repository = ref.read(authRepositoryProvider);
    _loginUseCase = LoginUseCase(repository);
    _registerUseCase = RegisterUseCase(repository);
    _getCurrentUserUseCase = GetCurrentUserUseCase(repository);
    _logoutUseCase = LogoutUseCase(repository);

    if (!await repository.hasActiveSession()) return null;

    final result = await _getCurrentUserUseCase();
    return result.when(
      success: (user) => user,
      // A stored-but-invalid token (e.g. expired refresh token too) means
      // "not actually signed in" from the UI's point of view.
      failure: (_) => null,
    );
  }

  Future<Result<UserEntity>> login(
      {required String identifier, required String password}) async {
    final result =
        await _loginUseCase(identifier: identifier, password: password);
    return result.when(
      success: (data) {
        final (user, _) = data;
        state = AsyncData(user);
        return Result.success(user);
      },
      failure: (failure) => Result.failure(failure),
    );
  }

  Future<Result<UserEntity>> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required List<String> interests,
    String? dateOfBirth,
    String? phoneNumber,
  }) async {
    final result = await _registerUseCase(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
      interests: interests,
      dateOfBirth: dateOfBirth,
      phoneNumber: phoneNumber,
    );
    return result.when(
      success: (data) {
        final (user, _) = data;
        state = AsyncData(user);
        return Result.success(user);
      },
      failure: (failure) => Result.failure(failure),
    );
  }

  Future<void> logout() async {
    await _logoutUseCase();
    state = const AsyncData(null);
  }

  /// Called by `ApiClient.onSessionExpired` (wired in `service_locator.dart`)
  /// when a refresh attempt fails mid-session — forces the router back to
  /// the auth flow without the user explicitly tapping "log out".
  void forceSignOut() {
    state = const AsyncData(null);
  }
}
