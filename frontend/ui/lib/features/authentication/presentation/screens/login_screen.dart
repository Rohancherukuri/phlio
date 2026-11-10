// Log in — Foxy greets you (Duolingo-style) and reacts as you go.
//
// Foxy is a live puppet ([FoxyPuppet]) next to a speech bubble. He waves
// hello, turns toward what you type, shuts his eyes while you enter a
// password (and owns up to peeking if you reveal it), thinks while the
// request is out, shakes his head and tells you what went wrong on a bad
// password, and bounces under confetti when you're in.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../onboarding/presentation/widgets/onboarding_kit.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../auth_flows.dart';
import '../controllers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _identifierFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _submitting = false;
  bool _success = false;
  bool _greeting = true;
  bool _talking = false;
  String? _error;

  /// Which social sign-in is running ('google' / 'apple'), for its spinner.
  String? _socialBusy;
  int _oops = 0;
  int _confetti = 0;
  Timer? _greetTimer;

  @override
  void initState() {
    super.initState();
    for (final node in [_identifierFocus, _passwordFocus]) {
      node.addListener(() => setState(() => _greeting = false));
    }
    _greetTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _greeting = false);
    });
  }

  @override
  void dispose() {
    _greetTimer?.cancel();
    _identifier.dispose();
    _password.dispose();
    _identifierFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _identifier.text.trim().isNotEmpty && _password.text.isNotEmpty;

  FoxyAct get _act {
    if (_success) return FoxyAct.cheer;
    if (_submitting) return FoxyAct.think;
    if (_error != null) return FoxyAct.oops;
    if (_passwordFocus.hasFocus || _password.text.isNotEmpty) {
      if (_obscure && _passwordFocus.hasFocus) return FoxyAct.peek;
    }
    if (_greeting) return FoxyAct.wave;
    return _talking ? FoxyAct.talk : FoxyAct.idle;
  }

  String get _line {
    if (_success) return 'You\'re in!';
    if (_submitting) return 'One sec…';
    if (_error != null) return _error!;
    if (_passwordFocus.hasFocus) {
      return _obscure ? 'I\'m not looking, promise.' : 'Okay, I peeked a little.';
    }
    if (_identifierFocus.hasFocus) {
      return 'Your username, email or mobile number all work.';
    }
    return 'Welcome back! Log in to pick up where you left off.';
  }

  /// Foxy follows the caret: further right as the identifier gets longer.
  double get _lean {
    if (!_identifierFocus.hasFocus) return 0;
    return (-0.4 + _identifier.text.length / 20).clamp(-0.4, 0.8);
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    await _handle(
        await AuthFlows.password(_identifier.text.trim(), _password.text));
  }

  /// Google / Apple: same ending as a password sign-in.
  Future<void> _socialSignIn(
      Future<SignInOutcome> Function() flow, String which) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _socialBusy = which;
      _error = null;
    });
    await _handle(await flow());
  }

  /// Finishes any sign-in: the two-factor step if needed, then in.
  Future<void> _handle(SignInOutcome outcome) async {
    if (!mounted) return;
    if (outcome is NeedsTwoFactor) {
      final done = await showTwoFactorPrompt(context, outcome);
      if (!mounted) return;
      outcome = done ?? const SignInCancelled();
    }
    switch (outcome) {
      case SignedIn(:final user, :final isNewUser):
        ref.read(authControllerProvider.notifier).activateAccount(user);
        HapticFeedback.heavyImpact();
        setState(() {
          _success = true;
          _submitting = false;
          _socialBusy = null;
          _confetti++;
        });
        if (isNewUser) await _askCountry();
        // Let the celebration land, then in.
        Future.delayed(const Duration(milliseconds: 1100), () {
          if (mounted) context.go(isNewUser ? '/tour' : '/home');
        });
      case SignInFailed(:final message):
        HapticFeedback.mediumImpact();
        setState(() {
          _submitting = false;
          _socialBusy = null;
          _error = message;
          _oops++;
        });
      default:
        setState(() {
          _submitting = false;
          _socialBusy = null;
        });
    }
  }

  /// New Google / Apple accounts pick their country (it sets the Pay
  /// currency), like the sign-up form asks.
  Future<void> _askCountry() async {
    String? code;
    final closed = Completer<void>();
    showCountryPicker(
      context: context,
      countryListTheme: CountryListThemeData(
        backgroundColor: PhlioColors.surface,
        textStyle: PhlioTypography.body.copyWith(color: PhlioColors.textPrimary),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      onSelect: (country) => code = country.countryCode,
      onClosed: () {
        if (!closed.isCompleted) closed.complete();
      },
    );
    await closed.future;
    if (code == null) return;
    try {
      await getIt<ApiClient>()
          .dio
          .put('/auth/me/country', data: {'country': code});
    } catch (_) {}
  }

  void _forgotPassword() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FoxyPuppet(act: FoxyAct.think, size: 140),
              const SizedBox(height: 8),
              Text('Trouble logging in?',
                  style: PhlioTypography.headline, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Self-serve password reset isn\'t live yet. Log in with your '
                'username, email or mobile number — any of them works with '
                'the same password.',
                style: PhlioTypography.body.copyWith(fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              PhlioSecondaryButton(
                  label: 'Got it', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: PhlioColors.backgroundDeep,
      body: OnboardingBackdrop(
        child: Stack(
          children: [
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: AutofillGroup(
                        child: Column(
                          children: [
                            const SizedBox(height: 18),
                            StaggerIn(
                              child: Image.asset(
                                'assets/images/logo/logo_wordmark.png',
                                height: 34,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (_, __, ___) => Text('Phlio',
                                    style: PhlioTypography.displayMedium),
                              ),
                            ),
                            const Spacer(flex: 2),
                            _foxyRow(keyboard),
                            const SizedBox(height: 22),
                            StaggerIn(
                              delay: const Duration(milliseconds: 200),
                              child: OnboardingField(
                                controller: _identifier,
                                focusNode: _identifierFocus,
                                label: 'Username, email or mobile',
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                error: _error != null,
                                onChanged: (_) => setState(() => _error = null),
                                onSubmitted: (_) => _passwordFocus.requestFocus(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            StaggerIn(
                              delay: const Duration(milliseconds: 260),
                              child: OnboardingField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                label: 'Password',
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                error: _error != null,
                                onChanged: (_) => setState(() => _error = null),
                                onSubmitted: (_) => _submit(),
                                suffix: _password.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: _obscure
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: () =>
                                            setState(() => _obscure = !_obscure),
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          size: 22,
                                          color: PhlioColors.textMuted,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            StaggerIn(
                              delay: const Duration(milliseconds: 320),
                              child: PhlioPrimaryButton(
                                label: 'Log in',
                                isLoading: _submitting,
                                onPressed: _canSubmit ? _submit : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            StaggerIn(
                              delay: const Duration(milliseconds: 360),
                              child: OnboardingLink(
                                  label: 'Forgot password?',
                                  onTap: _forgotPassword),
                            ),
                            const SizedBox(height: 10),
                            StaggerIn(
                              delay: const Duration(milliseconds: 380),
                              child: _orDivider(),
                            ),
                            const SizedBox(height: 12),
                            StaggerIn(
                              delay: const Duration(milliseconds: 400),
                              child: Row(children: [
                                Expanded(
                                  child: _SocialButton(
                                    label: 'Google',
                                    logo: SvgPicture.string(_googleG,
                                        width: 20, height: 20),
                                    light: true,
                                    busy: _socialBusy == 'google',
                                    onPressed: _submitting
                                        ? null
                                        : () => _socialSignIn(AuthFlows.google, 'google'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _SocialButton(
                                    label: 'Apple',
                                    logo: const Icon(Icons.apple,
                                        size: 22, color: Colors.white),
                                    light: false,
                                    busy: _socialBusy == 'apple',
                                    onPressed: _submitting
                                        ? null
                                        : () => _socialSignIn(AuthFlows.apple, 'apple'),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 18),
                            const Spacer(flex: 3),
                            StaggerIn(
                              delay: const Duration(milliseconds: 420),
                              child: PhlioSecondaryButton(
                                label: 'Create new account',
                                onPressed: () => context.go('/signup'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('PEOPLE. PLACES. POSSIBILITIES.',
                                style: PhlioTypography.tagline.copyWith(
                                    fontSize: 9.5,
                                    color: PhlioColors.textMuted)),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ConfettiBurst(
                  trigger: _confetti, origin: const Alignment(0, -0.35)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orDivider() => Row(children: [
        const Expanded(child: Divider(color: PhlioColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or continue with',
              style: PhlioTypography.caption
                  .copyWith(color: PhlioColors.textMuted)),
        ),
        const Expanded(child: Divider(color: PhlioColors.border)),
      ]);

  Widget _foxyRow(bool keyboard) {
    final size = keyboard ? 104.0 : 150.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: size),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, s, _) => FoxyPuppet(
            act: _act,
            size: s,
            talking: _talking,
            lean: _lean,
            oopsSignal: _oops,
          ),
        ),
        Expanded(
          child: Transform.translate(
            offset: const Offset(-10, 0),
            child: FoxyBubble(
              text: _line,
              tone: _error != null ? PhlioColors.danger : null,
              onTyping: (typing) {
                if (mounted && typing != _talking) {
                  setState(() => _talking = typing);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// "Continue with Google / Apple": white (Google) or black (Apple) pill.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.logo,
    required this.light,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final Widget logo;
  final bool light, busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = light ? const Color(0xFF1F1F1F) : Colors.white;
    return Semantics(
      button: true,
      label: 'Continue with $label',
      child: Material(
        color: light ? Colors.white : Colors.black,
        shape: StadiumBorder(
            side: BorderSide(
                color: light ? Colors.transparent : PhlioColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: SizedBox(
            height: 50,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (busy)
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else
                logo,
              const SizedBox(width: 10),
              Text(label,
                  style: PhlioTypography.bodyStrong.copyWith(color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Google's standard multicolour "G" for the sign-in button (per Google's
/// sign-in branding guidelines).
const _googleG = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';
