// Use case: authenticate with a username/email + password.
//
// Thin wrappers like this one might look unnecessary when they're a single
// pass-through call — the value shows up once a use case needs to
// orchestrate more than one repository (e.g. logging in *and* fetching
// user preferences in one step) without that logic leaking into a widget.

import '../../../../core/result/result.dart';
import '../entities/auth_tokens_entity.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class LoginUseCase {
  const LoginUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<(UserEntity, AuthTokensEntity)>> call({
    required String identifier,
    required String password,
  }) {
    return _repository.login(identifier: identifier, password: password);
  }
}
