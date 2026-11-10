// Splash — Foxy, fully rigged, runs in from the left (run cycle: legs,
// arms, ears and tail all moving, dust puffs behind him), hops at centre
// stage and lands arms-up — "hey!" — as the P mark and "Phlio" wordmark
// rise beneath him; the tagline fades in at the bottom. The pose swap happens at the top of the hop, under a squash, so
// the run flows into the greeting without a visible cut.
//
// It also bootstraps the session: it watches `authControllerProvider`, and
// the router (app/router/app_router.dart) leaves this screen once the
// session check has resolved *and* [SplashScreen.ready] is true — a short
// minimum so the mark's entrance always finishes instead of flashing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/colors.dart';
import '../../../design_system/typography.dart';
import '../../../design_system/widgets/foxy_puppet.dart';
import '../../../design_system/widgets/foxy_rive.dart';
import '../../authentication/presentation/controllers/auth_controller.dart';
import 'widgets/onboarding_kit.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// Flips to true once the entrance has played (once per launch).
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Foxy's entrance: run in (0–0.95 s), hop (0.95 s), land arms-up.
  static const _runSecs = 0.95;

  // Logo block: P mark (64) + gap (12) + "Phlio" wordmark (30).
  static const double _markHeight = 106;
  static const double _foxSize = 210;

  /// Space between Foxy's foot and the top of the P.
  static const double _footGap = 1;
  static const _total = Duration(milliseconds: 2400);
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: _total)
        ..addListener(_onTick);
  FoxyAct _act = FoxyAct.run;
  int _hop = 0;
  bool _hopped = false, _greeted = false;

  double get _secs => _intro.value * _total.inMilliseconds / 1000;

  void _onTick() {
    if (!_hopped && _secs >= _runSecs) {
      setState(() {
        _hopped = true;
        _hop++;
      });
    }
    // Swap poses near the top of the hop, hidden by the squash.
    if (!_greeted && _secs >= _runSecs + 0.12) {
      setState(() {
        _greeted = true;
        _act = FoxyAct.hooray;
      });
    }
    if (_secs >= 2.1 && !SplashScreen.ready.value) {
      SplashScreen.ready.value = true;
    }
  }
  bool _warmed = false;

  @override
  void initState() {
    super.initState();
    // Start once both rigs are decoded so Foxy never pops in mid-run.
    Future.wait([FoxyRig.load('clap'), FoxyRig.load('hooray')])
        .timeout(const Duration(milliseconds: 1500), onTimeout: () => const <FoxyRig>[])
        .catchError((_) => const <FoxyRig>[])
        .whenComplete(() {
      if (mounted) _intro.forward();
    });
    if (!SplashScreen.ready.value) {
      // Safety net if the entrance can't play (e.g. assets missing).
      Future.delayed(const Duration(milliseconds: 4000), () {
        SplashScreen.ready.value = true;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_warmed) return;
    _warmed = true;
    // Warm Foxy's artwork so the log-in screen opens without a pop-in.
    FoxyRive.precache(context);
    FoxyRig.warmUp();
    precacheImage(
        const AssetImage('assets/images/logo/logo_wordmark.png'), context);
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    return Scaffold(
      body: OnboardingBackdrop(
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, _) {
            final secs = _secs;
            double span(double a, double b) =>
                ((secs - a) / (b - a)).clamp(0.0, 1.0);
            final mark = Curves.easeOutBack.transform(span(1.05, 1.7));
            final markFade = Curves.easeOut.transform(span(1.05, 1.45));
            final footer = Curves.easeOut.transform(span(1.3, 2.0));
            // Run-in: from off-screen left to centre stage, easing out.
            final width = MediaQuery.sizeOf(context).width;
            final run = Curves.easeOutQuad.transform(span(0, _runSecs));
            final foxX = (1 - run) * -(width / 2 + 140);
            final started = _intro.value > 0;
            return Stack(
              children: [
                // The logo sits at the exact centre of the screen…
                Center(child: _buildMark(mark, markFade)),
                // …and Foxy lands on top of it: his planted foot (x 112,
                // y 305.5 of the 320-unit rig canvas in the arms-up pose)
                // ends just above the top of the P.
                Center(
                  child: Transform.translate(
                    offset: Offset(
                      foxX + _foxSize / 2 - _foxSize * 112 / 320,
                      -(_markHeight / 2) -
                          (_foxSize * 305.5 / 320 - _foxSize / 2) -
                          _footGap,
                    ),
                    child: Opacity(
                      opacity: started ? 1 : 0,
                      child: FoxyPuppet(
                        act: _act,
                        size: _foxSize,
                        hopSignal: _hop,
                        entrance: false,
                        poseBlend: Duration.zero,
                        poofOnSwap: true,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 28),
                    child: Opacity(
                      opacity: footer,
                      child: Transform.translate(
                        offset: Offset(0, (1 - footer) * 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('PEOPLE. PLACES. POSSIBILITIES.',
                                style: PhlioTypography.caption.copyWith(
                                    color: PhlioColors.textMuted,
                                    letterSpacing: 2.6,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The P mark and the "Phlio" wordmark, rising in under Foxy as he lands.
  Widget _buildMark(double mark, double markFade) {
    return Opacity(
      opacity: markFade,
      child: Transform.translate(
        offset: Offset(0, (1 - mark.clamp(0.0, 1.0)) * 10),
        child: Transform.scale(
          scale: 0.9 + 0.1 * mark,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo/logo_mark.png',
                height: 64,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Image.asset(
                'assets/images/logo/logo_wordmark.png',
                height: 30,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Text('Phlio',
                    style: PhlioTypography.headline
                        .copyWith(fontWeight: FontWeight.w400)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
