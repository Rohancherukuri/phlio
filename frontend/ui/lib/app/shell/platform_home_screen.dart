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

import '../../features/book/presentation/screens/book_screen.dart';
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

class _PlatformHomeScreenState extends ConsumerState<PlatformHomeScreen> {
  final visited = <int>{};
  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(currentPlatformProvider);
    visited.add(platform.index);

    // IndexedStack keeps every platform home alive (state + scroll) across
    // switches. Ordinal order matches the enum declaration order.
    return IndexedStack(
      index: platform.index,
      children: [
        for (final entry in const <Widget>[
          PayScreen(),
          SocialHomeScreen(),
          RoomsScreen(),
          BookScreen(),
          ShopScreen(),
          PlatformCatalogScreen(platform: 'stream'),
          NewsScreen(),
          AgentScreen(),
        ].indexed)
          visited.contains(entry.$1) ? entry.$2 : const SizedBox.shrink()
      ],
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
