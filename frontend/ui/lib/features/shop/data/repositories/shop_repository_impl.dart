import 'package:dio/dio.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/seller_entity.dart';
import '../../domain/repositories/shop_repository.dart';
import '../datasources/shop_remote_datasource.dart';
import '../models/product_model.dart';

final _logger = createLogger('phlio.shop');

class ShopRepositoryImpl implements ShopRepository {
  const ShopRepositoryImpl(this._remoteDataSource);

  final ShopRemoteDataSource _remoteDataSource;

  @override
  Future<Result<PaginatedResponse<ProductEntity>>> browse({
    ShopCategory? category,
    int? maxPriceMinorUnits,
    String? cursor,
  }) async {
    try {
      final json = await _remoteDataSource.browse(
        category: category,
        maxPriceMinorUnits: maxPriceMinorUnits,
        cursor: cursor,
      );
      final page = PaginatedResponse<ProductEntity>.fromJson(
        json,
        (item) => ProductModel.fromJson(item).toEntity(),
      );
      return Result.success(page);
    } on DioException catch (e) {
      _logger.warning('shop.browse failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<ProductEntity>> toggleFavorite(String productId) async {
    try {
      final product = await _remoteDataSource.toggleFavorite(productId);
      return Result.success(product.toEntity());
    } on DioException catch (e) {
      _logger.warning('shop.toggle_favorite failed product_id=$productId', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<List<SellerEntity>>> featuredSellers() async {
    try {
      final sellers = await _remoteDataSource.featuredSellers();
      return Result.success(sellers.map((s) => s.toEntity()).toList());
    } on DioException catch (e) {
      _logger.warning('shop.featured_sellers failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
