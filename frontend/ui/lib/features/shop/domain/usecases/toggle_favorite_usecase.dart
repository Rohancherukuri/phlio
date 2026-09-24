import '../../../../core/result/result.dart';
import '../entities/product_entity.dart';
import '../repositories/shop_repository.dart';

class ToggleFavoriteUseCase {
  const ToggleFavoriteUseCase(this._repository);

  final ShopRepository _repository;

  Future<Result<ProductEntity>> call(String productId) => _repository.toggleFavorite(productId);
}
