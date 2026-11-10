// Secure storage for the JWT access/refresh token pair.
//
// Wraps `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences
// on Android) behind a small, purpose-specific API rather than exposing a
// generic key-value store — every call site says what it means
// (`saveTokens`, `clearTokens`) instead of `write(key: '...', value: ...)`.
//
// Performance: every API request needs the access token, and a secure-storage
// read is a platform-channel round trip plus decryption (several ms on
// Android, more on a busy main thread). Tokens are therefore read from the
// Keystore/Keychain once and kept in memory; every write goes through this
// class, so the in-memory copy can never drift from what is stored.
// Concurrent first reads share one storage read.

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

  String? _access, _refresh, _profileRaw;
  Future<void>? _loaded;
  final _clearListeners = <Future<void> Function()>[];

  /// Runs [listener] whenever the session is cleared (sign-out), e.g. to wipe
  /// cached API responses that belong to the old account.
  void addClearListener(Future<void> Function() listener) =>
      _clearListeners.add(listener);

  Future<void> _ensureLoaded() => _loaded ??= () async {
        final values = await Future.wait([
          _storage.read(key: _accessTokenKey),
          _storage.read(key: _refreshTokenKey),
          _storage.read(key: _profileKey),
        ]);
        _access = values[0];
        _refresh = values[1];
        _profileRaw = values[2];
      }();

  /// Remembers the signed-in user's profile so the next launch opens the app
  /// straight away instead of waiting for `/auth/me` (a sleeping server can
  /// take a minute to answer). Tagged with a fingerprint of the refresh token,
  /// so it is only ever shown for the session it belongs to.
  Future<void> saveProfile(Map<String, dynamic> user) async {
    await _ensureLoaded();
    final refresh = _refresh;
    if (refresh == null) return;
    final raw = jsonEncode({'session': _fingerprint(refresh), 'user': user});
    if (raw == _profileRaw) return;
    _profileRaw = raw;
    await _storage.write(key: _profileKey, value: raw);
  }

  /// The profile saved by [saveProfile] for the current session, or null.
  Future<Map<String, dynamic>?> cachedProfile() async {
    await _ensureLoaded();
    final raw = _profileRaw, refresh = _refresh;
    if (raw == null || refresh == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['session'] != _fingerprint(refresh)) return null;
      return Map<String, dynamic>.from(decoded['user'] as Map);
    } catch (_) {
      return null;
    }
  }

  // FNV-1a: the token itself is never written next to the profile.
  static String _fingerprint(String token) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(token)) {
      hash = (hash ^ unit) * 0x100000001b3;
    }
    return (hash & 0xFFFFFFFF).toRadixString(16) +
        ((hash >> 32) & 0xFFFFFFFF).toRadixString(16);
  }

  /// Starts reading the tokens early (called at boot, before the first frame).
  Future<void> warmUp() => _ensureLoaded().catchError((_) {});

  static const _accessTokenKey = 'phlio.auth.access_token';
  static const _refreshTokenKey = 'phlio.auth.refresh_token';
  static const _profileKey = 'phlio.auth.profile';

  Future<void> saveTokens(AuthTokens tokens) async {
    await _ensureLoaded();
    _access = tokens.accessToken;
    _refresh = tokens.refreshToken;
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
  }

  Future<String?> get accessToken async {
    await _ensureLoaded();
    return _access;
  }

  Future<String?> get refreshToken async {
    await _ensureLoaded();
    return _refresh;
  }

  Future<void> updateAccessToken(String accessToken) async {
    await _ensureLoaded();
    _access = accessToken;
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  Future<void> clearTokens() async {
    await _ensureLoaded();
    _access = null;
    _refresh = null;
    _profileRaw = null;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _profileKey);
    for (final listener in List.of(_clearListeners)) {
      try {
        await listener();
      } catch (_) {
        // A failing listener (e.g. cache wipe) must never block sign-out.
      }
    }
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
