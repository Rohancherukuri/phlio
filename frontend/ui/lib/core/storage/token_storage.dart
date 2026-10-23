// Secure storage for the JWT access/refresh token pair.
//
// Wraps `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences
// on Android) behind a small, purpose-specific API rather than exposing a
// generic key-value store — every call site says what it means
// (`saveTokens`, `clearTokens`) instead of `write(key: '...', value: ...)`.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'phlio.auth.access_token';
  static const _refreshTokenKey = 'phlio.auth.refresh_token';

  Future<void> saveTokens(AuthTokens tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
  }

  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  Future<void> updateAccessToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<bool> get hasSession async => (await accessToken) != null;

  Future<List<Map<String, dynamic>>> savedAccounts() async {
    final raw = await _storage.read(key: 'phlio.auth.accounts');
    return raw == null
        ? []
        : (jsonDecode(raw) as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
  }

  Future<void> rememberAccount(
      {required String id, required String username, String? avatarUrl}) async {
    final access = await accessToken, refresh = await refreshToken;
    if (access == null || refresh == null) return;
    final accounts = await savedAccounts();
    accounts.removeWhere((a) => a['id'] == id);
    accounts.add({
      'id': id,
      'username': username,
      'avatar_url': avatarUrl,
      'access_token': access,
      'refresh_token': refresh
    });
    await _storage.write(
        key: 'phlio.auth.accounts', value: jsonEncode(accounts));
  }

  Future<void> forgetAccount(String id) async {
    final accounts = await savedAccounts();
    accounts.removeWhere((a) => a['id'] == id);
    await _storage.write(
        key: 'phlio.auth.accounts', value: jsonEncode(accounts));
  }
}
