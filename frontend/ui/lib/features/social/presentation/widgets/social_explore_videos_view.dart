import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import 'social_videos_view.dart';

/// Explore → Videos (Twitch Browse-style discovery): a live rail, grids of
/// videos from creators you follow / who follow you / other creators, and a
/// category rail with tags. All content is the seeded demo catalog from
/// social_videos_view.dart — tap targets are honest about demo playback.
class SocialExploreVideosView extends ConsumerWidget {
  const SocialExploreVideosView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedCreatorsProvider);
    final live =
        kSocialVideos.where((v) => v.kind == SocialVideoKind.live).toList();
    final fromFollows = kSocialVideos
        .where((v) =>
            followed.contains(v.creator) && v.kind != SocialVideoKind.live)
        .toList();
    final fromFollowers = kSocialVideos
        .where((v) =>
            kFollowersOfMe.contains(v.creator) &&
            v.kind != SocialVideoKind.live)
        .toList();
    final discover = kSocialVideos
        .where((v) =>
            kDiscoverCreators.contains(v.creator) &&
            v.kind != SocialVideoKind.live)
        .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg, PhlioSpacing.md,
              PhlioSpacing.lg, PhlioSpacing.xs),
          child: Text('Browse', style: PhlioTypography.headline),
        ),
        if (live.isNotEmpty) ...[
          _sectionHeader('Live now'),
          SizedBox(
            height: 234,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
              itemCount: live.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: PhlioSpacing.md),
              itemBuilder: (context, index) => _LiveRailCard(
                video: live[index],
                showFollowPill: !followed.contains(live[index].creator),
              ),
            ),
          ),
        ],
        _sectionHeader('From creators you follow'),
        _videoGrid(fromFollows),
        _sectionHeader('Follows you'),
        _videoGrid(fromFollowers),
        _sectionHeader('Discover more creators'),
        _videoGrid(discover),
        _sectionHeader('Categories'),
        _categoryRail(),
      ],
    );
  }

  Widget _videoGrid(List<SocialVideo> videos) {
    if (videos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
        child: Text('Nothing here yet.', style: PhlioTypography.caption),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: PhlioSpacing.md,
        crossAxisSpacing: PhlioSpacing.md,
        childAspectRatio: 0.78,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) => _GridCard(video: videos[index]),
    );
  }

  Widget _categoryRail() {
    // First entry per category provides the tag's cover art.
    final categories = <String, SocialVideo>{};
    for (final video in kSocialVideos) {
      categories.putIfAbsent(video.category, () => video);
    }
    return SizedBox(
      height: 128,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
        children: [
          for (final entry in categories.entries)
            _CategoryCard(
              category: entry.key,
              cover: entry.value.thumbAsset,
              videoCount:
                  kSocialVideos.where((v) => v.category == entry.key).length,
            ),
        ],
      ),
    );
  }

  static Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.xl, PhlioSpacing.lg, PhlioSpacing.sm),
      child: Text(text, style: PhlioTypography.title),
    );
  }
}

void _demoNote(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:
        Text('Demo content — real playback arrives with the video pipeline.'),
  ));
}

/// Horizontal live card: 16:9 thumb with LIVE + viewers, creator row with an
/// optional Follow pill below — the Twitch Browse pattern.
class _LiveRailCard extends ConsumerWidget {
  const _LiveRailCard({required this.video, required this.showFollowPill});

  final SocialVideo video;
  final bool showFollowPill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 288,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _demoNote(context),
            child: ClipRRect(
              borderRadius: PhlioRadii.lgRadius,
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.asset(
                      video.thumbAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: PhlioColors.surfaceElevated),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _smallLiveBadge(),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        child: Text(
                          video.metric,
                          style: PhlioTypography.caption
                              .copyWith(fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: PhlioSpacing.xs),
          Row(
            children: [
              GestureDetector(
                // Creator profile on avatar/name tap.
                onTap: () => context.push('/creator/${video.creator}'),
                child: ClipOval(
                  child: Image.asset(
                    video.avatarAsset,
                    width: 26,
                    height: 26,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 26,
                      height: 26,
                      color: PhlioColors.brandViolet.withValues(alpha: 0.25),
                      alignment: Alignment.center,
                      child: Text(video.creator[0].toUpperCase(),
                          style: PhlioTypography.caption
                              .copyWith(color: PhlioColors.brandLavender)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: PhlioSpacing.xs),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/creator/${video.creator}'),
                  child: Text(
                    video.creator,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.label,
                  ),
                ),
              ),
              if (showFollowPill) ...[
                const SizedBox(width: PhlioSpacing.xs),
                CreatorFollowPill(creator: video.creator),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                PhlioTypography.caption.copyWith(color: PhlioColors.textMuted),
          ),
        ],
      ),
    );
  }

  static Widget _smallLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: PhlioColors.danger,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text('LIVE',
          style: PhlioTypography.label.copyWith(
            fontSize: 10,
            letterSpacing: 0.6,
            color: Colors.white,
          )),
    );
  }
}

/// Two-column discovery card.
class _GridCard extends StatelessWidget {
  const _GridCard({required this.video});

  final SocialVideo video;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _demoNote(context),
      child: Container(
        decoration: BoxDecoration(
          color: PhlioColors.surface,
          borderRadius: PhlioRadii.lgRadius,
          border: Border.all(color: PhlioColors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                video.thumbAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: PhlioColors.surfaceElevated),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(PhlioSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.label.copyWith(height: 1.25),
                  ),
                  const SizedBox(height: PhlioSpacing.xs),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.push('/creator/${video.creator}'),
                        child: ClipOval(
                          child: Image.asset(
                            video.avatarAsset,
                            width: 18,
                            height: 18,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 18,
                              height: 18,
                              color: PhlioColors.brandViolet
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: PhlioSpacing.xs),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              context.push('/creator/${video.creator}'),
                          child: Text(
                            video.creator,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PhlioTypography.caption,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${video.metric} · ${video.category}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.caption
                        .copyWith(fontSize: 10, color: PhlioColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category tag card for the horizontal rail.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.cover,
    required this.videoCount,
  });

  final String category;
  final String cover;
  final int videoCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _demoNote(context),
      child: Container(
        width: 128,
        margin: const EdgeInsets.only(right: PhlioSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: PhlioRadii.mdRadius,
              child: Image.asset(
                cover,
                width: 128,
                height: 76,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 128,
                  height: 76,
                  color: PhlioColors.surfaceElevated,
                ),
              ),
            ),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhlioTypography.label.copyWith(fontSize: 12),
            ),
            Text(
              '$videoCount videos',
              style: PhlioTypography.caption
                  .copyWith(fontSize: 10, color: PhlioColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
