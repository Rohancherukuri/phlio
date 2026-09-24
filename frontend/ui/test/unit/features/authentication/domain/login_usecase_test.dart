// Tests for `LoginUseCase` — a thin pass-through today, but this is the
// pattern every other use case in the app follows, so it's worth
// establishing the mocktail-based testing approach here once.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phlio/core/result/result.dart';
import 'package:phlio/features/authentication/domain/entities/auth_tokens_entity.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/domain/repositories/auth_repository.dart';
import 'package:phlio/features/authentication/domain/usecases/login_usecase.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

UserEntity _buildUser() {
  return UserEntity(
    id: 'usr_test',
    username: 'testuser',
    fullName: 'Test User',
    email: 'test@example.com',
    bio: '',
    interests: const [],
    isVerified: false,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  late _MockAuthRepository repository;
  late LoginUseCase useCase;

  setUp(() {
    repository = _MockAuthRepository();
    useCase = LoginUseCase(repository);
  });

  test('delegates to AuthRepository.login with the given credentials', () async {
    final user = _buildUser();
    const tokens = AuthTokensEntity(accessToken: 'access-123', refreshToken: 'refresh-456');
    when(() => repository.login(identifier: 'testuser', password: 'password123'))
        .thenAnswer((_) async => Result.success((user, tokens)));

    final result = await useCase(identifier: 'testuser', password: 'password123');

    expect(result.isSuccess, isTrue);
    final (returnedUser, returnedTokens) = result.valueOrNull!;
    expect(returnedUser.username, 'testuser');
    expect(returnedTokens.accessToken, 'access-123');
    verify(() => repository.login(identifier: 'testuser', password: 'password123')).called(1);
  });

  test('propagates a Failure from the repository unchanged', () async {
    const failure = Failure(code: 'unauthorized', message: 'Incorrect username/email or password.');
    when(() => repository.login(identifier: any(named: 'identifier'), password: any(named: 'password')))
        .thenAnswer((_) async => const Result.failure(failure));

    final result = await useCase(identifier: 'wrong', password: 'wrong');

    expect(result.isFailure, isTrue);
    result.when(
      success: (_) => fail('expected a failure'),
      failure: (f) => expect(f.code, 'unauthorized'),
    );
  });
}
