import '../../../../app/config/app_config.dart';
import 'package:phlio/shared/content/content_surface.dart';
// Product card — mirrors the reference "4. ART" screen's product grid:
// a square image area (placeholder gradient until real photography is
// wired up — see assets/images/README.md), an animated heart/favorite
// toggle, title, and price.

import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../domain/entities/product_entity.dart';

class ProductCard extends StatelessWidget {
  const ProductCard(
      {required this.product,
      required this.onToggleFavorite,
      super.key,
      this.onTap});

  final ProductEntity product;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onTap;

  /// Branded placeholder shots (`assets/images/placeholders/shop/`) until
  /// real seller photography exists. Picked deterministically from the
  /// product id so the same product always shows the same image.
  static const _placeholderImages = [
    'assets/images/placeholders/shop/product_lamp.png',
    'assets/images/placeholders/shop/product_painting.png',
    'assets/images/placeholders/shop/product_lantern.png',
    'assets/images/placeholders/shop/product_ceramics.png',
    'assets/images/placeholders/shop/product_jewelry.png',
    'assets/images/placeholders/shop/product_print.png',
  ];

  String get _image =>
      _placeholderImages[product.id.hashCode.abs() % _placeholderImages.length];

  @override
  Widget build(BuildContext context) {
    return ContentSurface(
        platform: 'shop', contentId: product.id, child: _content(context));
  }

  Widget _content(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: PhlioRadii.xlRadius,
      child: InkWell(
        borderRadius: PhlioRadii.xlRadius,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: PhlioRadii.xlRadius,
                    child: product.imageUrls.isNotEmpty
                        ? Image.network(
                            AppConfig.mediaUrl(product.imageUrls.first),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Image.asset(_image, fit: BoxFit.cover))
                        : Image.asset(
                            _image,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                borderRadius: PhlioRadii.xlRadius,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    PhlioColors.domainArt
                                        .withValues(alpha: 0.55),
                                    PhlioColors.brandOrange
                                        .withValues(alpha: 0.35),
                                  ],
                                ),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.image_outlined,
                                  color: Colors.white70, size: 28),
                            ),
                          ),
                  ),
                  Positioned(
                    top: PhlioSpacing.sm,
                    right: PhlioSpacing.sm,
                    child: _AnimatedFavoriteButton(
                      isFavorited: product.favoritedByMe,
                      onTap: onToggleFavorite,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PhlioSpacing.sm),
            Text(
              product.title,
              style: PhlioTypography.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(product.displayPrice,
                    style: PhlioTypography.label
                        .copyWith(color: PhlioColors.brandOrange)),
                const Icon(Icons.shopping_bag_outlined,
                    size: 16, color: PhlioColors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small heart button with a "pop" bounce on toggle — implicit animation
/// only (`TweenAnimationBuilder`), no animation controller to manage, so
/// it's cheap to drop into any list without lifecycle bookkeeping.
class _AnimatedFavoriteButton extends StatelessWidget {
  const _AnimatedFavoriteButton(
      {required this.isFavorited, required this.onTap});

  final bool isFavorited;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration:
            const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(isFavorited),
          tween: Tween(begin: 0.6, end: 1.0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Icon(
            isFavorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: 16,
            color: isFavorited ? PhlioColors.danger : Colors.white,
          ),
        ),
      ),
    );
  }
}
