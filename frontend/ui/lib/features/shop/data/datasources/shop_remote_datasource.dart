// Talks to `/api/v1/shop/*`.

import '../../../../core/network/api_client.dart';
import '../../domain/entities/product_entity.dart';
import '../models/product_model.dart';
import '../models/seller_model.dart';

class ShopRemoteDataSource {
  const ShopRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> browse({
    ShopCategory? category,
    int? maxPriceMinorUnits,
    String? cursor,
  }) async {
    final response = await _apiClient.dio.get(
      '/shop/products',
      queryParameters: {
        if (category != null) 'category': category.apiValue,
        if (maxPriceMinorUnits != null) 'max_price_minor_units': maxPriceMinorUnits,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<ProductModel> toggleFavorite(String productId) async {
    final response = await _apiClient.dio.post('/shop/products/$productId/favorite');
    return ProductModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<SellerModel>> featuredSellers() async {
    final response = await _apiClient.dio.get('/shop/sellers/featured');
    return (response.data as List<dynamic>)
        .map((json) => SellerModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
