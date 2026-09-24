import '../../domain/entities/product_entity.dart';

class ProductModel {
  const ProductModel({
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

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      sellerId: json['seller_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      category: ShopCategory.fromApiValue(json['category'] as String),
      condition: ProductCondition.fromApiValue(json['condition'] as String? ?? 'new'),
      priceMinorUnits: json['price_minor_units'] as int,
      currency: json['currency'] as String? ?? 'INR',
      imageUrls: (json['image_urls'] as List<dynamic>? ?? []).cast<String>(),
      favoriteCount: json['favorite_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      favoritedByMe: json['favorited_by_me'] as bool? ?? false,
    );
  }

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

  ProductEntity toEntity() => ProductEntity(
        id: id,
        sellerId: sellerId,
        title: title,
        description: description,
        category: category,
        condition: condition,
        priceMinorUnits: priceMinorUnits,
        currency: currency,
        imageUrls: imageUrls,
        favoriteCount: favoriteCount,
        createdAt: createdAt,
        favoritedByMe: favoritedByMe,
      );
}
