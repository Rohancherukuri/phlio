// Phlio Shop screen — the universal marketplace (Phlio_Final_Product_Blueprint.md
// section 10). Visually mirrors the reference "4. ART" screen's layout
// (banner, category chips, featured sellers, product grid) since Art &
// Handmade is currently the only stocked category — the same layout
// generalizes cleanly to any other Shop category once it has data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../domain/entities/product_entity.dart';
import '../controllers/shop_controller.dart';
import '../widgets/product_card.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsControllerProvider);
    final sellersAsync = ref.watch(featuredSellersProvider);
    final selectedCategory = ref.watch(selectedShopCategoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Phlio Shop', style: PhlioTypography.displayMedium)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(productsControllerProvider);
          ref.invalidate(featuredSellersProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(PhlioSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(PhlioSpacing.xl),
              decoration: BoxDecoration(gradient: PhlioColors.brandGradientSoft, borderRadius: PhlioRadii.xxlRadius),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Art lives here.',
                          style: PhlioTypography.displayMedium.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: PhlioSpacing.xs),
                        Text(
                          'Real creators. Real stories. From art to everyday finds.',
                          style: PhlioTypography.body.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PhlioSpacing.xl),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  PhlioChipButton(
                    label: 'All',
                    selected: selectedCategory == null,
                    onPressed: () => ref.read(selectedShopCategoryProvider.notifier).state = null,
                  ),
                  const SizedBox(width: PhlioSpacing.sm),
                  for (final category in ShopCategory.values) ...[
                    PhlioChipButton(
                      label: category.label,
                      selected: selectedCategory == category,
                      onPressed: () => ref.read(selectedShopCategoryProvider.notifier).state = category,
                    ),
                    const SizedBox(width: PhlioSpacing.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: PhlioSpacing.xl),
            const PhlioSectionHeader(title: 'Featured sellers'),
            const SizedBox(height: PhlioSpacing.md),
            SizedBox(
              height: 88,
              child: sellersAsync.when(
                loading: () => const ShimmerRow(itemCount: 4, itemWidth: 64),
                error: (_, __) => const SizedBox.shrink(),
                data: (sellers) => ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: sellers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: PhlioSpacing.lg),
                  itemBuilder: (context, index) {
                    final seller = sellers[index];
                    return SizedBox(
                      width: 76,
                      child: Column(
                        children: [
                          PhlioAvatar(name: seller.displayName, size: 56),
                          const SizedBox(height: PhlioSpacing.xs),
                          Text(
                            seller.handle,
                            style: PhlioTypography.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: PhlioSpacing.xl),
            const PhlioSectionHeader(title: 'For you'),
            const SizedBox(height: PhlioSpacing.md),
            productsAsync.when(
              loading: () => const ShimmerGrid(crossAxisCount: 2, itemCount: 4, aspectRatio: 0.72),
              error: (error, _) => PhlioErrorView(
                failure: error is Failure ? error : const Failure.unknown(),
                onRetry: () => ref.invalidate(productsControllerProvider),
              ),
              data: (products) => products.isEmpty
                  ? _EmptyCategoryState(category: selectedCategory)
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: products.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: PhlioSpacing.lg,
                        crossAxisSpacing: PhlioSpacing.lg,
                        childAspectRatio: 0.72,
                      ),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ProductCard(
                          product: product,
                          onToggleFavorite: () =>
                              ref.read(productsControllerProvider.notifier).toggleFavorite(product.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCategoryState extends StatelessWidget {
  const _EmptyCategoryState({required this.category});

  final ShopCategory? category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PhlioSpacing.huge),
      child: Column(
        children: [
          const Icon(Icons.storefront_outlined, size: 36, color: PhlioColors.textMuted),
          const SizedBox(height: PhlioSpacing.md),
          Text(
            category == null ? 'Nothing here yet.' : 'No ${category!.label} listings yet.',
            style: PhlioTypography.body,
          ),
          const SizedBox(height: PhlioSpacing.xs),
          Text('Art & Handmade is the first category live on Phlio Shop.', style: PhlioTypography.caption),
        ],
      ),
    );
  }
}
