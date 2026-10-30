// Splash — Instagram's launch screen, in Phlio's palette: the logo mark
// alone in the middle, lit by a slow rim-light glow, and a quiet
// "from Phlio" signature at the bottom.
//
// It also bootstraps the session: it watches `authControllerProvider`, and
// the router (app/router/app_router.dart) leaves this screen once the
// session check has resolved *and* [SplashScreen.ready] is true — a short
// minimum so the mark's entrance always finishes instead of flashing.

import 'dart:math' as math;

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
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..forward();
  late final AnimationController _glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();
  bool _warmed = false;

  @override
  void initState() {
    super.initState();
    if (!SplashScreen.ready.value) {
      Future.delayed(const Duration(milliseconds: 1500), () {
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
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    return Scaffold(
      body: OnboardingBackdrop(
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _glow]),
          builder: (context, _) {
            final mark = Curves.easeOutBack
                .transform(const Interval(0, 0.6).transform(_intro.value));
            final markFade = Curves.easeOut
                .transform(const Interval(0, 0.4).transform(_intro.value));
            final footer = Curves.easeOut
                .transform(const Interval(0.45, 1).transform(_intro.value));
            // The rim light sweeps round the mark like the moments ring.
            final sweep = _glow.value * 2 * math.pi;
            final pulse = 0.5 + 0.5 * math.sin(sweep);
            return Stack(
              children: [
                Center(
                  child: Opacity(
                    opacity: markFade,
                    child: Transform.scale(
                      scale: 0.86 + 0.14 * mark,
                      child: SizedBox(
                        width: 180,
                        height: 180,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Soft halo.
                            Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [
                                  PhlioColors.brandViolet
                                      .withValues(alpha: 0.18 + 0.08 * pulse),
                                  PhlioColors.brandPeach
                                      .withValues(alpha: 0.05),
                                  Colors.transparent,
                                ], stops: const [0, 0.55, 1]),
                              ),
                            ),
                            Transform.rotate(
                              angle: sweep,
                              child: Container(
                                width: 132,
                                height: 132,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(colors: [
                                    Colors.transparent,
                                    PhlioColors.brandPeach
                                        .withValues(alpha: 0.10 * markFade),
                                    PhlioColors.brandViolet
                                        .withValues(alpha: 0.16 * markFade),
                                    Colors.transparent,
                                  ], stops: const [0, 0.35, 0.6, 1]),
                                ),
                              ),
                            ),
                            Image.asset(
                              'assets/images/logo/logo_mark.png',
                              height: 92,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ],
                        ),
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
                            Text('from',
                                style: PhlioTypography.caption.copyWith(
                                    color: PhlioColors.textMuted,
                                    letterSpacing: 0.4)),
                            const SizedBox(height: 6),
                            Image.asset(
                              'assets/images/logo/logo_wordmark.png',
                              height: 22,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
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
}
