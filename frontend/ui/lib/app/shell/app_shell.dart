import '../../features/profile/presentation/widgets/memories_screen.dart';
import '../../shared/content/stream_screen.dart';
import '../../shared/music/song_picker.dart';
import '../../shared/realtime/realtime_screen.dart';
import '../../shared/content/playlists_screen.dart';
import '../../features/shop/presentation/screens/cart_sheet.dart';
import '../../features/shop/presentation/controllers/cart_controller.dart';
import '../../features/social/presentation/widgets/video_publish_sheet.dart';
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
          onTrayTap: () => _showPlatformTray(context, ref),
        ),
      ),
    );
  }

  Future<void> _showPlatformTray(BuildContext context, WidgetRef ref) async {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final selected = await showGeneralDialog<PhlioPlatform>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close platform tray',
      barrierColor: Colors.black38,
      transitionDuration:
          reduced ? Duration.zero : const Duration(milliseconds: 280),
      pageBuilder: (popupContext, animation, secondaryAnimation) => SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 72),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: PhlioColors.surface,
                elevation: 12,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: PlatformTraySheet(
                    onSelected: (platform) =>
                        Navigator.of(popupContext).pop(platform),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final motion = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return FadeTransition(
            opacity: motion,
            child: ScaleTransition(
                alignment: Alignment.bottomRight,
                scale: Tween<double>(begin: .65, end: 1).animate(motion),
                child: child));
      },
    );
    if (selected == null || !context.mounted) return;
    ref.read(_trayPlatformSelectedProvider.notifier).state = true;
    ref.read(currentPlatformProvider.notifier).state = selected;
    context.go('/home');
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
            subtitle: '1–5 minutes',
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
            subtitle: 'Save a memory to your timeline',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const MemoriesScreen(kind: 'moment', openCamera: true)));
            },
          ),
          _CreateOption(
            icon: Icons.auto_stories_rounded,
            color: PhlioColors.domainArt,
            title: 'New experience',
            subtitle: 'Start a collaborative story',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const MemoriesScreen(kind: 'experience', openCamera: true)));
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
