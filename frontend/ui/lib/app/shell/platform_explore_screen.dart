// The Explore tab, per platform. Each platform gets its own discovery
// surface built from the providers that already back its home screen —
// explore is the "browse and wander" counterpart to home's "your stuff":
//
//   Pay    -> balance + full transaction history
//   Social -> trending tags + recent posts grid
//   Rooms  -> category chips + community discovery
//   Book   -> category chips + browseable listings
//   Shop   -> category chips + full catalog
//   Agent  -> "Meet Foxy" capability overview
//   Stream/News -> coming soon

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/colors.dart';
import '../../design_system/radii.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_button.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../design_system/widgets/phlio_fox.dart';
import '../../features/book/domain/entities/book_entities.dart';
import '../../features/book/presentation/controllers/book_controller.dart';
import '../../features/book/presentation/widgets/listing_placeholder.dart';
import '../../features/pay/presentation/controllers/pay_controller.dart';
import '../../features/rooms/presentation/screens/rooms_explore_screen.dart';
import '../../features/social/presentation/widgets/social_explore_videos_view.dart';
import '../../features/shop/domain/entities/product_entity.dart';
import '../../features/shop/presentation/controllers/shop_controller.dart';
import '../../features/shop/presentation/widgets/product_card.dart';
import '../platform/phlio_platform.dart';
import 'platform_home_screen.dart' show switchPlatform;

class PlatformExploreScreen extends ConsumerWidget {
  const PlatformExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(currentPlatformProvider);

    return IndexedStack(
      index: platform.index,
      children: const [
        _PayExplore(),
        SafeArea(child: SocialExploreVideosView()),
        RoomsExploreScreen(),
        _BookExplore(),
        _ShopExplore(),
        _ComingSoonExplore(platform: PhlioPlatform.stream),
        _ComingSoonExplore(platform: PhlioPlatform.news),
        _AgentExplore(),
      ],
    );
  }
}

// -- Pay --------------------------------------------------------------------

