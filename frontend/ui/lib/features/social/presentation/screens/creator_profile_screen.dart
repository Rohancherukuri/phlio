import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../widgets/creator_chat.dart';
import '../../../profile/presentation/widgets/profile_posts.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import '../../../../app/config/app_config.dart';
import '../widgets/social_videos_view.dart';

/// Creator profile screen — opened by tapping any creator's avatar (video
/// cards, live rail, stories strip). A replica of the own-profile layout:
/// @handle header, avatar + stats, display name with verified badge, bio,
/// hashtag chips, pinned song, Follow/Message actions, Moments circles and
/// the same six content tabs (Posts / Replies / Reposts / Schedule / Chat /
/// Clips). Chat is public; the Message action opens a separate private DM.
///
/// Account identity and posts come from the API. Bundled demo creators retain
/// their sample moments and profile details when no account is available.

@immutable
class CreatorProfile {
  const CreatorProfile({
    required this.handle,
    required this.displayName,
    required this.avatarAsset,
    required this.verified,
    required this.followers,
    required this.following,
    required this.postCount,
    required this.hasPosts,
    this.bio,
    this.avatarUrl,
    this.tags = const [],
    this.songTitle,
    this.moments = const [],
    this.replies = const [],
    this.reposts = const [],
  });

  final String handle;
  final String displayName;
  final String avatarAsset;
  final bool verified;
  final int followers;
  final int following;
  final int postCount;
  final bool hasPosts;
  final String? bio;
  final String? avatarUrl;
  final List<String> tags;
  final String? songTitle;
  final List<String> moments;
  final List<({String to, String text})> replies;
  final List<String> reposts;
}

/// Shared brand gradients for Moments circles and placeholder post tiles.
const kProfileGradients = [
  [PhlioColors.brandOrange, PhlioColors.brandViolet],
  [PhlioColors.brandViolet, PhlioColors.surfaceElevated],
  [PhlioColors.brandPink, PhlioColors.brandOrange],
  [PhlioColors.brandLavender, PhlioColors.brandViolet],
];

class CreatorProfileScreen extends StatefulWidget {
  const CreatorProfileScreen({required this.username, super.key});

  final String username;

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  static const _tabs = [
    'Posts',
    'Replies',
    'Reposts',
    'Schedule',
    'Chat',
    'Clips'
  ];
  ProfilePostType _postType = ProfilePostType.articles;
  int _tab = 0; // Land on Posts, like the own-profile page.

