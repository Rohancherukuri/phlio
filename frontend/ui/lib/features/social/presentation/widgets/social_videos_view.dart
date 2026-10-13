import 'video_thumbnail.dart';
import '../../../../shared/content/social_comments_sheet.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import '../../../../app/config/app_config.dart';
import 'creator_follow_button.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

    final entries = <Object>[
      if (fromFollows.isNotEmpty) 'Following',
      ...fromFollows,
      'Recommended for you',
      ...recommended,
    ];
    return RefreshIndicator(
      onRefresh: () => ref.refresh(socialVideoCatalogProvider.future),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 250,
        padding: const EdgeInsets.only(bottom: PhlioSpacing.xxl),
        itemCount: entries.length + 1,
        itemBuilder: (context, index) {
          if (index == entries.length) {
            if (catalog.isLoading)
              return const Center(child: CircularProgressIndicator());
            if (catalog.hasError)
              return Center(
                  child: TextButton(
                      onPressed: () =>
                          ref.invalidate(socialVideoCatalogProvider),
                      child: const Text('Could not load videos. Retry')));
            return videos.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No videos yet. Publish the first one.'))
                : const SizedBox.shrink();
          }
          final entry = entries[index];
          if (entry is String) return _sectionLabel(entry);
          final video = entry as PlayableVideo;
          return SocialVideoCard(
              key: ValueKey(video.id),
              video: socialVideoPresentation(video),
              showFollowPill: !followed.contains(video.creator),
              onTap: () => ref.read(videoPlaybackProvider).open(video));
        },
      ),
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
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(fit: StackFit.expand, children: [
                        VideoThumbnail(url: video.thumbAsset),
                        Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(video.metric,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)))),
                      ])))),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
                onTap: () => context.push('/creator/${video.creator}'),
                child: CircleAvatar(
                    radius: 19,
                    backgroundImage: video.avatarAsset.isEmpty
                        ? null
                        : NetworkImage(AppConfig.mediaUrl(video.avatarAsset)))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  InkWell(
                      onTap: onTap,
                      child: Text(video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              height: 1.3,
                              fontWeight: FontWeight.w600))),
                  const SizedBox(height: 5),
                  GestureDetector(
                      onTap: () => context.push('/creator/${video.creator}'),
                      child: Text('@${video.creator}',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF858D9E)))),
                ])),
            PopupMenuButton<String>(
                tooltip: 'Video options',
                onSelected: (value) {
                  if (value == 'comments')
                    showSocialComments(context, video.playable!.id);
                  else
                    showContentShare(context, 'social/${video.playable!.id}');
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'comments', child: Text('Comments')),
                      PopupMenuItem(value: 'share', child: Text('Share'))
                    ]),
          ]),
          if (showFollowPill)
            Align(
                alignment: Alignment.centerRight,
                child: CreatorFollowPill(creator: video.creator)),
          if (video.playable?.attribution != null)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(video.playable!.attribution!,
                    style: const TextStyle(
                        fontSize: 10, height: 1.3, color: Color(0xFF858D9E)))),
        ]));
  }
}

class CreatorFollowPill extends StatelessWidget {
  const CreatorFollowPill({required this.creator, super.key});
  final String creator;
  @override
  Widget build(BuildContext context) => CreatorFollowButton(creator: creator);
}
