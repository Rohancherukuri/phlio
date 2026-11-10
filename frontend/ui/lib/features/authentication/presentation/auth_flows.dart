// Sign-in flows beyond username + password: Google, Apple, and the
// two-factor step that any sign-in may need.
//
// Each flow ends in a [SignInOutcome]. On [SignedIn] the tokens are already
// saved and the caller hands the user to `AuthController.activateAccount`.
//
// Build settings (all --dart-define):
//   GOOGLE_SERVER_CLIENT_ID  the Google *web* OAuth client id (the backend's
//                            GOOGLE_CLIENT_IDS must include it). Needed on
//                            Android for an ID token.
//   GOOGLE_IOS_CLIENT_ID     the iOS OAuth client id (iOS only).
//   APPLE_SERVICE_ID         the Apple Services ID (Android / web flow).
//   APPLE_REDIRECT_URI       defaults to <API>/auth/oauth/apple/callback.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../app/config/app_config.dart';
import '../../../app/config/oauth_client_ids.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../../design_system/colors.dart';
import '../../../design_system/typography.dart';
import '../../../design_system/widgets/foxy_puppet.dart';
import '../data/models/user_model.dart';
import '../domain/entities/user_entity.dart';

// --dart-define values win; otherwise app/config/oauth_client_ids.dart.
const _googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID',
    defaultValue: kGoogleServerClientId);
const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID',
    defaultValue: kGoogleIosClientId);
const _appleServiceId =
    String.fromEnvironment('APPLE_SERVICE_ID', defaultValue: kAppleServiceId);
const _appleRedirectUri = String.fromEnvironment('APPLE_REDIRECT_URI');

sealed class SignInOutcome {
  const SignInOutcome();
}

class SignedIn extends SignInOutcome {
  const SignedIn(this.user, {this.isNewUser = false});
  final UserEntity user;
  final bool isNewUser;
}

class NeedsTwoFactor extends SignInOutcome {
  const NeedsTwoFactor(this.challenge, {this.isNewUser = false});
  final String challenge;
  final bool isNewUser;
}

class SignInFailed extends SignInOutcome {
  const SignInFailed(this.message);
  final String message;
}

class SignInCancelled extends SignInOutcome {
  const SignInCancelled();
}

/// The server's message for a failed request.
String authErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      if (data['error'] is Map && (data['error'] as Map)['message'] is String) {
        return (data['error'] as Map)['message'] as String;
      }
      if (data['detail'] is String) return data['detail'] as String;
    }
    return mapDioErrorToFailure(error).message;
  }
  return 'Something went wrong. Try again.';
}

/// Apple only accepts an https return URL registered on the Services ID, so
/// a local http API can't be used: fall back to the deployed API.
String get _appleRedirect {
  if (_appleRedirectUri.isNotEmpty) return _appleRedirectUri;
  final api = AppConfig.apiBaseUrl;
  final base = api.startsWith('https://')
      ? api
      : 'https://phlio-backend.onrender.com/api/v1';
  return '${base.replaceAll(RegExp(r'/+$'), '')}/auth/oauth/apple/callback';
}

abstract final class AuthFlows {
  static Dio get _dio => getIt<ApiClient>().dio;

  static bool get _isApplePlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Username / email / phone + password (may need a code next).
  static Future<SignInOutcome> password(String identifier, String password) =>
      _post('/auth/login', {'identifier': identifier, 'password': password});

  /// Second step: the challenge plus an authenticator or backup code.
  static Future<SignInOutcome> verify(String challenge, String code,
          {bool isNewUser = false}) =>
      _post('/auth/2fa/verify', {'challenge': challenge, 'code': code.trim()},
          isNewUser: isNewUser);

