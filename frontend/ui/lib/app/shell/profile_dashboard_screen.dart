// Profile dashboard — content statistics, opened from the profile page's
// dashboard card (Instagram-style "Your dashboard").
//
// Post counts come from the live feed (the user's own posts); view/like
// totals are seeded demo numbers until the analytics pipeline exists —
// labelled as such so nothing pretends to be measured.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/colors.dart';
import '../../../design_system/radii.dart';
import '../../../design_system/spacing.dart';
import '../../../design_system/typography.dart';
import '../../../design_system/widgets/phlio_card.dart';
import '../../../features/social/presentation/controllers/feed_controller.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';

class ProfileDashboardScreen extends ConsumerWidget {
  const ProfileDashboardScreen({required this.postCount, super.key});

  final int postCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final feedAsync = ref.watch(feedControllerProvider);
    final totalLikes = (feedAsync.valueOrNull?.posts ?? [])
        .where((post) => post.authorId == user?.id)
        .fold<int>(0, (sum, post) => sum + post.likeCount);

    // Seeded 7-day views series (demo analytics).
    const dailyViews = [180, 240, 150, 310, 280, 340, 290];

    return Scaffold(
      appBar: AppBar(title: const Text('Your dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(PhlioSpacing.lg),
        children: [
          Text('Last 30 days', style: PhlioTypography.caption),
          const SizedBox(height: PhlioSpacing.md),
          Row(
            children: [
              _statCard('Views', '1.4K', PhlioColors.brandOrange, Icons.visibility_outlined),
              const SizedBox(width: PhlioSpacing.md),
              _statCard('Likes', '$totalLikes', PhlioColors.danger, Icons.favorite_outlined),
            ],
          ),
          const SizedBox(height: PhlioSpacing.md),
          Row(
            children: [
              _statCard('Followers', '252', PhlioColors.brandViolet, Icons.person_add_outlined),
              const SizedBox(width: PhlioSpacing.md),
              _statCard('Posts', '$postCount', PhlioColors.domainRooms, Icons.grid_view_outlined),
            ],
          ),
          const SizedBox(height: PhlioSpacing.xl),
          Text('Views this week', style: PhlioTypography.headline),
          const SizedBox(height: PhlioSpacing.md),
          PhlioCard(
            child: Column(
              children: [
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final view in dailyViews) ...[
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 120 * view / 340,
                            decoration: BoxDecoration(
                              gradient: PhlioColors.sunsetGradient,
                              borderRadius: PhlioRadii.smRadius,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: PhlioSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final day in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: PhlioTypography.caption,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: PhlioSpacing.lg),
          Text(
            'Deeper analytics (watch time, follower growth, top content) '
            'arrive with the analytics pipeline.',
            style: PhlioTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: PhlioCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label, style: PhlioTypography.caption),
              ],
            ),
            const SizedBox(height: PhlioSpacing.xs),
            Text(value, style: PhlioTypography.headline),
          ],
        ),
      ),
    );
  }
}
