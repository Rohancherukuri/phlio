// Use case: fetch the currently authenticated user's profile.

import '../../../../core/result/result.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class GetCurrentUserUseCase {
  const GetCurrentUserUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<UserEntity>> call() => _repository.getCurrentUser();
}
