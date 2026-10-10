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
    return PhlioCard(
      padding: const EdgeInsets.all(PhlioSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                // Author profile from the post's avatar/name.
                onTap: () => context.push('/creator/${post.authorId}'),
                child: PhlioAvatar(
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
              const Icon(Icons.more_horiz_rounded,
                  color: PhlioColors.textMuted),
            ],
          ),
          const SizedBox(height: PhlioSpacing.md),
          Text(post.text, style: PhlioTypography.bodyLarge),
          for (final media in post.media)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: media.kind == MediaKind.image
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(AppConfig.mediaUrl(media.url),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Text('Image unavailable')))
                  : AspectRatio(
                      aspectRatio: 16 / 9,
                      child: FilledButton.tonalIcon(
                          onPressed: () => ref.read(videoPlaybackProvider).open(
                              PlayableVideo(
                                  id: post.id,
                                  title: post.text,
                                  creator: profile?['username'] as String? ??
                                      post.authorId,
                                  url: media.url)),
                          icon: const Icon(Icons.play_circle_outline, size: 40),
                          label: const Text('Play video'))),
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
          const SizedBox(height: PhlioSpacing.md),
          Row(
            children: [
              _ActionButton(
                icon: Icons.mode_comment_outlined,
                label: '${post.commentCount}',
                onTap: onOpenComments,
              ),
              const Spacer(),

            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: PhlioColors.textMuted),
          const SizedBox(width: PhlioSpacing.xs),
          Text(label, style: PhlioTypography.label),
        ],
      ),
    );
  }
}