  @override
  Widget build(BuildContext context) {
    // Consumer child owns the ref (follow state, DM thread); the State
    // itself stays ref-free for hot-reload safety.
    return Consumer(
      builder: (context, ref, _) {
        const CreatorProfile? seed = null;
        final remote = ref.watch(publicProfileProvider(widget.username));
        if (seed == null && !remote.hasValue) {
          return Scaffold(
              appBar: AppBar(),
              body: remote.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                    child: TextButton(
                        onPressed: () => ref
                            .invalidate(publicProfileProvider(widget.username)),
                        child: const Text('Profile unavailable. Retry'))),
                data: (_) => const SizedBox.shrink(),
              ));
        }
        final data = remote.valueOrNull;
        final profile = data == null
            ? seed!
            : CreatorProfile(
                handle: data['username'] as String,
                displayName: data['full_name'] as String,
                avatarAsset: seed?.avatarAsset ?? '',
                avatarUrl: data['avatar_url'] as String?,
                verified: data['is_verified'] == true,
                followers: data['followers'] as int? ?? 0,
                following: data['following'] as int? ?? 0,
                postCount: data['post_count'] as int? ?? 0,
                hasPosts: true,
                bio: data['bio'] as String?,
                tags: (data['interests'] as List? ?? []).cast<String>(),
                moments: seed?.moments ?? const [],
                replies: seed?.replies ?? const [],
                reposts: seed?.reposts ?? const [],
                songTitle: seed?.songTitle,
              );
        final followed = ref.watch(followedCreatorsProvider);
        final isFollowed = followed.contains(profile.handle);
        final videos = ref
                .watch(socialVideoCatalogProvider)
                .valueOrNull
                ?.where((v) => v.creator == profile.handle)
                .map(socialVideoPresentation)
                .toList() ??
            <SocialVideo>[];
        final clips =
            videos.where((v) => v.kind == SocialVideoKind.clip).toList();
        final isLive = videos.any((v) => v.kind == SocialVideoKind.live);

        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                // -- Scrollable header -------------------------------------
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: PhlioSpacing.sm),
                        child: Row(
                          children: [
                            BackButton(onPressed: () => context.pop()),
                            Expanded(
                              child: Text(
                                '@${profile.handle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PhlioTypography.headline,
                              ),
                            ),
                            IconButton(
                              tooltip: 'More',
                              icon: const Icon(Icons.more_vert_rounded,
                                  color: PhlioColors.textSecondary),
                              onPressed: () =>
                                  ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Mute, report and block arrive with the social graph.')),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg,
                            PhlioSpacing.sm, PhlioSpacing.lg, 0),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final stats = [
                            _stat(profile.postCount, 'posts'),
                            _stat(profile.followers, 'followers'),
                            _stat(profile.following, 'following'),
                          ];
                          if (constraints.maxWidth < 500 ||
                              MediaQuery.textScalerOf(context).scale(14) > 20) {
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _avatar(profile, 92),
                                  const SizedBox(height: 16),
                                  Wrap(
                                      spacing: 24,
                                      runSpacing: 12,
                                      children: stats),
                                ]);
                          }
                          return Row(children: [
                            _avatar(profile, 92),
                            const SizedBox(width: 24),
                            Expanded(
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: stats))
                          ]);
                        }),
                      ),
                      MutualAvatars(target: profile.handle),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg,
                            PhlioSpacing.md, PhlioSpacing.lg, 0),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                profile.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PhlioTypography.headline,
                              ),
                            ),
                            if (profile.verified) ...[
                              const SizedBox(width: PhlioSpacing.xs),
                              const Icon(Icons.verified_rounded,
                                  size: 18, color: PhlioColors.brandLavender),
                            ],
                            if (isLive) ...[
                              const SizedBox(width: PhlioSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: PhlioColors.danger,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('LIVE',
                                    style: PhlioTypography.label.copyWith(
                                        fontSize: 10,
                                        letterSpacing: 0.6,
                                        color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg,
                            PhlioSpacing.xs, PhlioSpacing.lg, 0),
                        child: Text(
                          profile.bio ?? 'Hasn\u2019t added a bio yet.',
                          style: PhlioTypography.body.copyWith(
                              color: profile.bio == null
                                  ? PhlioColors.textMuted
                                  : PhlioColors.textSecondary),
                        ),
                      ),
                      if (profile.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg,
                              PhlioSpacing.sm, PhlioSpacing.lg, 0),
                          child: Wrap(
                            spacing: PhlioSpacing.sm,
                            runSpacing: PhlioSpacing.sm,
                            children: [
                              for (final tag in profile.tags)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: PhlioColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(tag,
                                      style: PhlioTypography.label.copyWith(
                                          fontSize: 12,
                                          color: PhlioColors.textSecondary)),
                                ),
                            ],
                          ),
                        ),
                      if (profile.songTitle != null) ...[
                        const SizedBox(height: PhlioSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: PhlioSpacing.lg),
                          child: _songCard(profile.songTitle!),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg,
                            PhlioSpacing.md, PhlioSpacing.lg, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  try {
                                    await ref
                                        .read(socialVideoApiProvider)
                                        .follow(profile.handle, !isFollowed);
                                    ref.invalidate(creatorFollowingProvider);
                                  } catch (_) {
                                    if (context.mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Could not update follow. Try again.')));
                                  }
                                },
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isFollowed
                                        ? PhlioColors.surfaceElevated
                                        : PhlioColors.brandViolet,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isFollowed
                                        ? Border.all(
                                            color: PhlioColors.borderSubtle)
                                        : null,
                                  ),
                                  child: Text(
                                    isFollowed ? 'Following' : 'Follow',
                                    style: PhlioTypography.label.copyWith(
                                      color: isFollowed
                                          ? PhlioColors.textPrimary
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: PhlioSpacing.sm),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    context.push('/dm/${profile.handle}'),
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: PhlioColors.borderSubtle),
                                  ),
                                  child: Text('Message',
                                      style: PhlioTypography.label.copyWith(
                                          color: PhlioColors.textPrimary)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (profile.moments.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              PhlioSpacing.lg,
                              PhlioSpacing.xl,
                              PhlioSpacing.lg,
                              PhlioSpacing.sm),
                          child: Text('Moments', style: PhlioTypography.title),
                        ),
                        SizedBox(
                          height: 104,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: PhlioSpacing.lg),
                            children: [
                              for (var i = 0; i < profile.moments.length; i++)
                                _moment(profile.moments[i], i),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // -- Pinned tab row (replica of the own-profile tabs) --------
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ProfileTabBar(
                    tabs: _tabs,
                    postType: _postType,
                    extent: MediaQuery.textScalerOf(context).scale(20) + 40,
                    onPostType: (value) => setState(() {
                      _postType = value;
                      _tab = 0;
                    }),
                    selected: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ),
                // -- Tab content ---------------------------------------------
                if (_tab == 0)
                  SliverToBoxAdapter(
                      child: SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.65,
                          child: ProfilePosts(
                              author: profile.handle, type: _postType)))
                else if (_tab == 1)
                  profile.replies.isNotEmpty
                      ? SliverToBoxAdapter(child: _replies(profile.replies))
                      : _foxyEmpty(
                          'No replies yet',
                          'Replies to other posts will show up here.',
                          PhlioFoxPose.explorer)
                else if (_tab == 2)
                  profile.reposts.isNotEmpty
                      ? SliverToBoxAdapter(child: _reposts(profile.reposts))
                      : _foxyEmpty(
                          'Nothing reposted yet',
                          'Videos they share will appear here.',
                          PhlioFoxPose.explorer)
                else if (_tab == 3)
                  _foxyEmpty(
                      'Nothing scheduled',
                      'Streams and events arrive with the Events domain.',
                      PhlioFoxPose.happy)
                else if (_tab == 4)
                  // Public creator chat never reads private DM history.
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.62,
                      child: CreatorChat(username: profile.handle),
                    ),
                  )
                else
                  clips.isNotEmpty
                      ? SliverToBoxAdapter(child: _videosGrid(clips, ref))
                      : _foxyEmpty(
                          'No clips yet',
                          'Their best moments will be clipped here.',
                          PhlioFoxPose.cozy),
              ],
            ),
          ),
        );
      },
    );
  }

  // -- Pieces -------------------------------------------------------------------

  Widget _foxyEmpty(String title, String subtitle, PhlioFoxPose pose) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            PhlioFox(size: 88, pose: pose),
            const SizedBox(height: PhlioSpacing.md),
            Text(title, style: PhlioTypography.title),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style:
                  PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _replies(List<({String to, String text})> replies) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.md, PhlioSpacing.lg, 0),
      child: Column(
        children: [
          for (final reply in replies)
            Container(
              margin: const EdgeInsets.only(bottom: PhlioSpacing.md),
              padding: const EdgeInsets.all(PhlioSpacing.md),
              decoration: BoxDecoration(
                color: PhlioColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PhlioColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reply.text, style: PhlioTypography.body),
                  const SizedBox(height: PhlioSpacing.xs),
                  Text('Replying to @${reply.to}',
                      style: PhlioTypography.caption
                          .copyWith(color: PhlioColors.textMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _reposts(List<String> titles) {
    final videos = [
      for (final title in titles)
        if (kSocialVideos.any((v) => v.title == title))
          kSocialVideos.firstWhere((v) => v.title == title),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.md, PhlioSpacing.lg, 0),
      child: Column(
        children: [
          for (final video in videos)
            Container(
              margin: const EdgeInsets.only(bottom: PhlioSpacing.md),
              padding: const EdgeInsets.all(PhlioSpacing.sm),
              decoration: BoxDecoration(
                color: PhlioColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PhlioColors.borderSubtle),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      video.thumbAsset,
                      width: 72,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 44,
                        color: PhlioColors.surfaceElevated,
                      ),
                    ),
                  ),
                  const SizedBox(width: PhlioSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PhlioTypography.label),
                        const SizedBox(height: 2),
                        Text('@${video.creator} · ${video.metric}',
                            style: PhlioTypography.caption
                                .copyWith(color: PhlioColors.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.repeat_rounded,
                      size: 18, color: PhlioColors.brandLavender),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatar(CreatorProfile profile, double size) {
    if (profile.avatarUrl != null || profile.avatarAsset.isEmpty) {
      return PhlioAvatar(
          name: profile.displayName, imageUrl: profile.avatarUrl, size: size);
    }
    return ClipOval(
      child: Image.asset(
        profile.avatarAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: PhlioColors.brandViolet.withValues(alpha: 0.25),
          alignment: Alignment.center,
          child: Text(
            profile.handle[0].toUpperCase(),
            style: PhlioTypography.headline
                .copyWith(color: PhlioColors.brandLavender),
          ),
        ),
      ),
    );
  }

  Widget _stat(int value, String label) {
    return Column(
      children: [
        Text(_compact(value), style: PhlioTypography.headline),
        const SizedBox(height: 2),
        Text(label,
            style: PhlioTypography.caption
                .copyWith(color: PhlioColors.textSecondary)),
      ],
    );
  }

  Widget _songCard(String fileName) {
    return Container(
      padding: const EdgeInsets.all(PhlioSpacing.md),
      decoration: BoxDecoration(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PhlioColors.borderSubtle),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Demo song — profile audio lands with the social graph.')),
            ),
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                gradient: PhlioColors.sunsetGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
          const SizedBox(width: PhlioSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.label),
                const SizedBox(height: 2),
                Text('Pinned song · from their profile · 60 s preview',
                    style: PhlioTypography.caption
                        .copyWith(color: PhlioColors.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.music_note_rounded,
              color: PhlioColors.brandOrange, size: 22),
        ],
      ),
    );
  }

  Widget _moment(String label, int index) {
    final colors = kProfileGradients[index % kProfileGradients.length];
    return Padding(
      padding: const EdgeInsets.only(right: PhlioSpacing.lg),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label.characters.take(2).toString().toUpperCase(),
              style: PhlioTypography.label.copyWith(
                fontSize: 15,
                letterSpacing: 1,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: PhlioSpacing.xs),
          Text(label,
              style: PhlioTypography.caption
                  .copyWith(color: PhlioColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _videosGrid(List<SocialVideo> videos, WidgetRef ref) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.md, PhlioSpacing.lg, 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return GestureDetector(
          onLongPress: video.playable == null
              ? null
              : () => showContentShare(context, 'social/${video.playable!.id}'),
          onTap: video.playable == null
              ? null
              : () => ref.read(videoPlaybackProvider).open(video.playable!),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                AppConfig.mediaUrl(video.thumbAsset),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: PhlioColors.surfaceElevated),
              ),
              if (video.kind == SocialVideoKind.live)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: PhlioColors.danger,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('LIVE',
                        style: PhlioTypography.label.copyWith(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            color: Colors.white)),
                  ),
                ),
              Positioned(
                bottom: 6,
                left: 6,
                child: Text(
                  video.metric,
                  style: PhlioTypography.caption
                      .copyWith(fontSize: 10, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) {
      final m = n / 1000000;
      return '${m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1)}M';
    }
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k == k.roundToDouble() ? 0 : 1)}K';
    }
    return '$n';
  }
}

/// Pinned tab bar replicating the own-profile tabs (Posts…Clips). Horizontal
/// scrolling keeps six labels safe on narrow screens.
class _ProfileTabBar extends SliverPersistentHeaderDelegate {
  const _ProfileTabBar({
    required this.tabs,
    required this.selected,
    required this.onChanged,
    required this.postType,
    required this.extent,
    required this.onPostType,
  });

  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  final ProfilePostType postType;
  final double extent;
  final ValueChanged<ProfilePostType> onPostType;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i == 0)
                        ProfilePostsMenu(
                            selected: postType,
                            onOpened: () => onChanged(0),
                            onSelected: onPostType)
                      else
                        Text(
                          tabs[i],
                          style: PhlioTypography.label.copyWith(
                            fontSize: 13,
                            color: selected == i
                                ? PhlioColors.textPrimary
                                : PhlioColors.textSecondary,
                            fontWeight: selected == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Container(
                        width: 30,
                        height: 3,
                        decoration: BoxDecoration(
                          color: selected == i
                              ? PhlioColors.brandOrange
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBar oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.tabs != tabs ||
      oldDelegate.postType != postType ||
      oldDelegate.extent != extent;
}
