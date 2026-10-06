// Profile — the user's own page, an Instagram/Discord hybrid in Phlio's
// language:
//
//   avatar (tap: camera/gallery → crop → filter) · name & handle · bio ·
//   interest tags · posts/followers/following · profile song (1-minute
//   ambient loop, play/pause) · dashboard button · Edit/Share actions ·
//   Moments (highlights) row · content tabs:
//   Posts (Articles/Videos/Pics) · Replies · Reposts · Schedule · Chat ·
//   Clips
//
// Uploads beyond posts (videos, clips, articles, schedules) are honest
// empty states — those domains land with Stream/Moments/Experiences.
// Logout lives in the dashboard overflow for this stage.

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/colors.dart';
import '../../../design_system/radii.dart';
import '../../../design_system/spacing.dart';
import '../../../design_system/typography.dart';
import '../../../design_system/widgets/phlio_card.dart';
import '../../../design_system/widgets/phlio_fox.dart';
import '../../../features/rooms/presentation/controllers/messaging_controller.dart';
import '../../../features/social/presentation/controllers/feed_controller.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: _tabs.length, vsync: this);

  static const _tabs = ['Posts', 'Replies', 'Reposts', 'Schedule', 'Chat', 'Clips'];

  // Profile song playback (a bundled ambient loop, or the user's song).
  final AudioPlayer _songPlayer = AudioPlayer();
  StreamSubscription<Duration>? _songPositionSub;
  bool _songPlaying = false;

  // Posts sub-tab (X-style dropdown): Articles / Videos / Pics.
  String _postsSubTab = 'Articles';

  @override
  void dispose() {
    _songPositionSub?.cancel();
    _tabController.dispose();
    _songPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleSong() async {
    if (_songPlaying) {
      await _songPlayer.stop();
      if (mounted) setState(() => _songPlaying = false);
      return;
    }
    try {
      final song = ref.read(avatarProvider);
      final customPath = song.songPath;
      if (customPath != null) {
        await _songPlayer.play(DeviceFileSource(customPath));
        // Loop inside the selected section, Instagram-style.
        final start = song.songStart;
        final end = song.songEnd > start ? song.songEnd : start + 60;
        if (start > 0) await _songPlayer.seek(Duration(milliseconds: (start * 1000).round()));
        _songPositionSub?.cancel();
        _songPositionSub = _songPlayer.onPositionChanged.listen((position) {
          final pos = position.inMilliseconds / 1000;
          if (pos >= end) {
            _songPlayer.seek(Duration(milliseconds: (start * 1000).round()));
          }
        });
      } else {
        await _songPlayer.play(AssetSource('audio/profile_song.wav'));
      }
      await _songPlayer.setReleaseMode(ReleaseMode.loop);
      if (mounted) setState(() => _songPlaying = true);
      _songPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _songPlaying = false);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play the profile song.')),
      );
    }
  }

  Future<void> _openAvatarEditor() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: PhlioColors.brandOrange),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: PhlioColors.brandViolet),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
            ),
            if (ref.read(avatarProvider).hasAvatar)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: PhlioColors.danger),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == 'remove') {
      await ref.read(avatarProvider.notifier).clear();
      return;
    }

    try {
      final staged = await ref
          .read(avatarProvider.notifier)
          .pickAndCrop(camera: source == 'camera');
      if (staged == null || !mounted) return;
      ref.read(avatarProvider.notifier).stage(staged);
      await _openFilterPicker();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openFilterPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final avatar = ref.watch(avatarProvider);
          if (!avatar.hasAvatar) return const SizedBox.shrink();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                  child: Text('Pick a filter', style: PhlioTypography.headline),
                ),
                SizedBox(
                  height: 150,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
                    children: [
                      for (var i = 0; i < kAvatarFilters.length; i++)
                        GestureDetector(
                          onTap: () =>
                              ref.read(avatarProvider.notifier).setFilter(i),
                          child: Padding(
                            padding: const EdgeInsets.only(right: PhlioSpacing.md),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2.5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: avatar.filterIndex == i
                                          ? PhlioColors.brandOrange
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: ColorFiltered(
                                      colorFilter: kAvatarFilters[i].matrix,
                                      child: Image.file(
                                        File(avatar.filePath!),
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: PhlioSpacing.xs),
                                Text(kAvatarFilters[i].name,
                                    style: PhlioTypography.caption),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String get _songTitle {
    final custom = ref.read(avatarProvider).songPath;
    if (custom == null) return 'Ambient Sketch — Phlio Original';
    return custom.split('/').last;
  }

  String get _songSubtitle {
    final song = ref.read(avatarProvider);
    if (song.songPath == null) return 'My song · 0:16 · loops';
    final length = song.songEnd > song.songStart
        ? (song.songEnd - song.songStart).round()
        : 60;
    return 'My song · from device · $length s selected';
  }

  Future<void> _openSongPicker() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.library_music_rounded,
                  color: PhlioColors.brandOrange),
              title: const Text('Choose from device'),
              subtitle: const Text('Pick an audio file'),
              onTap: () => Navigator.of(sheetContext).pop('device'),
            ),
            ListTile(
              leading: const Icon(Icons.album_rounded, color: PhlioColors.brandViolet),
              title: const Text('Spotify'),
              subtitle: const Text('Connect your account'),
              onTap: () => Navigator.of(sheetContext).pop('spotify'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == 'spotify') {
      _comingSoon(context, 'Spotify (licensed partner API)');
      return;
    }

    try {
      final path = await ref.read(avatarProvider.notifier).pickSong();
      if (path == null || !mounted) return;
      // If the previous song is playing, switch playback off for the trim.
      if (_songPlaying) {
        await _songPlayer.stop();
        setState(() => _songPlaying = false);
      }

      // Probe the file's duration for the trim sheet.
      final probe = AudioPlayer();
      final durationFuture = probe.onDurationChanged.first;
      await probe.setSource(DeviceFileSource(path));
      final duration = await durationFuture.timeout(
        const Duration(seconds: 3),
        onTimeout: () => const Duration(seconds: 30),
      );
      await probe.stop();
      probe.dispose();

      if (!mounted) return;
      final section = await showModalBottomSheet<(double, double)>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _SongTrimSheet(filePath: path, duration: duration),
      );
      if (section == null || !mounted) {
        setState(() {}); // refresh title even if cancelled
        return;
      }
      await ref.read(avatarProvider.notifier).setSongSection(section.$1, section.$2);
      setState(() {}); // refresh title/subtitle
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile song updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what — coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final feedAsync = ref.watch(feedControllerProvider);
    final myPosts = (feedAsync.valueOrNull?.posts ?? [])
        .where((post) => post.authorId == user.id)
        .toList();
    final dmConversations =
        (ref.watch(dmConversationsProvider).valueOrNull ?? []).map((c) => (c['peer'] as Map)['id'] as String).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('@${user.username}', style: PhlioTypography.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.lg, PhlioSpacing.xxl,
        ),
        children: [
          // -- Identity row: avatar + stats --------------------------------
          Row(
            children: [
              GestureDetector(
                onTap: _openAvatarEditor,
                child: Stack(
                  children: [
                    MeAvatar(name: user.fullName, size: 88),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          gradient: PhlioColors.sunsetGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_camera_rounded,
                            size: 15, color: PhlioColors.textOnBrand),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PhlioSpacing.xl),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _stat('${myPosts.length}', 'posts'),
                    _stat('252', 'followers'),
                    _stat('280', 'following'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: PhlioSpacing.lg),

          // -- Name, bio, interests ------------------------------------------
          Row(
            children: [
              Flexible(
                child: Text(user.fullName,
                    style: PhlioTypography.headline, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.verified_rounded,
                  size: 16, color: PhlioColors.brandViolet),
            ],
          ),
          const SizedBox(height: PhlioSpacing.xs),
          Text(
            user.bio.isEmpty ? 'No bio yet — tap edit to add one.' : user.bio,
            style: PhlioTypography.body,
          ),
          if (user.interests.isNotEmpty) ...[
            const SizedBox(height: PhlioSpacing.sm),
            Wrap(
              spacing: PhlioSpacing.xs,
              runSpacing: PhlioSpacing.xs,
              children: [
                for (final interest in user.interests)
                  Chip(
                    label: Text('#$interest', style: PhlioTypography.caption),
                    backgroundColor: PhlioColors.surfaceElevated,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          const SizedBox(height: PhlioSpacing.lg),

          // -- Profile song ----------------------------------------------------
          PhlioCard(
            padding:
                const EdgeInsets.symmetric(horizontal: PhlioSpacing.md, vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleSong,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      gradient: PhlioColors.sunsetGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _songPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20,
                      color: PhlioColors.textOnBrand,
                    ),
                  ),
                ),
                const SizedBox(width: PhlioSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_songTitle, style: PhlioTypography.bodyStrong),
                      Text(
                        _songSubtitle,
                        style: PhlioTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Song source picker: local files, or Spotify later.
                IconButton(
                  icon: const Icon(Icons.library_music_rounded,
                      color: PhlioColors.brandOrange, size: 20),
                  tooltip: 'Change song',
                  onPressed: _openSongPicker,
                ),
              ],
            ),
          ),
          const SizedBox(height: PhlioSpacing.md),

          // -- Dashboard button --------------------------------------------------
          GestureDetector(
            onTap: () => context.push('/profile-dashboard', extra: myPosts.length),
            child: Container(
              padding: const EdgeInsets.all(PhlioSpacing.lg),
              decoration: BoxDecoration(
                color: PhlioColors.surfaceElevated,
                borderRadius: PhlioRadii.xlRadius,
                border: Border.all(color: PhlioColors.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights_rounded, color: PhlioColors.brandOrange),
                  const SizedBox(width: PhlioSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your dashboard', style: PhlioTypography.bodyStrong),
                        Text(
                          'Views, likes and how your content is doing.',
                          style: PhlioTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: PhlioSpacing.md),

          // -- Edit / Share ------------------------------------------------------
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _comingSoon(context, 'Edit profile'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: PhlioColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: PhlioRadii.mdRadius),
                  ),
                  child: Text('Edit profile', style: PhlioTypography.bodyStrong),
                ),
              ),
              const SizedBox(width: PhlioSpacing.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _comingSoon(context, 'Share profile'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: PhlioColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: PhlioRadii.mdRadius),
                  ),
                  child: Text('Share profile', style: PhlioTypography.bodyStrong),
                ),
              ),
            ],
          ),
          const SizedBox(height: PhlioSpacing.xl),

          // -- Moments (highlights) ------------------------------------------------
          Text('Moments', style: PhlioTypography.headline),
          const SizedBox(height: PhlioSpacing.md),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _momentNew(() => _comingSoon(context, 'New moments')),
                for (final moment in _seedMoments)
                  GestureDetector(
                    onTap: () => _comingSoon(context, 'Moment: ${moment.$1}'),
                    child: Padding(
                      padding: const EdgeInsets.only(right: PhlioSpacing.md),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: const BoxDecoration(
                              gradient: PhlioColors.sunsetGradient,
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                moment.$2,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                              ),
                            ),
                          ),
                          const SizedBox(height: PhlioSpacing.xs),
                          Text(moment.$1, style: PhlioTypography.caption),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: PhlioSpacing.lg),

          // -- Content tabs ----------------------------------------------------------
          _tabRow(),
          SizedBox(
            height: 420,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Posts with the X-style dropdown: "Posts + arrow" opens
                // Articles / Videos / Pics; the selected one fills the tab.
                Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PopupMenuButton<String>(
                        initialValue: _postsSubTab,
                        color: PhlioColors.surfaceElevated,
                        shape: RoundedRectangleBorder(borderRadius: PhlioRadii.lgRadius),
                        onSelected: (value) => setState(() => _postsSubTab = value),
                        itemBuilder: (context) => [
                          for (final option in const ['Articles', 'Videos', 'Pics'])
                            PopupMenuItem(
                              value: option,
                              child: Row(
                                children: [
                                  Icon(
                                    switch (option) {
                                      'Articles' => Icons.article_outlined,
                                      'Videos' => Icons.videocam_outlined,
                                      _ => Icons.photo_outlined,
                                    },
                                    size: 18,
                                    color: PhlioColors.textSecondary,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(option, style: PhlioTypography.bodyStrong),
                                  const Spacer(),
                                  if (option == _postsSubTab)
                                    const Icon(Icons.check_rounded,
                                        size: 18, color: PhlioColors.brandOrange),
                                ],
                              ),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: PhlioSpacing.xs, vertical: PhlioSpacing.sm,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Posts', style: PhlioTypography.headline),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: PhlioColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 330,
                      child: switch (_postsSubTab) {
                        'Videos' => _emptyContent(
                            icon: Icons.videocam_outlined,
                            message: 'No videos yet',
                            hint: 'Video uploads arrive with Phlio Stream.',
                          ),
                        'Pics' => myPosts.isEmpty
                            ? _emptyContent(
                                icon: Icons.photo_outlined,
                                message: 'No pictures yet',
                                hint: 'Post from the Home composer - your pics land here.',
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.only(top: PhlioSpacing.md),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 2,
                                  crossAxisSpacing: 2,
                                ),
                                itemCount: myPosts.length,
                                itemBuilder: (context, index) => Container(
                                  color: PhlioColors.surfaceElevated,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    myPosts[index].text,
                                    style: PhlioTypography.caption,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                        _ => _emptyContent(
                            icon: Icons.article_outlined,
                            message: 'No articles yet',
                            hint: 'Long-form writing arrives with Phlio News.',
                          ),
                      },
                    ),
                  ],
                ),
                _emptyContent(
                  icon: Icons.reply_outlined,
                  message: 'No replies yet',
                  hint: 'Replies you post in feeds will appear here.',
                ),
                _emptyContent(
                  icon: Icons.repeat_rounded,
                  message: 'No reposts yet',
                  hint: 'Repost something you love and it lands here.',
                ),
                _emptyContent(
                  icon: Icons.schedule_rounded,
                  message: 'Nothing scheduled',
                  hint: 'Scheduling arrives with Phlio Stream.',
                ),
                // Chat: real DM conversations from this session.
                dmConversations.isEmpty
                    ? _emptyContent(
                        icon: Icons.chat_bubble_outline_rounded,
                        message: 'No conversations yet',
                        hint: 'Tap a member in a room to start chatting.',
                      )
                    : ListView(
                        padding: const EdgeInsets.only(top: PhlioSpacing.md),
                        children: [
                          for (final username in dmConversations)
                            ListTile(
                              leading: PhlioAvatar(name: username, size: 42),
                              title: Text(username, style: PhlioTypography.bodyStrong),
                              subtitle: Text('Direct message',
                                  style: PhlioTypography.caption, maxLines: 1),
                              onTap: () => context.push('/dm/$username'),
                            ),
                        ],
                      ),
                _emptyContent(
                  icon: Icons.content_cut_rounded,
                  message: 'No clips yet',
                  hint: 'Clips you upload arrive with Phlio Stream.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const List<(String, String)> _seedMoments = [
    ('cafe', 'assets/images/placeholders/shop/product_ceramics.png'),
    ('dusk', 'assets/images/placeholders/social/thumb_travel_1.png'),
    ('gym', 'assets/images/placeholders/social/thumb_fitness_1.png'),
  ];

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value, style: PhlioTypography.headline),
        Text(label, style: PhlioTypography.caption),
      ],
    );
  }

  Widget _momentNew(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: PhlioSpacing.md),
        child: Column(
          children: [
            Container(
              width: 63,
              height: 63,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: PhlioColors.border, width: 1.5),
              ),
              child: const Icon(Icons.add_rounded, color: PhlioColors.textSecondary),
            ),
            const SizedBox(height: PhlioSpacing.xs),
            Text('New', style: PhlioTypography.caption),
          ],
        ),
      ),
    );
  }

  Widget _tabRow() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: PhlioColors.borderSubtle,
      indicatorColor: PhlioColors.brandOrange,
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: PhlioColors.textPrimary,
      unselectedLabelColor: PhlioColors.textMuted,
      labelStyle: PhlioTypography.label.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: PhlioTypography.label,
      tabs: [for (final tab in _tabs) Tab(text: tab)],
    );
  }

  Widget _emptyContent({
    required IconData icon,
    required String message,
    required String hint,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhlioFox(size: 90, pose: PhlioFoxPose.coffee),
          const SizedBox(height: PhlioSpacing.md),
          Text(message, style: PhlioTypography.title),
          const SizedBox(height: PhlioSpacing.xs),
          Text(hint, style: PhlioTypography.body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}


/// Instagram-style song trim sheet: full-song waveform strip with a
/// draggable 60-second selection window, times, and preview playback.
class _SongTrimSheet extends StatefulWidget {
  const _SongTrimSheet({required this.filePath, required this.duration});

  final String filePath;
  final Duration duration;

  @override
  State<_SongTrimSheet> createState() => _SongTrimSheetState();
}

class _SongTrimSheetState extends State<_SongTrimSheet> {
  static const _maxSection = 60.0;

  late double _duration = widget.duration.inMilliseconds / 1000;
  double _offsetFraction = 0; // where the selection window starts (0..1)
  double _windowFraction = 1; // window length as a fraction of the song

  late double _sectionLength = _duration < _maxSection ? _duration : _maxSection;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _windowFraction = (_sectionLength / _duration).clamp(0.0, 1.0);
  }

  double get _start => _offsetFraction * _duration;
  double get _end => _start + _windowFraction * _duration;

  String _clock(double seconds) {
    final s = seconds.round();
    return '${(s ~/ 60)}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _previewing = false);
      return;
    }
    try {
      await _previewPlayer.play(DeviceFileSource(widget.filePath));
      await _previewPlayer.seek(Duration(milliseconds: (_start * 1000).round()));
      if (mounted) setState(() => _previewing = true);
      _previewPlayer.onPositionChanged.listen((position) {
        final pos = position.inMilliseconds / 1000;
        if (pos >= _end) {
          _previewPlayer.stop();
          if (mounted) setState(() => _previewing = false);
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preview unavailable for this file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bars = List<double>.generate(
      72,
      (i) => 0.25 +
          0.6 *
              (0.5 + 0.5 * _pseudoWave(i + widget.filePath.hashCode.abs() % 7)),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: "New song" + Done.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Row(
                children: [
                  Text('New song', style: PhlioTypography.headline),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        Navigator.of(context).pop((_start, _end)),
                    child: Text('Done',
                        style: PhlioTypography.bodyStrong
                            .copyWith(color: PhlioColors.brandOrange)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PhlioSpacing.lg),
            // Cover + file name.
            Center(
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: PhlioColors.surfaceElevated,
                      borderRadius: PhlioRadii.mdRadius,
                      border: Border.all(color: PhlioColors.border),
                    ),
                    child: const Icon(Icons.music_note_rounded,
                        color: PhlioColors.brandOrange, size: 30),
                  ),
                  const SizedBox(height: PhlioSpacing.sm),
                  SizedBox(
                    width: 220,
                    child: Text(
                      widget.filePath.split('/').last,
                      textAlign: TextAlign.center,
                      style: PhlioTypography.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PhlioSpacing.xl),
            // Section length badge + times + preview.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: PhlioColors.border),
                    ),
                    child: Text('${_sectionLength.round()}',
                        style: PhlioTypography.caption),
                  ),
                  const Spacer(),
                  Text(
                    '${_clock(_start)} - ${_clock(_end)}',
                    style: PhlioTypography.bodyStrong,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _togglePreview,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        gradient: PhlioColors.sunsetGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: PhlioColors.textOnBrand,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PhlioSpacing.lg),
            // Waveform with the draggable selection window.
            LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth - 48;
                final windowWidth = trackWidth * _windowFraction;
                final dimBars = [
                  for (var i = 0; i < 72; i++)
                    0.25 + 0.6 * (0.5 + 0.5 * _pseudoWave(i + i * 137 % 97)),
                ];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    height: 110,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Full waveform (dim).
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final h in dimBars)
                              Container(
                                width: 3,
                                height: 70 * h,
                                decoration: BoxDecoration(
                                  color: PhlioColors.textMuted
                                      .withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                          ],
                        ),
                        // Selection window (draggable).
                        Positioned(
                          left: _offsetFraction * trackWidth,
                          width: windowWidth,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                _offsetFraction = (_offsetFraction +
                                        details.delta.dx / trackWidth)
                                    .clamp(0.0, 1.0 - _windowFraction);
                              });
                            },
                            child: Container(
                              height: 96,
                              decoration: BoxDecoration(
                                gradient: PhlioColors.sunsetGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  for (final h in dimBars)
                                    Expanded(
                                      child: Center(
                                        child: Container(
                                          width: 2,
                                          height: 56 * h,
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: PhlioSpacing.lg),
          ],
        ),
      ),
    );
  }

  double _pseudoWave(int i) {
    // Deterministic pseudo-random bar heights so the waveform is stable.
    var x = (i * 137 + 41) % 97;
    return x / 97;
  }
}