  static Future<SignInOutcome> google() async {
    final google = GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId:
          _googleServerClientId.isEmpty ? null : _googleServerClientId,
      clientId: !kIsWeb && Platform.isIOS && _googleIosClientId.isNotEmpty
          ? _googleIosClientId
          : null,
    );
    try {
      await google.signOut(); // always offer the account chooser
      final account = await google.signIn();
      if (account == null) return const SignInCancelled();
      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        debugPrint('Google sign-in: build with --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>');
        return const SignInFailed('Google sign-in isn\'t available yet.');
      }
      return _post('/auth/oauth/google', {'id_token': idToken});
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled') return const SignInCancelled();
      debugPrint('Google sign-in failed: ${e.code} ${e.message}');
      if (e.code == 'network_error') {
        return const SignInFailed(
            'No connection. Check your internet and try again.');
      }
      // ApiException 10 = DEVELOPER_ERROR: the Android OAuth client
      // (package + SHA-1) isn't registered in the same Google Cloud project
      // as GOOGLE_SERVER_CLIENT_ID, or that id isn't a *Web* client.
      final status =
          RegExp(r'ApiException: (\d+)').firstMatch('${e.message}')?.group(1);
      final developerError = status == '10';
      if (developerError) {
        debugPrint('Google DEVELOPER_ERROR: register an Android OAuth client '
            '(package + SHA-1 of the keystore that signed this build) in the '
            'same Google Cloud project as GOOGLE_SERVER_CLIENT_ID.');
      }
      // Short enough for Foxy's bubble; the details are in the log above.
      // Google Play services error number (ApiException N), shown so the
      // cause can be looked up: 7 network, 10 app not registered,
      // 12500 consent screen / account problem, 12502 already in progress.
      return SignInFailed(developerError
          ? 'Google doesn\'t recognise this app build yet.'
          : status == '12500'
              ? 'Google couldn\'t finish sign-in (12500). The app\'s consent screen needs setting up.'
              : 'Google sign-in didn\'t work${status != null ? ' ($status)' : ''}. Try again.');
    }
  }

  static Future<SignInOutcome> apple() async {
    if (!_isApplePlatform && _appleServiceId.isEmpty) {
      debugPrint('Apple sign-in: build with --dart-define=APPLE_SERVICE_ID=<Services ID>');
      return const SignInFailed('Apple sign-in isn\'t available yet.');
    }
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: _isApplePlatform
            ? null
            : WebAuthenticationOptions(
                clientId: _appleServiceId,
                redirectUri: Uri.parse(_appleRedirect),
              ),
      );
      final token = credential.identityToken;
      if (token == null) {
        return const SignInFailed('Apple didn\'t return a sign-in token.');
      }
      final name = [credential.givenName, credential.familyName]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
      return _post('/auth/oauth/apple',
          {'identity_token': token, if (name.isNotEmpty) 'full_name': name});
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const SignInCancelled();
      }
      return SignInFailed('Apple sign-in failed (${e.code.name}).');
    } on SignInWithAppleNotSupportedException {
      return const SignInFailed('Sign in with Apple isn\'t available here.');
    }
  }

  static Future<SignInOutcome> _post(String path, Map<String, dynamic> body,
      {bool isNewUser = false}) async {
    try {
      final json =
          ((await _dio.post(path, data: body)).data as Map).cast<String, dynamic>();
      final isNew = isNewUser || json['is_new_user'] == true;
      if (json['two_factor_required'] == true) {
        return NeedsTwoFactor(json['challenge'] as String, isNewUser: isNew);
      }
      final tokens = (json['tokens'] as Map).cast<String, dynamic>();
      await getIt<TokenStorage>().saveTokens(AuthTokens(
        accessToken: tokens['access_token'] as String,
        refreshToken: tokens['refresh_token'] as String,
      ));
      final user =
          UserModel.fromJson((json['user'] as Map).cast<String, dynamic>())
              .toEntity();
      return SignedIn(user, isNewUser: isNew);
    } catch (e) {
      return SignInFailed(authErrorMessage(e));
    }
  }
}

/// The two-factor step: a sheet asking for the authenticator code (or a
/// backup code). Returns the signed-in outcome, or null if dismissed.
Future<SignedIn?> showTwoFactorPrompt(
        BuildContext context, NeedsTwoFactor step) =>
    showModalBottomSheet<SignedIn>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _TwoFactorPrompt(step: step),
    );

class _TwoFactorPrompt extends StatefulWidget {
  const _TwoFactorPrompt({required this.step});
  final NeedsTwoFactor step;

  @override
  State<_TwoFactorPrompt> createState() => _TwoFactorPromptState();
}

class _TwoFactorPromptState extends State<_TwoFactorPrompt> {
  final _code = TextEditingController();
  bool _backup = false, _busy = false;
  String? _error;
  FoxyAct _act = FoxyAct.think;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length < (_backup ? 8 : 6) || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await AuthFlows.verify(widget.step.challenge, code,
        isNewUser: widget.step.isNewUser);
    if (!mounted) return;
    switch (outcome) {
      case SignedIn():
        HapticFeedback.heavyImpact();
        setState(() => _act = FoxyAct.hooray);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.pop(context, outcome);
      case SignInFailed(:final message):
        HapticFeedback.mediumImpact();
        setState(() {
          _busy = false;
          _error = message;
          _act = FoxyAct.oops;
        });
      default:
        setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: PhlioColors.border,
                  borderRadius: BorderRadius.circular(4)),
            ),
            FoxyPuppet(act: _act, size: 130),
            Text('Two-factor authentication', style: PhlioTypography.headline),
            const SizedBox(height: 6),
            Text(
              _backup
                  ? 'Enter one of your backup codes (like abcd-2345). Each works once.'
                  : 'Enter the 6-digit code from your authenticator app.',
              textAlign: TextAlign.center,
              style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _code,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType:
                  _backup ? TextInputType.text : TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: _backup ? 9 : 6,
              inputFormatters: _backup
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]'))]
                  : [FilteringTextInputFormatter.digitsOnly],
              style: PhlioTypography.headline
                  .copyWith(letterSpacing: _backup ? 4 : 10),
              decoration: InputDecoration(
                counterText: '',
                hintText: _backup ? 'xxxx-xxxx' : '••••••',
                errorText: _error,
              ),
              onChanged: (v) {
                if (_error != null) setState(() => _error = null);
                if (!_backup && v.length == 6) _submit();
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verify'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _backup = !_backup;
                _code.clear();
                _error = null;
              }),
              child: Text(_backup
                  ? 'Use the authenticator app instead'
                  : 'Use a backup code'),
            ),
          ]),
        ),
      ),
    );
  }
}
