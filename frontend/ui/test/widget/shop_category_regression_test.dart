import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/result/result.dart';
import 'package:phlio/shared/models/paginated_response.dart';
import 'package:phlio/features/shop/domain/entities/product_entity.dart';
import 'package:phlio/features/shop/domain/repositories/shop_repository.dart';
import 'package:phlio/features/shop/presentation/controllers/shop_controller.dart';

class EmptyCatalog implements ShopRepository {
  final requested = <ShopCategory?>[];
  @override
  Future<Result<PaginatedResponse<ProductEntity>>> browse({ShopCategory? category, int? maxPriceMinorUnits, String? cursor}) async {
    requested.add(category);
    return const Result.success(PaginatedResponse(items: <ProductEntity>[], nextCursor: null, hasMore: false));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  test('Every Shop category can be selected repeatedly without a late initialization failure', () async {
    final catalog = EmptyCatalog();
    final container = ProviderContainer(overrides: [shopRepositoryProvider.overrideWithValue(catalog)]);
    addTearDown(container.dispose);
    await container.read(productsControllerProvider.future);
    for (final category in [...ShopCategory.values, ...ShopCategory.values.reversed]) {
      container.read(selectedShopCategoryProvider.notifier).state = category;
      expect(await container.read(productsControllerProvider.future), isEmpty);
    }
    expect(catalog.requested.toSet(), containsAll(ShopCategory.values));
  });
}
