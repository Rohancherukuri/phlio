// A single post in the feed — mirrors the reference Social screen's post
// cards: avatar + author row, text, an optional image, and a like/comment/
// share action row.

import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../domain/entities/post_entity.dart';

class PostCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return PhlioCard(
      padding: const EdgeInsets.all(PhlioSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhlioAvatar(name: authorName, size: 40),
              const SizedBox(width: PhlioSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(authorName, style: PhlioTypography.bodyStrong),
                    Text(timeago.format(post.createdAt), style: PhlioTypography.caption),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz_rounded, color: PhlioColors.textMuted),
            ],
          ),
          const SizedBox(height: PhlioSpacing.md),
          Text(post.text, style: PhlioTypography.bodyLarge),
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: PhlioSpacing.sm),
            Wrap(
              spacing: PhlioSpacing.xs,
              children: post.tags
                  .map((tag) => Text('#$tag', style: PhlioTypography.label.copyWith(color: PhlioColors.brandPurple)))
                  .toList(),
            ),
          ],
          const SizedBox(height: PhlioSpacing.md),
          Row(
            children: [
              _ActionButton(
                icon: post.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                iconColor: post.likedByMe ? PhlioColors.danger : PhlioColors.textMuted,
                label: '${post.likeCount}',
                onTap: onToggleLike,
              ),
              const SizedBox(width: PhlioSpacing.xl),
              _ActionButton(
                icon: Icons.mode_comment_outlined,
                label: '${post.commentCount}',
                onTap: onOpenComments,
              ),
              const Spacer(),
              const Icon(Icons.bookmark_border_rounded, color: PhlioColors.textMuted, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap, this.iconColor});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: iconColor ?? PhlioColors.textMuted),
          const SizedBox(width: PhlioSpacing.xs),
          Text(label, style: PhlioTypography.label),
        ],
      ),
    );
  }
}
