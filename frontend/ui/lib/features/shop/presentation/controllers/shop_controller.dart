// Shop marketplace state management (Riverpod).
//
// `ProductsController` is an `AsyncNotifier` (not a plain `FutureProvider`)
// specifically because it needs to mutate its own cached list for
// optimistic favorite-toggling — the same reasoning as
// `features/social/presentation/controllers/feed_controller.dart`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/seller_entity.dart';
import '../../domain/repositories/shop_repository.dart';
import '../../domain/usecases/browse_products_usecase.dart';
import '../../domain/usecases/toggle_favorite_usecase.dart';

final shopRepositoryProvider = Provider<ShopRepository>((ref) => getIt<ShopRepository>());

final selectedShopCategoryProvider = StateProvider<ShopCategory?>((ref) => null);

final productsControllerProvider = AsyncNotifierProvider<ProductsController, List<ProductEntity>>(
  ProductsController.new,
);

class ProductsController extends AsyncNotifier<List<ProductEntity>> {
  late final BrowseProductsUseCase _browseUseCase;
  late final ToggleFavoriteUseCase _toggleFavoriteUseCase;

  @override
  Future<List<ProductEntity>> build() async {
    final repository = ref.read(shopRepositoryProvider);
    _browseUseCase = BrowseProductsUseCase(repository);
    _toggleFavoriteUseCase = ToggleFavoriteUseCase(repository);

    // Re-run automatically whenever the category filter changes.
    final category = ref.watch(selectedShopCategoryProvider);
    final result = await _browseUseCase(category: category);
    return result.when(success: (page) => page.items, failure: (failure) => throw failure);
  }

  Future<void> toggleFavorite(String productId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final optimistic = [
      for (final p in current)
        if (p.id == productId) p.toggleFavoritedOptimistically() else p,
    ];
    state = AsyncData(optimistic);

    final result = await _toggleFavoriteUseCase(productId);
    result.when(
      success: (server) {
        final reconciled = [
          for (final p in optimistic)
            if (p.id == productId) server else p,
        ];
        state = AsyncData(reconciled);
      },
      failure: (_) => state = AsyncData(current),
    );
  }
}

final featuredSellersProvider = FutureProvider.autoDispose<List<SellerEntity>>((ref) async {
  final repository = ref.watch(shopRepositoryProvider);
  final result = await repository.featuredSellers();
  return result.when(success: (sellers) => sellers, failure: (failure) => throw failure);
});
