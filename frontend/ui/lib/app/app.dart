// Root application widget: wires the theme and the router together. Kept
// deliberately thin — everything it needs (the router, the theme) is
// assembled elsewhere so this file reads as a one-glance summary of "what
// is the app."

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import '../features/social/presentation/widgets/social_video_player.dart';
import '../features/rooms/presentation/widgets/incoming_call_banner.dart';
import 'theme/app_theme.dart';

class PhlioApp extends ConsumerWidget {
  const PhlioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Phlio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      // The builder sits above the router's Navigator. Global controls need
      // their own Overlay ancestor for tooltips, independent of route overlays.
      builder: (context, child) => Overlay.wrap(
          child: Stack(
        children: [
          child!,
          const SocialVideoPlayer(),
          IncomingCallBanner(router: router),
        ],
      )),
    );
  }
}
