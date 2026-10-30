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
    if (_error != null) return FoxyAct.sad;
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
    final result = await ref.read(authControllerProvider.notifier).login(
          identifier: _identifier.text.trim(),
          password: _password.text,
        );
    if (!mounted) return;
    result.when(
      success: (_) {
        HapticFeedback.heavyImpact();
        setState(() {
          _success = true;
          _submitting = false;
          _confetti++;
        });
        // Let the celebration land, then in.
        Future.delayed(const Duration(milliseconds: 1100), () {
          if (mounted) context.go('/home');
        });
      },
      failure: (failure) {
        HapticFeedback.mediumImpact();
        setState(() {
          _submitting = false;
          _error = failure.message;
          _oops++;
        });
      },
    );
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