class _PayExplore extends ConsumerWidget {
  const _PayExplore();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Explore Pay'),
            Text('All your money moves',
                style: PhlioTypography.caption.copyWith(height: 1.2)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(PhlioSpacing.lg),
        children: [
          walletAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Text('Could not load wallet.', style: PhlioTypography.body),
            data: (wallet) => Container(
              padding: const EdgeInsets.all(PhlioSpacing.lg),
              decoration: BoxDecoration(
                color: PhlioColors.surface,
                borderRadius: PhlioRadii.xlRadius,
                border: Border.all(color: PhlioColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Balance', style: PhlioTypography.label),
                        Text(wallet.displayBalance,
                            style: PhlioTypography.displayMedium),
                      ],
                    ),
                  ),
                  const PhlioFox(
                      size: 48, pose: PhlioFoxPose.coffee, animate: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: PhlioSpacing.xl),
          Text('Full history', style: PhlioTypography.headline),
          const SizedBox(height: PhlioSpacing.md),
          transactionsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(PhlioSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('Could not load transactions.',
                style: PhlioTypography.body),
            data: (transactions) {
              if (transactions.isEmpty) {
                return Text('No transactions yet.',
                    style: PhlioTypography.body);
              }
              return Column(
                children: [
                  for (final txn in transactions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: PhlioSpacing.sm),
                      child: PhlioCard(
                        padding: const EdgeInsets.all(PhlioSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(txn.counterparty,
                                      style: PhlioTypography.bodyStrong),
                                  if (txn.note.isNotEmpty)
                                    Text(
                                      txn.note,
                                      style: PhlioTypography.caption,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              txn.displayAmount,
                              style: PhlioTypography.bodyStrong.copyWith(
                                color: txn.isReceive
                                    ? PhlioColors.success
                                    : PhlioColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// -- Rooms --------------------------------------------------------------------

// -- Book ---------------------------------------------------------------------

class _BookExplore extends ConsumerWidget {
  const _BookExplore();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(listingsControllerProvider);
    final selectedCategory = ref.watch(selectedBookCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Explore Book'),
            Text('Places, events, experiences',
                style: PhlioTypography.caption.copyWith(height: 1.2)),
          ],
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
              children: [
                PhlioChipButton(
                  label: 'All',
                  selected: selectedCategory == null,
                  onPressed: () => ref
                      .read(selectedBookCategoryProvider.notifier)
                      .state = null,
                ),
                const SizedBox(width: PhlioSpacing.sm),
                for (final category in BookCategory.values) ...[
                  PhlioChipButton(
                    label: category.label,
                    selected: selectedCategory == category,
                    onPressed: () => ref
                        .read(selectedBookCategoryProvider.notifier)
                        .state = category,
                  ),
                  const SizedBox(width: PhlioSpacing.sm),
                ],
              ],
            ),
          ),
          Expanded(
            child: listingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('Could not load listings.',
                      style: PhlioTypography.body)),
              data: (listings) => ListView(
                padding: const EdgeInsets.all(PhlioSpacing.lg),
                children: [
                  if (listings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: PhlioSpacing.massive),
                      child: Column(
                        children: [
                          const PhlioFox(
                              size: 110, pose: PhlioFoxPose.explorer),
                          const SizedBox(height: PhlioSpacing.md),
                          Text('Nothing bookable here yet',
                              style: PhlioTypography.title),
                        ],
                      ),
                    ),
                  for (final listing in listings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
                      child: PhlioCard(
                        padding: const EdgeInsets.all(PhlioSpacing.lg),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: PhlioRadii.mdRadius,
                              child: Image.asset(
                                listingPlaceholderImage(listing),
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                              ),
                            ),
                            const SizedBox(width: PhlioSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(listing.title,
                                      style: PhlioTypography.bodyStrong),
                                  Text(listing.venue,
                                      style: PhlioTypography.caption),
                                ],
                              ),
                            ),
                            Text(
                              listing.displayPrice,
                              style: PhlioTypography.label.copyWith(
                                color: listing.isFree
                                    ? PhlioColors.success
                                    : PhlioColors.brandOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Shop ---------------------------------------------------------------------

class _ShopExplore extends ConsumerWidget {
  const _ShopExplore();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsControllerProvider);
    final selectedCategory = ref.watch(selectedShopCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Explore Shop'),
            Text('Discover what you love',
                style: PhlioTypography.caption.copyWith(height: 1.2)),
          ],
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
              children: [
                PhlioChipButton(
                  label: 'All',
                  selected: selectedCategory == null,
                  onPressed: () => ref
                      .read(selectedShopCategoryProvider.notifier)
                      .state = null,
                ),
                const SizedBox(width: PhlioSpacing.sm),
                for (final category in ShopCategory.values) ...[
                  PhlioChipButton(
                    label: category.label,
                    selected: selectedCategory == category,
                    onPressed: () => ref
                        .read(selectedShopCategoryProvider.notifier)
                        .state = category,
                  ),
                  const SizedBox(width: PhlioSpacing.sm),
                ],
              ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('Could not load products.',
                      style: PhlioTypography.body)),
              data: (products) => GridView.builder(
                padding: const EdgeInsets.all(PhlioSpacing.lg),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: PhlioSpacing.md,
                  crossAxisSpacing: PhlioSpacing.md,
                  childAspectRatio: 0.72,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) => ProductCard(
                  product: products[index],
                  onToggleFavorite: () => ref
                      .read(productsControllerProvider.notifier)
                      .toggleFavorite(products[index].id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Agent --------------------------------------------------------------------

class _AgentExplore extends StatelessWidget {
  const _AgentExplore();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Meet Foxy'),
            Text('More than an agent. A friend on your journey.',
                style: PhlioTypography.caption.copyWith(height: 1.2)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(PhlioSpacing.xl),
        children: [
          const Center(
              child: PhlioFoxAnimation(
                  size: 140, animation: PhlioFoxLoop.explore)),
          const SizedBox(height: PhlioSpacing.lg),
          const _CapabilityTile(
            icon: Icons.event_note_rounded,
            title: 'Plans with friends',
            body:
                'Tell Foxy the vibe and budget — get movie, dinner and hangout options.',
          ),
          const _CapabilityTile(
            icon: Icons.confirmation_number_rounded,
            title: 'Bookings',
            body: 'Reserve courts, tables and seats without leaving the chat.',
          ),
          const _CapabilityTile(
            icon: Icons.storefront_rounded,
            title: 'Shopping help',
            body: 'Find products within budget across Phlio Shop.',
          ),
          const _CapabilityTile(
            icon: Icons.currency_rupee_rounded,
            title: 'Split payments',
            body:
                'Prepare bill splits — you always confirm before money moves.',
          ),
          const SizedBox(height: PhlioSpacing.lg),
          PhlioPrimaryButton(
            label: 'Chat with Foxy',
            onPressed: () => switchPlatform(context, PhlioPlatform.agent),
          ),
          const SizedBox(height: PhlioSpacing.xxl),
        ],
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile(
      {required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
      child: PhlioCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PhlioColors.brandOrange.withValues(alpha: 0.14),
                borderRadius: PhlioRadii.mdRadius,
              ),
              child: Icon(icon, color: PhlioColors.brandOrange, size: 22),
            ),
            const SizedBox(width: PhlioSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PhlioTypography.bodyStrong),
                  Text(body, style: PhlioTypography.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Stream / News ------------------------------------------------------------

class _ComingSoonExplore extends StatelessWidget {
  const _ComingSoonExplore({required this.platform});

  final PhlioPlatform platform;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Explore ${platform.label}')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PhlioFox(size: 110, pose: PhlioFoxPose.sleepy),
            const SizedBox(height: PhlioSpacing.md),
            Text('${platform.label} is coming soon',
                style: PhlioTypography.headline),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              'Switch platforms from the tray meanwhile.',
              style: PhlioTypography.body,
            ),
          ],
        ),
      ),
    );
  }
}
