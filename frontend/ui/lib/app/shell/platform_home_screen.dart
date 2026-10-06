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

import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_button.dart';
import '../../design_system/widgets/phlio_fox.dart';
import '../../features/book/presentation/screens/book_screen.dart';
import '../../features/pay/presentation/screens/pay_screen.dart';
import '../../features/phlio_agent/presentation/screens/agent_screen.dart';
import '../../features/rooms/presentation/screens/rooms_screen.dart';
import '../../features/shop/presentation/screens/shop_screen.dart';
import '../../features/social/presentation/screens/social_home_screen.dart';
import '../platform/phlio_platform.dart';

class PlatformHomeScreen extends ConsumerWidget {
  const PlatformHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(currentPlatformProvider);

    // IndexedStack keeps every platform home alive (state + scroll) across
    // switches. Ordinal order matches the enum declaration order.
    return IndexedStack(
      index: platform.index,
      children: const [
        PayScreen(),
        SocialHomeScreen(),
        RoomsScreen(),
        BookScreen(),
        ShopScreen(),
        _ComingSoonHome(platform: PhlioPlatform.stream),
        _ComingSoonHome(platform: PhlioPlatform.news),
        AgentScreen(),
      ],
    );
  }
}

class _ComingSoonHome extends StatelessWidget {
  const _ComingSoonHome({required this.platform});

  final PhlioPlatform platform;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Phlio ${platform.label}', style: PhlioTypography.displayMedium)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(PhlioSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PhlioFox(size: 120, pose: PhlioFoxPose.sleepy),
              const SizedBox(height: PhlioSpacing.lg),
              Text('${platform.label} is on the roadmap', style: PhlioTypography.headline),
              const SizedBox(height: PhlioSpacing.xs),
              Text(
                platform == PhlioPlatform.stream
                    ? 'Watch, listen and enjoy — being built next.'
                    : 'Stay informed, stay aware — being built next.',
                textAlign: TextAlign.center,
                style: PhlioTypography.body,
              ),
              const SizedBox(height: PhlioSpacing.xl),
              PhlioPrimaryButton(
                label: 'Back to Social',
                size: PhlioButtonSize.medium,
                onPressed: () {
                  switchPlatform(context, PhlioPlatform.social);
                },
              ),
            ],
          ),
        ),
      ),
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
