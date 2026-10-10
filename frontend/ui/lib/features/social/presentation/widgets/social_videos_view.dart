import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import '../../../../app/config/app_config.dart';
import 'creator_follow_button.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';

/// Database-backed video feed with persistent creator subscriptions.
/// The plain State owns no WidgetRef, preserving hot-reload compatibility.
/// One video/live entry. `kind` distinguishes live streams (red badge +
/// viewer count) from long-form videos and clips (view count).
@immutable
class SocialVideo {
  const SocialVideo({
    required this.title,
    required this.creator,
    required this.avatarAsset,
    required this.thumbAsset,
    required this.category,
    required this.kind,
    required this.metric,
    this.playable,
  });

  final PlayableVideo? playable;
  final String title;
  final String creator;
  final String avatarAsset;
  final String thumbAsset;
  final String category;
  final SocialVideoKind kind;
  final String metric; // "1,240 viewers" or "48.2K views"
}

enum SocialVideoKind { live, video, clip }

/// The backend owns discovery and subscriptions.
final followedCreatorsProvider = Provider<Set<String>>(
    (ref) => ref.watch(creatorFollowingProvider).valueOrNull ?? <String>{});
const List<SocialVideo> kSocialVideos = [];
const List<String> kFollowersOfMe = [];
const List<String> kDiscoverCreators = [];
SocialVideo socialVideoPresentation(PlayableVideo video) => SocialVideo(
      playable: video,
      title: video.title,
      creator: video.creator,
      avatarAsset: video.avatarUrl ?? '',
      thumbAsset: video.thumbnailUrl ?? '',
      category: video.kind == 'clip' ? 'Clips' : 'Videos',
      kind: video.kind == 'clip' ? SocialVideoKind.clip : SocialVideoKind.video,
      metric: video.durationSeconds > 0
          ? '${video.durationSeconds ~/ 60}:${(video.durationSeconds % 60).toString().padLeft(2, '0')}'
          : video.kind == 'clip'
              ? 'Clip'
              : 'Video',
    );

/// Home Videos tab — the Following feed.
class SocialVideosView extends StatefulWidget {
  const SocialVideosView({super.key});
  @override
  State<SocialVideosView> createState() => _SocialVideosViewState();
}

class _SocialVideosViewState extends State<SocialVideosView> {
  @override
  Widget build(BuildContext context) {
    // Consumer child owns the Riverpod ref; this State stays ref-free.
    return Consumer(
      builder: (context, ref, child) => _followingFeed(context, ref),
    );
  }

  Widget _followingFeed(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedCreatorsProvider);
    final catalog = ref.watch(socialVideoCatalogProvider);
    final videos = (catalog.valueOrNull ?? <PlayableVideo>[])
        .where((v) => v.kind != 'clip')
        .toList();
    final fromFollows =
        videos.where((v) => followed.contains(v.creator)).toList();
    final recommended =
        videos.where((v) => !followed.contains(v.creator)).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.xxl),
      children: [
        _sectionLabel('Following'),
        // Followed creators' content — live and VOD interleaved, newest-first
        // feel via the seed order.
        for (final video in fromFollows)
          SocialVideoCard(
              video: socialVideoPresentation(video),
              fallbackGradient: true,
              onTap: () => ref.read(videoPlaybackProvider).open(video)),
        _sectionLabel('Recommended for you'),
        for (final video in recommended)
          SocialVideoCard(
            video: socialVideoPresentation(video),
            fallbackGradient: true,
            showFollowPill: true,
            onTap: () => ref.read(videoPlaybackProvider).open(video),
          ),
        if (catalog.isLoading) const Center(child: CircularProgressIndicator()),
        if (catalog.hasError)
          Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                  child: const Text('Could not load videos. Retry'))),
        if (catalog.hasValue && videos.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No videos yet. Publish the first one.')),
      ],
    );
  }

  static Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.xl, PhlioSpacing.lg, PhlioSpacing.sm),
      child: Text(text, style: PhlioTypography.title),
    );
  }
}

/// Twitch-style full-width card: 16:9 thumb with LIVE badge + metric overlay,
/// then avatar / creator / Follow pill, title and category chip below.
class SocialVideoCard extends ConsumerWidget {
  const SocialVideoCard({
    required this.video,
    required this.onTap,
    this.showFollowPill = false,
    this.fallbackGradient = false,
    super.key,
  });

  final SocialVideo video;
  final VoidCallback onTap;
  final bool showFollowPill;
  final bool fallbackGradient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ContentSurface(
        platform: 'social',
        contentId: video.playable?.id ?? video.title,
        child: _content(context, ref));
  }

  Widget _content(BuildContext context, WidgetRef ref) {
    final isLive = video.kind == SocialVideoKind.live;
    return Padding(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: fallbackGradient && video.thumbAsset.isEmpty
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                PhlioColors.brandViolet.withValues(alpha: 0.35),
                                PhlioColors.surfaceElevated,
                              ],
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.play_arrow_rounded,
                                size: 44, color: PhlioColors.textSecondary),
                          ),
                        )
                      : Image.network(
                          AppConfig.mediaUrl(video.thumbAsset),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  PhlioColors.brandViolet
                                      .withValues(alpha: 0.35),
                                  PhlioColors.surfaceElevated,
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.play_arrow_rounded,
                                  size: 44, color: PhlioColors.textSecondary),
                            ),
                          ),
                        ),
                ),
                if (isLive)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _liveBadge(),
                  ),
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: _overlayPill(video.metric),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.lg, 0),
              child: Row(
                children: [
                  GestureDetector(
                    // Tap the creator's avatar/name to open their profile.
                    onTap: () => context.push('/creator/${video.creator}'),
                    child: ClipOval(
                      child: Image.network(
                        AppConfig.mediaUrl(video.avatarAsset),
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 36,
                          height: 36,
                          color:
                              PhlioColors.brandViolet.withValues(alpha: 0.25),
                          alignment: Alignment.center,
                          child: Text(
                            video.creator.isEmpty
                                ? '?'
                                : video.creator[0].toUpperCase(),
                            style: PhlioTypography.label
                                .copyWith(color: PhlioColors.brandLavender),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: PhlioSpacing.sm),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('/creator/${video.creator}'),
                      child: Text(
                        video.creator,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.bodyStrong,
                      ),
                    ),
                  ),
                  if (showFollowPill) ...[
                    const SizedBox(width: PhlioSpacing.sm),
                    CreatorFollowPill(creator: video.creator),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  PhlioSpacing.lg, PhlioSpacing.xxs, PhlioSpacing.lg, 0),
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.body
                    .copyWith(color: PhlioColors.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  PhlioSpacing.lg, PhlioSpacing.xs, PhlioSpacing.lg, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: PhlioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: PhlioColors.borderSubtle),
                ),
                child: Text(
                  video.category,
                  style: PhlioTypography.caption
                      .copyWith(fontSize: 11, color: PhlioColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PhlioColors.danger,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text('LIVE',
              style: PhlioTypography.label.copyWith(
                fontSize: 11,
                letterSpacing: 0.6,
                color: Colors.white,
              )),
        ],
      ),
    );
  }

  static Widget _overlayPill(String metric) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        metric,
        style: PhlioTypography.caption.copyWith(
          fontSize: 11,
          color: Colors.white,
        ),
      ),
    );
  }
}

class CreatorFollowPill extends StatelessWidget {
  const CreatorFollowPill({required this.creator, super.key});
  final String creator;
  @override
  Widget build(BuildContext context) => CreatorFollowButton(creator: creator);
}
