import 'post_poll.dart';
import 'post_photos.dart';
import 'content_owner_menu.dart';
import '../../../../shared/music/song_picker.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import 'package:phlio/shared/content/content_surface.dart';
// A single post in the feed — mirrors the reference Social screen's post
// cards: avatar + author row, text, an optional image, and a like/comment/
// share action row.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/app_config.dart';
import '../../../profile/presentation/widgets/profile_posts.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../domain/entities/post_entity.dart';
import 'package:phlio/core/network/media_cache.dart';
import 'package:phlio/features/phlio_agent/presentation/screens/move/move_social.dart';

class PostCard extends ConsumerWidget {
  const PostCard({
    required this.post,
    required this.authorName,
    required this.onToggleLike,
    required this.onOpenComments,
    super.key,
  });

  final PostEntity post;
  final String authorName;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ContentSurface(
        platform: 'social', contentId: post.id, child: _content(context, ref));
  }

  Widget _content(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(post.authorId)).valueOrNull;
    final displayName = profile?['full_name'] as String? ?? authorName;
    // Plain photos (not Phlio Move route cards) share one frame.
    final photos = [
      for (final m in post.media)
        if (m.kind == MediaKind.image && !isActivityMedia(m.url)) m
    ];
    return PhlioCard(
      padding: const EdgeInsets.all(PhlioSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ContentSongBadge(kind: 'post', target: post.id),
          Row(
            children: [
              GestureDetector(
                // Author profile from the post's avatar/name.
                onTap: () => context.push('/creator/${post.authorId}'),
                child: ContentAuthorAvatar(
                    author: post.authorId,
                    name: displayName,
                    imageUrl: profile?['avatar_url'] as String?,
                    size: 40),
              ),
              const SizedBox(width: PhlioSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/creator/${post.authorId}'),
                      child:
                          Text(displayName, style: PhlioTypography.bodyStrong),
                    ),
                    Text(timeago.format(post.createdAt),
                        style: PhlioTypography.caption),
                  ],
                ),
              ),
              ContentOwnerMenu(
                  id: post.id, owner: post.authorId, text: post.text),
            ],
          ),
          if (post.text.trim().isNotEmpty) ...[
            const SizedBox(height: PhlioSpacing.md),
            Text(post.text, style: PhlioTypography.bodyLarge),
          ],
          PostPoll(id: post.id),
          // Photos: one full-width frame (a carousel for several), shaped
          // like the first photo within 4:5 … 1.91:1.
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: PostPhotos(
                  key: ValueKey('photos-${post.id}'),
                  urls: [for (final m in photos) m.url]),
            ),
          for (final media in post.media)
            if (!photos.contains(media))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: media.kind == MediaKind.image && isActivityMedia(media.url)
                  // A Phlio Move activity: route card + stats; tap opens it
                  // from the Agent explore tab.
                  ? ActivityPostBlock(postId: post.id, imageUrl: media.url)
                  : AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(fit: StackFit.expand, children: [
                            if (media.thumbnailUrl != null)
                              phlioNetworkImage(
                                  AppConfig.mediaUrl(media.thumbnailUrl!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const ColoredBox(
                                          color: Color(0xFF182231))),
                            Center(
                                child: IconButton.filled(
                                    tooltip: 'Play video',
                                    onPressed: () => ref
                                        .read(videoPlaybackProvider)
                                        .open(PlayableVideo(
                                            id: post.id,
                                            title: post.text,
                                            creator: profile?['username']
                                                    as String? ??
                                                post.authorId,
                                            url: media.url)),
                                    icon: const Icon(Icons.play_arrow,
                                        size: 40))),
                          ]))),
            ),
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: PhlioSpacing.sm),
            Wrap(
              spacing: PhlioSpacing.xs,
              children: post.tags
                  .map((tag) => Text('#$tag',
                      style: PhlioTypography.label
                          .copyWith(color: PhlioColors.brandPurple)))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
