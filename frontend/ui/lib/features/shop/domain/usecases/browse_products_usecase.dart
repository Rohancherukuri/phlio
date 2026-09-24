import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/product_entity.dart';
import '../repositories/shop_repository.dart';

class BrowseProductsUseCase {
  const BrowseProductsUseCase(this._repository);

  final ShopRepository _repository;

  Future<Result<PaginatedResponse<ProductEntity>>> call({
    ShopCategory? category,
    int? maxPriceMinorUnits,
    String? cursor,
  }) {
    return _repository.browse(category: category, maxPriceMinorUnits: maxPriceMinorUnits, cursor: cursor);
  }
}
