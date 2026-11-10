import '../../features/profile/presentation/widgets/memories_screen.dart';
import '../../features/profile/presentation/widgets/experience_screen.dart';
import '../../shared/content/stream_screen.dart';
import '../../shared/music/song_picker.dart';
import '../../shared/realtime/realtime_screen.dart';
import '../../shared/content/playlists_screen.dart';
import '../../features/shop/presentation/screens/cart_sheet.dart';
import '../../features/shop/presentation/controllers/cart_controller.dart';
import '../../features/social/presentation/widgets/video_publish_sheet.dart';
import '../../features/social/presentation/widgets/moment_composer.dart';
// The persistent app chrome: platform-aware bottom navigation wrapping the
// three shell tabs — Home (current platform's home), Explore (current
// platform's discovery), and Profile (shared across all platforms). The
// center gradient button opens a create sheet whose options depend on the
// current platform (Social: post/video/clip/moment/experience/snap);
// the trailing Tray slot opens the platform switcher sheet.
//
// Social, Rooms, Shop, Book, Pay, Stream, News and Agent are *platforms*
// selected via the tray, not tabs — see `app/platform/phlio_platform.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_bottom_nav.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';
import '../../features/rooms/presentation/widgets/create_room_sheet.dart';
import '../../features/social/presentation/widgets/social_feed_view.dart'
    show showPostComposer;
import '../platform/phlio_platform.dart';
import '../../features/phlio_agent/presentation/widgets/agent_quick_actions.dart';
import 'platform_home_screen.dart' show switchPlatform;
import 'platform_tray_sheet.dart';
import '../../features/social/presentation/controllers/video_playback_controller.dart';

