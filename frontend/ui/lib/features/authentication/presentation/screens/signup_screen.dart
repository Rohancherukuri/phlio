// Sign up — one question per screen, asked by Foxy (Duolingo-style).
//
//   Join Phlio → mobile number (or email) → [email] → password → birthday
//   → name → username → interests → terms ("I agree" creates the account)
//   → profile picture → welcome
//
// Foxy is a live puppet ([FoxyPuppet]) who stays on screen for the whole
// flow: centre stage on the intro and welcome screens, then beside each
// question, which he "says" in a speech bubble that types out while he
// talks. He nods when an answer is accepted, shakes his head and says what's
// wrong when it isn't, shuts his eyes while you type a password, tilts his
// head over usernames, swoons when you pick interests and bounces under
// confetti at the end.
//
// Creating the account signs the person in, which would normally make the
// router jump straight to /home. [SignupScreen.holdForOnboarding] keeps
// them here for the last two screens (profile picture and welcome).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../onboarding/presentation/widgets/onboarding_kit.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../controllers/auth_controller.dart';

const _availableInterests = [
  'Art',
  'Tech',
  'Gaming',
  'Travel',
  'Food',
  'Music',
  'Sports',
  'Learning',
  'Shopping',
  'Communities',
  'Film',
  'Fitness',
  'Photography',
  'Books',
];

int _passwordScore(String password) {
  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'[a-z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password) &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
  return score;
}

