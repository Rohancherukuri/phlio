// Tests for `ProductEntity` — specifically `displayPrice` (hand-rolled
// currency formatting, easy to get subtly wrong) and
// `toggleFavoritedOptimistically` (the optimistic-UI helper
// `ProductsController` depends on — see
// `features/shop/presentation/controllers/shop_controller.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/shop/domain/entities/product_entity.dart';

ProductEntity _buildProduct({
  int priceMinorUnits = 249900,
  String currency = 'INR',
  int favoriteCount = 3,
  bool favoritedByMe = false,
}) {
  return ProductEntity(
    id: 'prd_test',
    sellerId: 'sel_test',
    title: 'Test Product',
    description: 'A product used only in tests.',
    category: ShopCategory.artAndHandmade,
    condition: ProductCondition.handmade,
    priceMinorUnits: priceMinorUnits,
    currency: currency,
    imageUrls: const [],
    favoriteCount: favoriteCount,
    createdAt: DateTime(2026, 1, 1),
    favoritedByMe: favoritedByMe,
  );
}

void main() {
  group('displayPrice', () {
    test('formats whole-rupee paise amounts with a ₹ symbol and no decimals', () {
      final product = _buildProduct(priceMinorUnits: 249900); // ₹2,499.00
      expect(product.displayPrice, '₹2,499');
    });

    test('adds thousands separators for large amounts', () {
      final product = _buildProduct(priceMinorUnits: 80000 * 100); // ₹80,000
      expect(product.displayPrice, '₹80,000');
    });

    test('uses the currency code as a prefix for non-INR currencies', () {
      final product = _buildProduct(priceMinorUnits: 5000, currency: 'USD'); // $50.00
      expect(product.displayPrice, 'USD 50');
    });

    test('handles small amounts under 1,000 without a separator', () {
      final product = _buildProduct(priceMinorUnits: 49900); // ₹499
      expect(product.displayPrice, '₹499');
    });
  });

  group('toggleFavoritedOptimistically', () {
    test('flips favoritedByMe from false to true and increments the count', () {
      final product = _buildProduct(favoriteCount: 10, favoritedByMe: false);
      final toggled = product.toggleFavoritedOptimistically();
      expect(toggled.favoritedByMe, isTrue);
      expect(toggled.favoriteCount, 11);
    });

    test('flips favoritedByMe from true to false and decrements the count', () {
      final product = _buildProduct(favoriteCount: 10, favoritedByMe: true);
      final toggled = product.toggleFavoritedOptimistically();
      expect(toggled.favoritedByMe, isFalse);
      expect(toggled.favoriteCount, 9);
    });

    test('preserves every other field unchanged', () {
      final product = _buildProduct();
      final toggled = product.toggleFavoritedOptimistically();
      expect(toggled.id, product.id);
      expect(toggled.title, product.title);
      expect(toggled.priceMinorUnits, product.priceMinorUnits);
      expect(toggled.category, product.category);
    });
  });

  group('ShopCategory.fromApiValue', () {
    test('round-trips every category through its apiValue', () {
      for (final category in ShopCategory.values) {
        expect(ShopCategory.fromApiValue(category.apiValue), category);
      }
    });

    test('falls back to artAndHandmade for an unrecognized value', () {
      expect(ShopCategory.fromApiValue('not_a_real_category'), ShopCategory.artAndHandmade);
    });
  });
}