final _trayPlatformSelectedProvider = StateProvider<bool>((ref) => false);

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(currentPlatformProvider);
    final onPay = platform == PhlioPlatform.pay;
    final onShop = platform == PhlioPlatform.shop;
    final onPlaylist =
        platform == PhlioPlatform.news || platform == PhlioPlatform.stream;
    final user = ref.watch(authControllerProvider).valueOrNull;

    final mode = ref.watch(videoPlaybackProvider.select((value) => value.mode));
    final expanded = mode == SocialPlayerMode.expanded ||
        mode == SocialPlayerMode.fullscreen;
    return PopScope(
      canPop: !expanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && expanded)
          ref.read(videoPlaybackProvider).setMode(SocialPlayerMode.floating);
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: PhlioBottomNav(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          // Phlio Pay: the center button becomes Scan & Pay, like the
          // reference payments apps. Everywhere else: the create sheet.
          createIcon: onShop
              ? Icons.shopping_bag_outlined
              : onPay
                  ? Icons.qr_code_scanner_rounded
                  : Icons.add_rounded,
          createLabel: onShop
              ? 'Cart'
              : onPay
                  ? 'Scan and pay'
                  : onPlaylist
                      ? 'Create playlist'
                      : platform == PhlioPlatform.agent
                          ? 'Foxy actions'
                          : 'Create',
          createCount: onShop
              ? (ref.watch(cartProvider).valueOrNull?['count'] as int? ?? 0)
              : 0,
          profileAvatar:
              user == null ? null : MeAvatar(name: user.fullName, size: 22),
          onCreateTap: onShop
              ? () => showShopCart(context)
              : onPay
                  ? () => context.push('/qr-scanner')
                  : platform == PhlioPlatform.rooms
                      ? () => showCreateRoomSheet(context)
                      // Agent: the Foxy wheel — Lens, Voice, Photos, New chat.
                      : platform == PhlioPlatform.agent
                          ? () => showAgentWheel(context)
                      : onPlaylist
                          ? () => showPlaylists(
                              context,
                              platform == PhlioPlatform.news
                                  ? 'news'
                                  : 'stream',
                              mediaMode: platform == PhlioPlatform.stream
                                  ? (ref.read(streamAudioModeProvider)
                                      ? 'audio'
                                      : 'video')
                                  : null)
                          : () => _showCreateSheet(context, ref),
          trayIcon: ref.watch(_trayPlatformSelectedProvider)
              ? platform.activeIcon
              : Icons.apps_rounded,
          trayLabel: ref.watch(_trayPlatformSelectedProvider)
              ? platform.label.replaceFirst('Phlio ', '')
              : 'Tray',
          trayColor: ref.watch(_trayPlatformSelectedProvider)
              ? platform.color
              : PhlioColors.textMuted,
          trayOpen: ref.watch(platformTrayOpenProvider),
          onTrayTap: () => _showPlatformTray(context, ref),
        ),
      ),
    );
  }

  Future<void> _showPlatformTray(BuildContext context, WidgetRef ref) {
    // The animated tray (platform_tray_sheet.dart): the card grows out of the
    // nav, and on a pick the new platform's home fades in while the card
    // sinks back into the tray button.
    return showPlatformSwitcher(context, onSelected: (selected) {
      ref.read(_trayPlatformSelectedProvider.notifier).state = true;
      ref.read(currentPlatformProvider.notifier).state = selected;
      context.go('/home');
    });
  }

  void _showCreateSheet(BuildContext context, WidgetRef ref) {
    final platform = ref.read(currentPlatformProvider);
    final options = _createOptions(context, ref, platform);

    // isScrollControlled + SingleChildScrollView: the Social sheet carries
    // six options, which can exceed the default sheet cap at larger font
    // scales — it scrolls instead of overflowing.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Create', style: PhlioTypography.headline),
                ),
              ),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Text(
                    'Nothing to create on ${platform.label} yet.',
                    style: PhlioTypography.body,
                  ),
                )
              else
                for (final option in options) _createTile(sheetContext, option),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Create options per platform — Social gets the full content-creation
  /// set (post, video, clip, moment, experience, snap); the other live
  /// platforms get their own domain action.
  List<_CreateOption> _createOptions(
    BuildContext context,
    WidgetRef ref,
    PhlioPlatform platform,
  ) {
    // Actions that don't have a domain behind them yet are honest
    // "coming soon" snackbars — the entry points exist, the features land
    // with their platforms (Stream for video/clip, Moments/Experiences
    // domains for memories and stories).
    VoidCallback comingSoon(String what) {
      return () {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$what — coming soon.')),
        );
      };
    }

    VoidCallback switchAndGo(PhlioPlatform target) {
      return () {
        Navigator.of(context).pop();
        switchPlatform(context, target);
        context.go('/home');
      };
    }

    switch (platform) {
      case PhlioPlatform.social:
        return [
          _CreateOption(
            icon: Icons.edit_rounded,
            color: PhlioColors.domainSocial,
            title: 'New post',
            subtitle: 'Share a moment with your people',
            onTap: () {
              Navigator.of(context).pop();
              showPostComposer(context, ref);
            },
          ),
          _CreateOption(
            icon: Icons.videocam_rounded,
            color: PhlioColors.domainStream,
            title: 'New video',
            subtitle: '1–7 minutes',
            onTap: () {
              Navigator.of(context).pop();
              showVideoPublisher(context, kind: 'video');
            },
          ),
          _CreateOption(
            icon: Icons.content_cut_rounded,
            color: PhlioColors.brandOrange,
            title: 'New clip',
            subtitle: '15 seconds–2 minutes',
            onTap: () {
              Navigator.of(context).pop();
              showVideoPublisher(context, kind: 'clip');
            },
          ),
          _CreateOption(
              icon: Icons.sensors_rounded,
              color: PhlioColors.brandPurple,
              title: 'Go live',
              subtitle: 'Broadcast to your Social audience',
              onTap: () {
                Navigator.of(context).pop();
                openRealtime(context,
                    endpoint: '/realtime/live',
                    title:
                        'Live with ${ref.read(authControllerProvider).valueOrNull?.fullName ?? 'me'}');
              }),
          _CreateOption(
            icon: Icons.photo_library_rounded,
            color: PhlioColors.domainNews,
            title: 'New moment',
            subtitle: 'Share a photo or video for 24 hours',
            onTap: () {
              final navigator = Navigator.of(context, rootNavigator: true);
              Navigator.pop(context);
              navigator.push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const MomentComposerScreen()));
            },
          ),
          _CreateOption(
            icon: Icons.auto_stories_rounded,
            color: PhlioColors.domainArt,
            title: 'New experience',
            subtitle: 'Weekly photo dumps with your best friends',
            onTap: () {
              final navigator = Navigator.of(context, rootNavigator: true);
              Navigator.pop(context);
              openExperience(navigator.context);
            },
          ),
          _CreateOption(
            icon: Icons.photo_camera_rounded,
            color: PhlioColors.domainPay,
            title: 'New snap',
            subtitle: 'Capture and share instantly',
            onTap: () {
              final navigator = Navigator.of(context, rootNavigator: true);
              Navigator.of(context).pop();
              navigator.push(
                  MaterialPageRoute(builder: (_) => const MemoriesScreen()));
            },
          ),
        ];
      case PhlioPlatform.rooms:
        return [
          _CreateOption(
            icon: Icons.forum_rounded,
            color: PhlioColors.domainRooms,
            title: 'New room',
            subtitle: 'Start a community conversation',
            onTap: () => switchAndGo(PhlioPlatform.rooms)(),
          ),
        ];
      case PhlioPlatform.book:
        return [
          _CreateOption(
            icon: Icons.local_activity_rounded,
            color: PhlioColors.domainBook,
            title: 'Plan something',
            subtitle: 'Book an experience with friends',
            onTap: () => switchAndGo(PhlioPlatform.book)(),
          ),
        ];
      case PhlioPlatform.agent:
        return [
          _CreateOption(
            icon: Icons.auto_awesome_rounded,
            color: PhlioColors.brandOrange,
            title: 'Ask Foxy',
            subtitle: 'Let the Agent plan it for you',
            onTap: () => switchAndGo(PhlioPlatform.agent)(),
          ),
        ];
      case PhlioPlatform.pay:
      case PhlioPlatform.shop:
      case PhlioPlatform.stream:
      case PhlioPlatform.news:
        return const [];
    }
  }

  Widget _createTile(BuildContext context, _CreateOption option) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: option.color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(option.icon, color: option.color, size: 22),
      ),
      title: Text(option.title, style: PhlioTypography.bodyStrong),
      subtitle: Text(option.subtitle, style: PhlioTypography.caption),
      onTap: option.onTap,
    );
  }
}

class _CreateOption {
  const _CreateOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}