enum _Step {
  intro,
  contact,
  email,
  password,
  birthday,
  name,
  username,
  interests,
  terms,
  photo,
  welcome,
}

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  /// True from "I agree" until the welcome screen is dismissed, so the
  /// router lets a freshly signed-in person finish onboarding.
  static final ValueNotifier<bool> holdForOnboarding = ValueNotifier(false);

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _passwordFocus = FocusNode();

  late Country _country;
  bool _usePhone = true;
  bool _obscure = true;
  DateTime? _birthday;
  final Set<String> _interests = {};

  int _index = 0;
  bool _forward = true;
  bool _submitting = false;
  bool _registered = false;
  final Map<_Step, String> _errors = {};

  // Foxy
  bool _talking = false;
  int _nod = 0;
  int _oops = 0;
  int _hop = 0;
  int _confetti = 0;
  FoxyAct? _flash; // a short-lived reaction (love, clap)
  Timer? _flashTimer;
  String? _reaction; // a one-off line that replaces the step's question
  bool _introSecondLine = false;
  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    final region =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    _country = Country.tryParse(region ?? '') ?? Country.parse('IN');
    _passwordFocus.addListener(() => setState(() {}));
    _introTimer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted && _current == _Step.intro) {
        setState(() => _introSecondLine = true);
      }
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _introTimer?.cancel();
    _passwordFocus.dispose();
    for (final c in [_phone, _email, _password, _name, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Flow

  List<_Step> get _flow => [
        _Step.intro,
        _Step.contact,
        if (_usePhone) _Step.email,
        _Step.password,
        _Step.birthday,
        _Step.name,
        _Step.username,
        _Step.interests,
        _Step.terms,
        _Step.photo,
        _Step.welcome,
      ];

  _Step get _current => _flow[_index];

  bool get _isHero => _current == _Step.intro || _current == _Step.welcome;

  String get _firstName {
    final first = _name.text.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'friend' : first;
  }

  void _go(int index) {
    FocusScope.of(context).unfocus();
    final target = index.clamp(0, _flow.length - 1);
    setState(() {
      _forward = target > _index;
      _index = target;
      _reaction = null;
    });
    if (_flow[target] == _Step.welcome) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        setState(() => _confetti++);
      });
    }
  }

  void _back() {
    if (_registered) return; // the account exists; only forward from here
    if (_index == 0) {
      context.go('/login');
      return;
    }
    _go(_index - 1);
  }

  void _fail(_Step step, String message) {
    HapticFeedback.mediumImpact();
    setState(() {
      _errors[step] = message;
      _oops++;
    });
  }

  void _clearError(_Step step) {
    if (_errors.containsKey(step)) setState(() => _errors.remove(step));
  }

  void _flashAct(FoxyAct act, {Duration duration = const Duration(milliseconds: 1400)}) {
    _flashTimer?.cancel();
    setState(() => _flash = act);
    _flashTimer = Timer(duration, () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _next() {
    final error = _validate(_current);
    if (error != null) return _fail(_current, error);
    HapticFeedback.lightImpact();
    setState(() {
      _errors.remove(_current);
      _nod++;
    });
    if (_current == _Step.name && _username.text.isEmpty) {
      _username.text = _suggestions().first;
    }
    // Let the nod land before the question changes.
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _go(_index + 1);
    });
  }

  String? _validate(_Step step) {
    switch (step) {
      case _Step.contact:
        if (_usePhone) {
          final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 6 || digits.length > 14) {
            return 'Hmm, that number looks a little short. Mind checking it?';
          }
          return null;
        }
        return _emailError();
      case _Step.email:
        return _emailError();
      case _Step.password:
        if (_password.text.length < 8) {
          return 'It needs at least 8 characters.';
        }
        if (_password.text.toLowerCase() == 'password' ||
            RegExp(r'^(.)\1+$').hasMatch(_password.text)) {
          return 'That one\'s too easy to guess. Try something less common.';
        }
        return null;
      case _Step.birthday:
        final birthday = _birthday;
        if (birthday == null) return 'Spin the wheel to your birthday.';
        if (_age(birthday) < 13) {
          return 'Sorry, you need to be at least 13 to join Phlio.';
        }
        return null;
      case _Step.name:
        return _name.text.trim().isEmpty ? 'I didn\'t catch your name.' : null;
      case _Step.username:
        final value = _username.text.trim();
        if (value.length < 3) return 'Usernames need at least 3 characters.';
        if (value.length > 30) return 'Keep it to 30 characters or fewer.';
        if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(value)) {
          return 'Only letters, numbers, full stops and underscores, please.';
        }
        return null;
      default:
        return null;
    }
  }

  String? _emailError() =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())
          ? null
          : 'That email doesn\'t look quite right.';

  int _age(DateTime birthday) {
    final now = DateTime.now();
    var age = now.year - birthday.year;
    if (now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age;
  }

  String? get _phoneNumber {
    final digits = _phone.text.replaceAll(RegExp(r'[\s()\-]'), '');
    if (!_usePhone || digits.isEmpty) return null;
    return digits.startsWith('+') ? digits : '+${_country.phoneCode}$digits';
  }

  List<String> _suggestions() {
    final words = _name.text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    var base = words.join('.');
    if (base.length < 3) base = 'phlio.${base.isEmpty ? 'friend' : base}';
    if (base.length > 24) base = base.substring(0, 24);
    final seed = _name.text.hashCode.abs();
    final year = _birthday == null ? (seed % 90 + 10) : _birthday!.year % 100;
    return {
      base,
      '${base.replaceAll('.', '_')}${(seed % 900 + 100)}',
      '$base.${year.toString().padLeft(2, '0')}',
    }.toList();
  }

  Future<void> _register() async {
    setState(() {
      _submitting = true;
      _errors.remove(_Step.terms);
    });
    SignupScreen.holdForOnboarding.value = true;
    final result = await ref.read(authControllerProvider.notifier).register(
          fullName: _name.text.trim(),
          username: _username.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          phoneNumber: _phoneNumber,
          dateOfBirth: _birthday?.toIso8601String().split('T').first,
          interests: _interests.map((i) => i.toLowerCase()).toList(),
        );
    if (!mounted) return;
    result.when(
      success: (_) {
        HapticFeedback.mediumImpact();
        setState(() {
          _registered = true;
          _submitting = false;
        });
        _flashAct(FoxyAct.clap, duration: const Duration(milliseconds: 1600));
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) _go(_flow.indexOf(_Step.photo));
        });
      },
      failure: (failure) {
        SignupScreen.holdForOnboarding.value = false;
        setState(() => _submitting = false);
        // Send the person back to the answer the server didn't accept.
        final message = failure.message;
        final lower = message.toLowerCase();
        final step = lower.contains('username')
            ? _Step.username
            : lower.contains('phone')
                ? _Step.contact
                : lower.contains('email')
                    ? (_usePhone ? _Step.email : _Step.contact)
                    : lower.contains('password')
                        ? _Step.password
                        : lower.contains('birth')
                            ? _Step.birthday
                            : _Step.terms;
        if (step != _Step.terms) _go(_flow.indexOf(step));
        _fail(step, message);
      },
    );
  }

  void _finish() {
    SignupScreen.holdForOnboarding.value = false;
    context.go('/home');
  }

  Future<void> _pickPhoto() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (camera == null || !mounted) return;
    final avatar = ref.read(avatarProvider.notifier);
    try {
      final file = await avatar.pickAndCrop(camera: camera);
      if (file == null || !mounted) return;
      avatar.stage(file);
      avatar.setFilter(0); // persists the new picture
      setState(() => _reaction = 'Looking good.');
      _flashAct(FoxyAct.love);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  // ---------------------------------------------------------------------------
  // What Foxy says and does

  String get _line {
    final error = _errors[_current];
    if (error != null) return error;
    if (_reaction != null) return _reaction!;
    switch (_current) {
      case _Step.intro:
        return _introSecondLine
            ? 'I\'ll get your Phlio account ready. It takes about a minute.'
            : 'Hi, I\'m Foxy!';
      case _Step.contact:
        return _usePhone ? 'What\'s your mobile number?' : 'What\'s your email?';
      case _Step.email:
        return 'And an email, so you can always get back in.';
      case _Step.password:
        if (_password.text.isNotEmpty && _passwordScore(_password.text) >= 3) {
          return 'Ooh, that\'s a strong one.';
        }
        return 'Make a password. I won\'t look.';
      case _Step.birthday:
        return 'When\'s your birthday?';
      case _Step.name:
        return 'What should I call you?';
      case _Step.username:
        return 'Nice to meet you, $_firstName! Pick a username.';
      case _Step.interests:
        return 'What are you into? Pick a few.';
      case _Step.terms:
        return _submitting
            ? 'Setting things up…'
            : 'Last thing: a quick look at the rules.';
      case _Step.photo:
        return 'Add a photo so friends can find you.';
      case _Step.welcome:
        return 'You\'re all set, $_firstName!';
    }
  }

  FoxyAct get _act {
    if (_flash != null) return _flash!;
    switch (_current) {
      case _Step.intro:
        return FoxyAct.wave;
      case _Step.password:
        final typing = _password.text.isNotEmpty || _passwordFocus.hasFocus;
        return typing && _obscure ? FoxyAct.peek : FoxyAct.idle;
      case _Step.birthday:
        return _birthday == null ? FoxyAct.think : FoxyAct.idle;
      case _Step.username:
        return FoxyAct.think;
      case _Step.terms:
        return _submitting ? FoxyAct.think : FoxyAct.idle;
      case _Step.welcome:
        return FoxyAct.cheer;
      default:
        return _talking ? FoxyAct.talk : FoxyAct.idle;
    }
  }

  double get _lean {
    final controller = switch (_current) {
      _Step.contact => _usePhone ? _phone : _email,
      _Step.email => _email,
      _Step.name => _name,
      _Step.username => _username,
      _ => null,
    };
    if (controller == null || controller.text.isEmpty) return 0;
    return (controller.text.length / 18).clamp(0.0, 0.8);
  }

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final step = _current;
    final hero = _isHero;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: PhlioColors.backgroundDeep,
        body: OnboardingBackdrop(
          child: Stack(
            children: [
              SafeArea(
                child: LayoutBuilder(builder: (context, box) {
                  final w = box.maxWidth;
                  final h = box.maxHeight;
                  final foxSize = hero
                      ? math.min(w * 0.64, h * 0.36).clamp(170.0, 280.0)
                      : (keyboard ? 92.0 : 124.0);
                  final foxTop = hero ? h * 0.27 : 50.0;
                  final foxLeft = hero ? (w - foxSize) / 2 : 6.0;
                  final contentTop = foxTop + foxSize + (hero ? 0 : 4);
                  return Stack(
                    children: [
                      // The answer area for this step.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: hero ? contentTop : contentTop,
                        bottom: 0,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 360),
                          reverseDuration: const Duration(milliseconds: 200),
                          layoutBuilder: (current, previous) => Stack(
                            fit: StackFit.expand,
                            children: [...previous, if (current != null) current],
                          ),
                          transitionBuilder: (child, animation) {
                            final fade = CurvedAnimation(
                                parent: animation, curve: Curves.easeOut);
                            if (child.key != ValueKey(step)) {
                              return FadeTransition(opacity: fade, child: child);
                            }
                            return FadeTransition(
                              opacity: fade,
                              child: SlideTransition(
                                position: Tween(
                                  begin: Offset(_forward ? 0.12 : -0.12, 0),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic)),
                                child: child,
                              ),
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey(step),
                            child: _page(step, keyboard),
                          ),
                        ),
                      ),
                      // Foxy.
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 620),
                        curve: Curves.easeInOutCubic,
                        left: foxLeft,
                        top: foxTop,
                        width: foxSize,
                        height: foxSize,
                        child: LayoutBuilder(
                          builder: (context, fox) => FoxyPuppet(
                            act: _act,
                            size: fox.maxWidth,
                            talking: _talking,
                            lean: _lean,
                            nodSignal: _nod,
                            oopsSignal: _oops,
                            hopSignal: _hop,
                          ),
                        ),
                      ),
                      // What he says.
                      if (hero)
                        Positioned(
                          left: 24,
                          right: 24,
                          // His art leaves air above his ears.
                          bottom: h - foxTop - foxSize * 0.16,
                          child: Center(child: _bubble(BubbleTail.bottom)),
                        )
                      else
                        Positioned(
                          left: foxLeft + foxSize - 8,
                          right: 18,
                          top: foxTop + (keyboard ? 6 : 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _bubble(BubbleTail.left),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 50,
                        child: _header(hero),
                      ),
                    ],
                  );
                }),
              ),
              Positioned.fill(child: ConfettiBurst(trigger: _confetti)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(BubbleTail tail) {
    final error = _errors.containsKey(_current);
    return FoxyBubble(
      key: ValueKey(tail),
      text: _line,
      tail: tail,
      tone: error ? PhlioColors.danger : null,
      style: tail == BubbleTail.bottom
          ? PhlioTypography.displayMedium.copyWith(fontSize: 23, height: 1.25)
          : null,
      onTyping: (typing) {
        if (mounted && typing != _talking) setState(() => _talking = typing);
      },
    );
  }

  Widget _header(bool hero) {
    final showBack = !_registered;
    final steps = _flow.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 24, 0),
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: showBack ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              tooltip: 'Back',
              onPressed: showBack ? _back : null,
              icon: Icon(hero ? Icons.close_rounded : Icons.arrow_back_rounded,
                  color: PhlioColors.textSecondary),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedOpacity(
              opacity: hero ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: OnboardingProgress(value: _index / steps),
            ),
          ),
        ],
      ),
    );
  }

  /// The pinned bottom bar: one big button (plus an optional link).
  Widget _footer({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
    Widget? secondary,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhlioPrimaryButton(label: label, isLoading: loading, onPressed: onPressed),
          if (secondary != null) ...[const SizedBox(height: 6), secondary],
        ],
      ),
    );
  }

  /// Answer area + pinned footer for a question step.
  Widget _formPage({
    required List<Widget> children,
    String primary = 'Continue',
    VoidCallback? onPrimary,
    bool loading = false,
    Widget? secondary,
    String? hint,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaggerIn(
                  delay: const Duration(milliseconds: 220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 12),
                  StaggerIn(
                    delay: const Duration(milliseconds: 300),
                    child: Text(hint,
                        style: PhlioTypography.body
                            .copyWith(fontSize: 14, color: PhlioColors.textMuted)),
                  ),
                ],
              ],
            ),
          ),
        ),
        _footer(
          label: primary,
          onPressed: onPrimary ?? _next,
          loading: loading,
          secondary: secondary,
        ),
      ],
    );
  }

  Widget _page(_Step step, bool keyboard) {
    switch (step) {
      case _Step.intro:
        return Column(
          children: [
            const Spacer(),
            StaggerIn(
              delay: const Duration(milliseconds: 400),
              child: Text('PEOPLE. PLACES. POSSIBILITIES.',
                  style: PhlioTypography.tagline
                      .copyWith(fontSize: 10, color: PhlioColors.textMuted)),
            ),
            const SizedBox(height: 18),
            _footer(
              label: 'Get started',
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => _hop++);
                _go(1);
              },
              secondary: OnboardingLink(
                label: 'I already have an account',
                onTap: () => context.go('/login'),
              ),
            ),
          ],
        );
      case _Step.contact:
        return _usePhone ? _phonePage() : _emailPage();
      case _Step.email:
        return _formPage(
          hint: 'It won\'t appear on your profile.',
          children: [
            OnboardingField(
              controller: _email,
              label: 'Email address',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autofocus: true,
              error: _errors.containsKey(_Step.email),
              onChanged: (_) => setState(() => _errors.remove(_Step.email)),
              onSubmitted: (_) => _next(),
            ),
          ],
        );
      case _Step.password:
        return _formPage(
          hint: 'At least 8 characters. A mix of letters, numbers and '
              'symbols is hardest to guess.',
          children: [
            OnboardingField(
              controller: _password,
              focusNode: _passwordFocus,
              label: 'Password',
              obscureText: _obscure,
              autofocus: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              error: _errors.containsKey(_Step.password),
              onChanged: (_) => setState(() => _errors.remove(_Step.password)),
              onSubmitted: (_) => _next(),
              suffix: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 22,
                  color: PhlioColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _PasswordStrength(password: _password.text),
          ],
        );
      case _Step.birthday:
        return _birthdayPage();
      case _Step.name:
        return _formPage(
          hint: 'This is how you\'ll appear to friends across Phlio.',
          children: [
            OnboardingField(
              controller: _name,
              label: 'Full name',
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              error: _errors.containsKey(_Step.name),
              onChanged: (_) => setState(() => _errors.remove(_Step.name)),
              onSubmitted: (_) => _next(),
            ),
          ],
        );
      case _Step.username:
        return _usernamePage();
      case _Step.interests:
        return _interestsPage();
      case _Step.terms:
        return _termsPage();
      case _Step.photo:
        return _photoPage();
      case _Step.welcome:
        return Column(
          children: [
            const Spacer(),
            StaggerIn(
              delay: const Duration(milliseconds: 500),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Your feed, chats, plans and moments are ready. '
                  'I\'ll be around if you need a hand.',
                  textAlign: TextAlign.center,
                  style: PhlioTypography.body.copyWith(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _footer(label: 'Let\'s go', onPressed: _finish),
          ],
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Individual steps

  Widget _phonePage() {
    return _formPage(
      hint: 'No one else will see it on your profile.',
      secondary: OnboardingLink(
        label: 'Use email instead',
        onTap: () => setState(() {
          _usePhone = false;
          _errors.remove(_Step.contact);
        }),
      ),
      children: [
        OnboardingField(
          controller: _phone,
          label: 'Mobile number',
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          error: _errors.containsKey(_Step.contact),
          onChanged: (_) => setState(() => _errors.remove(_Step.contact)),
          onSubmitted: (_) => _next(),
          prefix: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => showCountryPicker(
              context: context,
              showPhoneCode: true,
              countryListTheme: CountryListThemeData(
                backgroundColor: PhlioColors.surface,
                textStyle: PhlioTypography.body
                    .copyWith(color: PhlioColors.textPrimary),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              onSelect: (country) => setState(() => _country = country),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_country.flagEmoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text('+${_country.phoneCode}',
                      style: PhlioTypography.bodyLarge
                          .copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Icon(Icons.expand_more_rounded,
                      size: 20, color: PhlioColors.textMuted),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 26, color: PhlioColors.border),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emailPage() {
    return _formPage(
      hint: 'No one else will see it on your profile.',
      secondary: OnboardingLink(
        label: 'Use mobile number instead',
        onTap: () => setState(() {
          _usePhone = true;
          _errors.remove(_Step.contact);
        }),
      ),
      children: [
        OnboardingField(
          controller: _email,
          label: 'Email address',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          error: _errors.containsKey(_Step.contact),
          onChanged: (_) => setState(() => _errors.remove(_Step.contact)),
          onSubmitted: (_) => _next(),
        ),
      ],
    );
  }

  Widget _birthdayPage() {
    final today = DateUtils.dateOnly(DateTime.now());
    final initial =
        _birthday ?? DateTime(today.year - 18, today.month, today.day);
    final birthday = _birthday;
    return _formPage(
      hint: 'Use your own birthday, even if this account is for a business '
          'or a pet. No one sees it unless you share it.',
      onPrimary: () {
        _birthday ??= initial;
        _next();
      },
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            birthday == null
                ? 'Scroll to your date of birth'
                : '${MaterialLocalizations.of(context).formatFullDate(birthday)}'
                    ' · ${_age(birthday)} years old',
            key: ValueKey(birthday),
            textAlign: TextAlign.center,
            style: PhlioTypography.bodyLarge.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: birthday == null
                    ? PhlioColors.textMuted
                    : PhlioColors.textPrimary),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 210,
          decoration: BoxDecoration(
            color: PhlioColors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _errors.containsKey(_Step.birthday)
                    ? PhlioColors.danger.withValues(alpha: 0.8)
                    : PhlioColors.border.withValues(alpha: 0.6)),
          ),
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.dark,
              textTheme: CupertinoTextThemeData(
                dateTimePickerTextStyle: TextStyle(
                  fontFamily: PhlioTypography.uiFamily,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: PhlioColors.textPrimary,
                ),
              ),
            ),
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: initial,
              minimumYear: 1900,
              maximumDate: today,
              onDateTimeChanged: (value) {
                final first = _birthday == null;
                setState(() {
                  _birthday = DateUtils.dateOnly(value);
                  _errors.remove(_Step.birthday);
                });
                if (first) setState(() => _nod++);
                HapticFeedback.selectionClick();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _usernamePage() {
    final value = _username.text.trim();
    final valid = _validate(_Step.username) == null;
    return _formPage(
      hint: 'You can change it any time.',
      children: [
        OnboardingField(
          controller: _username,
          label: 'Username',
          autofocus: true,
          autofillHints: const [AutofillHints.newUsername],
          error: _errors.containsKey(_Step.username),
          onChanged: (_) => setState(() => _errors.remove(_Step.username)),
          onSubmitted: (_) => _next(),
          suffix: value.isEmpty
              ? null
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    valid ? Icons.check_circle_rounded : Icons.cancel_outlined,
                    key: ValueKey(valid),
                    size: 22,
                    color: valid ? PhlioColors.success : PhlioColors.danger,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in _suggestions())
              _Pill(
                label: suggestion,
                selected: suggestion == value,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _username.text = suggestion;
                    _errors.remove(_Step.username);
                    _nod++;
                  });
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _interestsPage() {
    return _formPage(
      primary: _interests.isEmpty ? 'Skip for now' : 'Continue',
      hint: 'Phlio uses these to tune Explore, Book and Shop from day one.',
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (final interest in _availableInterests)
              _Pill(
                label: interest,
                big: true,
                selected: _interests.contains(interest),
                onTap: () {
                  HapticFeedback.selectionClick();
                  final adding = !_interests.contains(interest);
                  setState(() {
                    adding ? _interests.add(interest) : _interests.remove(interest);
                    if (adding && _interests.length == 1) {
                      _reaction = 'Ooh, nice. Pick as many as you like.';
                    }
                    if (_interests.isEmpty) _reaction = null;
                  });
                  if (adding) _flashAct(FoxyAct.love, duration: const Duration(milliseconds: 1100));
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _termsPage() {
    final strong =
        PhlioTypography.bodyStrong.copyWith(fontSize: 15.5, color: PhlioColors.textPrimary);
    final body = PhlioTypography.body.copyWith(fontSize: 15.5, height: 1.5);
    return _formPage(
      primary: 'I agree',
      loading: _submitting,
      onPrimary: _register,
      children: [
        Text.rich(
          TextSpan(style: body, children: [
            const TextSpan(text: 'By tapping '),
            TextSpan(text: 'I agree', style: strong),
            const TextSpan(text: ', you create a Phlio account and agree to Phlio\'s '),
            TextSpan(text: 'Terms', style: strong),
            const TextSpan(text: ', '),
            TextSpan(text: 'Privacy Policy', style: strong),
            const TextSpan(text: ' and '),
            TextSpan(text: 'Cookies Policy', style: strong),
            const TextSpan(text: '.'),
          ]),
        ),
        const SizedBox(height: 14),
        Text(
          'The Privacy Policy describes how we use what you share when you '
          'create an account — to keep Phlio safe, personalise your feed, '
          'and suggest people, places and plans you might like.',
          style: body,
        ),
      ],
    );
  }

  Widget _photoPage() {
    final path = ref.watch(avatarProvider).filePath;
    return _formPage(
      primary: path == null ? 'Add a photo' : 'Continue',
      onPrimary: path == null ? _pickPhoto : () => _go(_index + 1),
      secondary: path == null
          ? OnboardingLink(label: 'Skip for now', onTap: () => _go(_index + 1))
          : OnboardingLink(label: 'Change photo', onTap: _pickPhoto),
      children: [
        const SizedBox(height: 6),
        Center(
          child: GestureDetector(
            onTap: _pickPhoto,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 168,
              height: 168,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: path == null
                    ? null
                    : const SweepGradient(colors: [
                        PhlioColors.brandViolet,
                        PhlioColors.brandPink,
                        PhlioColors.brandPeach,
                        PhlioColors.brandViolet,
                      ]),
                border: path == null
                    ? Border.all(color: PhlioColors.border, width: 1.6)
                    : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: PhlioColors.backgroundDeep),
                child: ClipOval(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: path == null
                        ? Container(
                            key: const ValueKey('empty'),
                            color: PhlioColors.surface,
                            alignment: Alignment.center,
                            child: const Icon(Icons.add_a_photo_outlined,
                                size: 40, color: PhlioColors.textMuted),
                          )
                        : Image.file(File(path),
                            key: ValueKey(path),
                            fit: BoxFit.cover,
                            width: 160,
                            height: 160),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A rounded choice chip with the brand gradient outline when selected.
class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.big = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: selected ? PhlioColors.sunsetGradient : null,
            color: selected ? null : PhlioColors.border.withValues(alpha: 0.8),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
                horizontal: big ? 18 : 16, vertical: big ? 12 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? PhlioColors.surfaceElevated
                  : PhlioColors.backgroundDeep,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded,
                      size: 18, color: PhlioColors.brandPeach),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: PhlioTypography.label.copyWith(
                        fontSize: big ? 16 : 15,
                        color: selected
                            ? PhlioColors.textPrimary
                            : PhlioColors.textSecondary,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Four segments under the password field.
class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final score = _passwordScore(password);
    const labels = ['Too short', 'Okay', 'Good', 'Strong', 'Very strong'];
    final colors = [
      PhlioColors.danger,
      PhlioColors.warning,
      PhlioColors.brandPeach,
      PhlioColors.success,
      PhlioColors.success,
    ];
    if (password.isEmpty) return const SizedBox(height: 20);
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: i < score ? colors[score] : PhlioColors.surfaceElevated,
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 6),
        ],
        const SizedBox(width: 12),
        Text(labels[score],
            style: PhlioTypography.label
                .copyWith(fontSize: 14, color: colors[score], fontWeight: FontWeight.w700)),
      ],
    );
  }
}
