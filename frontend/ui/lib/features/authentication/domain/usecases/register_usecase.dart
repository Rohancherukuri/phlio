// Use case: create a new Phlio account.

import '../../../../core/result/result.dart';
import '../entities/auth_tokens_entity.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class RegisterUseCase {
  const RegisterUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<(UserEntity, AuthTokensEntity)>> call({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required List<String> interests,
  }) {
    return _repository.register(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
      interests: interests,
    );
  }
}
