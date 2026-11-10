// Concrete `AuthRepository`: orchestrates the remote data source, maps
// Dio failures to `Failure`, and persists the resulting token pair.
//
// This is the only place in the authentication feature that touches both
// networking (`AuthRemoteDataSource`) and local storage (`TokenStorage`) —
// use cases and the controller only ever see the `AuthRepository`
// interface, never these two collaborators directly.

import 'dart:async';

import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../../../core/storage/token_storage.dart' as storage;
import '../../domain/entities/auth_tokens_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

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
    String? dateOfBirth,
    String? phoneNumber,
    String? country,
  }) async {
    try {
      final response = await _remoteDataSource.register(
        fullName: fullName,
        username: username,
        email: email,
        password: password,
        interests: interests,
        dateOfBirth: dateOfBirth,
        phoneNumber: phoneNumber,
      country: country,
      );
      await _persistTokens(response.tokens);
      final user = response.user.toEntity();
      unawaited(rememberUser(user));
      return Result.success((user, response.tokens));
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
      final response = await _remoteDataSource.login(
          identifier: identifier, password: password);
      await _persistTokens(response.tokens);
      final user = response.user.toEntity();
      unawaited(rememberUser(user));
      return Result.success((user, response.tokens));
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<UserEntity>> getCurrentUser() async {
    try {
      final json = await _remoteDataSource.getCurrentUserJson();
      final user = UserModel.fromJson(json).toEntity();
      unawaited(_tokenStorage.saveProfile(json));
      return Result.success(user);
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<UserEntity?> cachedUser() async {
    final json = await _tokenStorage.cachedProfile();
    if (json == null) return null;
    try {
      return UserModel.fromJson(json).toEntity();
    } catch (_) {
      return null; // saved by an older build with a different shape
    }
  }

  @override
  Future<void> rememberUser(UserEntity user) => _tokenStorage.saveProfile({
        'id': user.id,
        'username': user.username,
        'full_name': user.fullName,
        'email': user.email,
        'avatar_url': user.avatarUrl,
        'date_of_birth': user.dateOfBirth?.toIso8601String().substring(0, 10),
        'phone_number': user.phoneNumber,
        'country': user.country,
        'bio': user.bio,
        'interests': user.interests,
        'is_verified': user.isVerified,
        'created_at': user.createdAt.toIso8601String(),
      });

  @override
  Future<void> logout() => _tokenStorage.clearTokens();

  @override
  Future<bool> hasActiveSession() => _tokenStorage.hasSession;

  Future<void> _persistTokens(AuthTokensEntity tokens) {
    return _tokenStorage.saveTokens(
      storage.AuthTokens(
          accessToken: tokens.accessToken, refreshToken: tokens.refreshToken),
    );
  }
}
