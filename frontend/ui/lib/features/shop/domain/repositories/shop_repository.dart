import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/product_entity.dart';
import '../entities/seller_entity.dart';

abstract interface class ShopRepository {
  Future<Result<PaginatedResponse<ProductEntity>>> browse({
    ShopCategory? category,
    int? maxPriceMinorUnits,
    String? cursor,
  });

  Future<Result<ProductEntity>> toggleFavorite(String productId);

  Future<Result<List<SellerEntity>>> featuredSellers();
}
