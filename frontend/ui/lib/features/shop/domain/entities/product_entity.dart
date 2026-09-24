// Framework-agnostic domain entity for a Phlio Shop product.
//
// `ShopCategory` mirrors the full category set from
// Phlio_Final_Product_Blueprint.md section 10 — only `artAndHandmade` has
// real seeded data in this build stage (see backend/app/core/seed.py),
// but the model is the general Shop shape from day one so adding a second
// category later is additive, not a rewrite.

import 'package:equatable/equatable.dart';

enum ShopCategory {
  fashion('fashion', 'Fashion'),
  foodAndGrocery('food_and_grocery', 'Food & Grocery'),
  pharmaAndWellness('pharma_and_wellness', 'Pharma & Wellness'),
  electronics('electronics', 'Electronics'),
  homeAndLiving('home_and_living', 'Home & Living'),
  artAndHandmade('art_and_handmade', 'Art & Handmade'),
  sportsAndFitness('sports_and_fitness', 'Sports & Fitness'),
  booksAndEducation('books_and_education', 'Books & Education'),
  beautyAndPersonalCare('beauty_and_personal_care', 'Beauty & Personal Care'),
  toysAndGames('toys_and_games', 'Toys & Games'),
  automotive('automotive', 'Automotive'),
  petSupplies('pet_supplies', 'Pet Supplies'),
  digitalProducts('digital_products', 'Digital Products');

  const ShopCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ShopCategory fromApiValue(String value) =>
      ShopCategory.values.firstWhere((c) => c.apiValue == value, orElse: () => ShopCategory.artAndHandmade);
}

enum ProductCondition {
  newItem('new', 'New'),
  likeNew('like_new', 'Like New'),
  good('good', 'Good'),
  used('used', 'Used'),
  refurbished('refurbished', 'Refurbished'),
  handmade('handmade', 'Handmade'),
  customMade('custom_made', 'Custom Made');

  const ProductCondition(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ProductCondition fromApiValue(String value) => ProductCondition.values
      .firstWhere((c) => c.apiValue == value, orElse: () => ProductCondition.newItem);
}

class ProductEntity extends Equatable {
  const ProductEntity({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.description,
    required this.category,
    required this.condition,
    required this.priceMinorUnits,
    required this.currency,
    required this.imageUrls,
    required this.favoriteCount,
    required this.createdAt,
    required this.favoritedByMe,
  });

  final String id;
  final String sellerId;
  final String title;
  final String description;
  final ShopCategory category;
  final ProductCondition condition;
  final int priceMinorUnits;
  final String currency;
  final List<String> imageUrls;
  final int favoriteCount;
  final DateTime createdAt;
  final bool favoritedByMe;

  /// Formats [priceMinorUnits] as a display price, e.g. `2_499_00` (paise)
  /// with currency `INR` -> `"₹2,499"`. Kept deliberately simple (no
  /// `intl` dependency) since Phlio currently only prices in INR;
  /// reach for `NumberFormat.currency` here if/when multi-currency ships.
  String get displayPrice {
    final majorUnits = priceMinorUnits / 100;
    final symbol = currency == 'INR' ? '₹' : '$currency ';
    final formatted = majorUnits
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '$symbol$formatted';
  }

  ProductEntity toggleFavoritedOptimistically() {
    return ProductEntity(
      id: id,
      sellerId: sellerId,
      title: title,
      description: description,
      category: category,
      condition: condition,
      priceMinorUnits: priceMinorUnits,
      currency: currency,
      imageUrls: imageUrls,
      favoriteCount: favoritedByMe ? favoriteCount - 1 : favoriteCount + 1,
      createdAt: createdAt,
      favoritedByMe: !favoritedByMe,
    );
  }

  @override
  List<Object?> get props => [id, title, priceMinorUnits, favoriteCount, favoritedByMe];
}
