// Home screen — mirrors the reference "2. HOME" screen: greeting, search
// bar, quick actions grid, the Phlio Agent prompt card, and horizontal
// "For you" strips pulled from Rooms and Shop.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../domain/entities/quick_action_entity.dart';
import '../controllers/home_controller.dart';
import '../widgets/quick_action_grid.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _handleQuickAction(BuildContext context, QuickActionEntity action) {
    if (!action.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${action.label} is coming soon.')),
      );
      return;
    }
    switch (action.kind) {
      case QuickActionKind.shop:
        context.go('/shop');
      case QuickActionKind.social:
        context.go('/social');
      case QuickActionKind.rooms:
        context.go('/rooms');
      case QuickActionKind.agent:
        context.go('/agent');
      case QuickActionKind.pay:
      case QuickActionKind.book:
      case QuickActionKind.stream:
      case QuickActionKind.news:
        break; // unreachable: these are always `isAvailable: false` today
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(homeOverviewProvider);
    return Scaffold(
      body: SafeArea(
        child: overviewAsync.when(
          loading: () => const _HomeLoadingSkeleton(),
          error: (error, _) => PhlioErrorView(
            failure: error is Failure ? error : const Failure.unknown(),
            onRetry: () => ref.invalidate(homeOverviewProvider),
          ),
          data: (overview) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(homeOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.all(PhlioSpacing.lg),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Good morning,', style: PhlioTypography.body),
                          Text('${overview.greetingName} 👋',
                              style: PhlioTypography.displayMedium),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () {},
                    ),
                    GestureDetector(
                      onTap: () =>
                          ref.read(authControllerProvider.notifier).logout(),
                      child: const Icon(Icons.logout_rounded,
                          color: PhlioColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: PhlioSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.md),
                  decoration: BoxDecoration(
                    color: PhlioColors.surfaceInput,
                    borderRadius: PhlioRadii.lgRadius,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          color: PhlioColors.textMuted, size: 20),
                      const SizedBox(width: PhlioSpacing.sm),
                      Text('What are you looking for?',
                          style: PhlioTypography.body),
                    ],
                  ),
                ),
                const SizedBox(height: PhlioSpacing.xl),
                QuickActionGrid(
                  actions: overview.quickActions,
                  onTap: (action) => _handleQuickAction(context, action),
                ),
                const SizedBox(height: PhlioSpacing.xl),
                PhlioCard(
                  onTap: () => context.go('/agent'),
                  child: Row(
                    children: [
                      const Hero(
                          tag: 'phlio-agent-fox', child: PhlioFox(size: 56)),
                      const SizedBox(width: PhlioSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Want me to plan tonight?',
                                style: PhlioTypography.bodyStrong),
                            Text('Movies, food, or something new?',
                                style: PhlioTypography.caption),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: PhlioColors.textMuted),
                    ],
                  ),
                ),
                const SizedBox(height: PhlioSpacing.xl),
                PhlioSectionHeader(
                  title: 'Rooms for you',
                  actionLabel: 'See all',
                  onAction: () => context.go('/rooms'),
                ),
                const SizedBox(height: PhlioSpacing.md),
                for (final room in overview.featuredRooms) ...[
                  PhlioCard(
                    onTap: () => context.push('/rooms/${room.id}'),
                    child: Row(
                      children: [
                        Text(room.icon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: PhlioSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(room.name,
                                  style: PhlioTypography.bodyStrong),
                              Text('${room.memberCount} members',
                                  style: PhlioTypography.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PhlioSpacing.sm),
                ],
                const SizedBox(height: PhlioSpacing.lg),
                PhlioSectionHeader(
                  title: 'From Phlio Shop',
                  actionLabel: 'See all',
                  onAction: () => context.go('/shop'),
                ),
                const SizedBox(height: PhlioSpacing.md),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: overview.featuredProducts.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: PhlioSpacing.md),
                    itemBuilder: (context, index) {
                      final product = overview.featuredProducts[index];
                      return Container(
                        width: 130,
                        padding: const EdgeInsets.all(PhlioSpacing.md),
                        decoration: BoxDecoration(
                          color: PhlioColors.surface,
                          borderRadius: PhlioRadii.lgRadius,
                          border: Border.all(color: PhlioColors.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Hero(
                                tag: 'product-image-${product.id}',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color:
                                        PhlioColors.domainArt.withOpacity(0.3),
                                    borderRadius: PhlioRadii.mdRadius,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: PhlioSpacing.xs),
                            Text(
                              product.title,
                              style: PhlioTypography.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              product.displayPrice,
                              style: PhlioTypography.caption
                                  .copyWith(color: PhlioColors.brandOrange),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: PhlioSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A skeleton that mirrors the real layout's shape (greeting bar, search
/// bar, quick-action grid, a room list, a product strip) — replacing the
/// previous plain spinner so the very first screen someone sees after
/// login already feels like "the app," not a loading interstitial.
class _HomeLoadingSkeleton extends StatelessWidget {
  const _HomeLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PhlioSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PhlioShimmer(width: 160, height: 28),
          const SizedBox(height: PhlioSpacing.lg),
          PhlioShimmer(height: 48, borderRadius: PhlioRadii.lgRadius),
          const SizedBox(height: PhlioSpacing.xl),
          const ShimmerGrid(crossAxisCount: 4, itemCount: 8, aspectRatio: 0.8),
          const SizedBox(height: PhlioSpacing.xl),
          PhlioShimmer(height: 72, borderRadius: PhlioRadii.xlRadius),
          const SizedBox(height: PhlioSpacing.xl),
          const ShimmerList(itemCount: 2, itemHeight: 64),
        ],
      ),
    );
  }
}
