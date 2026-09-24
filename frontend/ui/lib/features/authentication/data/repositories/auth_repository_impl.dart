// Concrete `AuthRepository`: orchestrates the remote data source, maps
// Dio failures to `Failure`, and persists the resulting token pair.
//
// This is the only place in the authentication feature that touches both
// networking (`AuthRemoteDataSource`) and local storage (`TokenStorage`) —
// use cases and the controller only ever see the `AuthRepository`
// interface, never these two collaborators directly.

import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../../../core/storage/token_storage.dart' as storage;
import '../../domain/entities/auth_tokens_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required storage.TokenStorage tokenStorage,
  })  : _remoteDataSource = remoteDataSource,
        _tokenStorage = tokenStorage;

  final AuthRemoteDataSource _remoteDataSource;
  final storage.TokenStorage _tokenStorage;

  @override
  Future<Result<(UserEntity, AuthTokensEntity)>> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required List<String> interests,
  }) async {
    try {
      final response = await _remoteDataSource.register(
        fullName: fullName,
        username: username,
        email: email,
        password: password,
        interests: interests,
      );
      await _persistTokens(response.tokens);
      return Result.success((response.user.toEntity(), response.tokens));
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<(UserEntity, AuthTokensEntity)>> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await _remoteDataSource.login(identifier: identifier, password: password);
      await _persistTokens(response.tokens);
      return Result.success((response.user.toEntity(), response.tokens));
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<UserEntity>> getCurrentUser() async {
    try {
      final user = await _remoteDataSource.getCurrentUser();
      return Result.success(user.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<void> logout() => _tokenStorage.clearTokens();

  @override
  Future<bool> hasActiveSession() => _tokenStorage.hasSession;

  Future<void> _persistTokens(AuthTokensEntity tokens) {
    return _tokenStorage.saveTokens(
      storage.AuthTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken),
    );
  }
}
