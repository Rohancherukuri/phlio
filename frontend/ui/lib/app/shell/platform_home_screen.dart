import '../../shared/content/stream_screen.dart';
import 'package:phlio/shared/content/news_screen.dart';
import 'package:phlio/shared/content/content_surface.dart';
// The Home tab is platform-aware: whatever platform is selected in the
// App Tray, this screen shows that platform's home surface. All platform
// homes stay alive in an `IndexedStack` so switching platforms preserves
// scroll position and loaded state (a super-app that forgets your feed
// every time you peek at Pay feels broken).
//
// Per-platform mapping (all existing screens, so each platform keeps its
// full feature surface):
//   Pay -> wallet · Social -> the social surface (Posts/Videos tabs) ·
//   Rooms -> discovery · Book -> listings · Shop -> marketplace · Agent ->
//   Foxy chat · Stream/News -> honest "coming soon" platform page.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/book/presentation/screens/book_discovery_screen.dart';
import '../../features/pay/presentation/screens/pay_screen.dart';
import '../../features/phlio_agent/presentation/screens/agent_screen.dart';
import '../../features/rooms/presentation/screens/rooms_screen.dart';
import '../../features/shop/presentation/screens/shop_screen.dart';
import '../../features/social/presentation/screens/social_home_screen.dart';
import '../platform/phlio_platform.dart';

class PlatformHomeScreen extends ConsumerStatefulWidget {
  const PlatformHomeScreen({super.key});

  @override
  ConsumerState<PlatformHomeScreen> createState() => _PlatformHomeScreenState();
}

class _PlatformHomeScreenState extends ConsumerState<PlatformHomeScreen>
    with SingleTickerProviderStateMixin {
  final visited = <int>{};

  // Platform switch: the new home fades up into place (the tray card is
  // collapsing into the nav above it at the same time).
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(currentPlatformProvider);
    ref.listen(currentPlatformProvider, (previous, next) {
      if (previous == next) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enter.value = 1;
      } else {
        _enter.forward(from: 0);
      }
    });
    visited.add(platform.index);

    // IndexedStack keeps every platform home alive (state + scroll) across
    // switches. Ordinal order matches the enum declaration order.
    final stack = IndexedStack(
      index: platform.index,
      children: [
        for (final entry in const <Widget>[
          PayScreen(),
          SocialHomeScreen(),
          RoomsScreen(),
          BookDiscoveryScreen(),
          ShopScreen(),
          StreamScreen(),
          NewsScreen(),
          AgentScreen(),
        ].indexed)
          visited.contains(entry.$1)
              ? TickerMode(enabled: platform.index == entry.$1, child: entry.$2)
              : const SizedBox.shrink()
      ],
    );
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        // Same widget shape at rest (opacity 1, no offset) so the platform
        // homes are never re-parented and keep their state.
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: Transform.scale(scale: 0.985 + 0.015 * t, child: child),
          ),
        );
      },
      child: stack,
    );
  }
}

/// Convenience for call sites that switch platform (quick actions, activity
/// tiles, plan-card CTA, create sheet, tray). Navigation to `/home` is done
/// by the caller with go_router; this only flips the platform state.
void switchPlatform(BuildContext context, PhlioPlatform platform) {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(currentPlatformProvider.notifier).state = platform;
}
