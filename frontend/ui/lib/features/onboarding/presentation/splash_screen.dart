// Splash screen — mirrors the reference "1. LOADING — A warm start to
// bigger things." screen. Also doubles as the app's session bootstrap
// point: it watches `authControllerProvider` and the router's redirect
// logic (see `app/router/app_router.dart`) sends the user to `/home` or
// `/login` once that resolves, so this screen never navigates itself —
// it just renders while `AsyncValue.loading`.
//
// The entrance is a small choreographed sequence (mark scales/fades in
// first, then the tagline and progress bar fade in a beat later) rather
// than everything appearing at once — this is usually the very first
// thing a person sees, so it's worth the extra ~20 lines to make it feel
// considered rather than instantaneous.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/colors.dart';
import '../../../design_system/spacing.dart';
import '../../../design_system/typography.dart';
import '../../authentication/presentation/controllers/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markScale;
  late final Animation<double> _markOpacity;
  late final Animation<double> _detailsOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _markScale = Tween(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOutBack)));
    _markOpacity = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5, curve: Curves.easeOut));
    _detailsOpacity = CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0, curve: Curves.easeOut));
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
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _markOpacity,
                  child: ScaleTransition(
                    scale: _markScale,
                    child: ShaderMask(
                      shaderCallback: (bounds) => PhlioColors.brandGradient.createShader(bounds),
                      child: Text(
                        'P',
                        style: PhlioTypography.displayLarge.copyWith(fontSize: 96, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _markOpacity,
                  child: Text('Phlio', style: PhlioTypography.displayLarge),
                ),
                const SizedBox(height: PhlioSpacing.xs),
                FadeTransition(
                  opacity: _detailsOpacity,
                  child: Text(
                    'PEOPLE. PLACES. POSSIBILITIES.',
                    style: PhlioTypography.caption.copyWith(letterSpacing: 3),
                  ),
                ),
                const SizedBox(height: PhlioSpacing.massive),
                FadeTransition(
                  opacity: _detailsOpacity,
                  child: Text("Let's get you moving.", style: PhlioTypography.body),
                ),
                const SizedBox(height: PhlioSpacing.lg),
                FadeTransition(
                  opacity: _detailsOpacity,
                  child: SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor: PhlioColors.surfaceElevated,
                        valueColor: AlwaysStoppedAnimation(PhlioColors.brandPurple),
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
