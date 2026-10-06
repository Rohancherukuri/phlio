// Splash screen — mirrors the reference "1. LOADING — A warm start to
// bigger things." screen. Also doubles as the app's session bootstrap
// point: it watches `authControllerProvider` and the router's redirect
// logic (see `app/router/app_router.dart`) sends the user to `/home` or
// `/login` once that resolves, so this screen never navigates itself —
// it just renders while `AsyncValue.loading`.
//
// The entrance is a small choreographed sequence (logo mark rises in
// first, then the wordmark/tagline, then Foxy and the progress bar fade
// in a beat later) rather than everything appearing at once — this is
// usually the very first thing a person sees, so it's worth the extra
// lines to make it feel considered rather than instantaneous.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/colors.dart';
import '../../../design_system/spacing.dart';
import '../../../design_system/typography.dart';
import '../../../design_system/widgets/phlio_fox.dart';
import '../../authentication/presentation/controllers/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markScale;
  late final Animation<double> _markOpacity;
  late final Animation<double> _detailsOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _markScale = Tween(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.55, curve: Curves.easeOutBack)),
    );
    _markOpacity = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.45, curve: Curves.easeOut));
    _detailsOpacity = CurvedAnimation(parent: _controller, curve: const Interval(0.45, 0.85, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reading (not watching-and-ignoring) is enough to kick off `build()`
    // on the notifier if it hasn't run yet; the router itself watches this
    // provider to decide where to redirect once it settles.
    ref.watch(authControllerProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 1.1,
            colors: [Color(0xFF1A1426), PhlioColors.background],
            stops: [0.0, 0.7],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo mark — the gradient "P" from the brand sheet.
                  FadeTransition(
                    opacity: _markOpacity,
                    child: ScaleTransition(
                      scale: _markScale,
                      child: SizedBox(
                        height: 118,
                        child: Image.asset(
                          'assets/images/logo/logo_mark.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: PhlioSpacing.lg),
                  // Wordmark + tagline.
                  FadeTransition(
                    opacity: _detailsOpacity,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 42,
                          child: Image.asset(
                            'assets/images/logo/logo_wordmark.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: PhlioSpacing.sm),
                        Text(
                          'PEOPLE. PLACES. POSSIBILITIES.',
                          style: PhlioTypography.tagline,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PhlioSpacing.massive),
                  // Foxy waves hello while the app warms up.
                  FadeTransition(
                    opacity: _detailsOpacity,
                    child: Column(
                      children: [
                        const PhlioFoxAnimation(
                          size: 132,
                          animation: PhlioFoxLoop.wave,
                        ),
                        const SizedBox(height: PhlioSpacing.lg),
                        Text("Let's get you moving.", style: PhlioTypography.body),
                      ],
                    ),
                  ),
                  const SizedBox(height: PhlioSpacing.lg),
                  FadeTransition(
                    opacity: _detailsOpacity,
                    child: SizedBox(
                      width: 132,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: PhlioColors.surfaceElevated,
                          valueColor: AlwaysStoppedAnimation(PhlioColors.brandOrange),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
