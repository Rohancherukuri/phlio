import '../../../authentication/presentation/controllers/auth_controller.dart';
// Book feature state management (Riverpod).
//
// `ListingsController` mirrors `ProductsController` in the shop feature:
// an `AsyncNotifier` that re-runs whenever the selected category changes.
// `MyBookingsController` is a plain `FutureProvider` — the bookings list is
// read-only here and invalidated after every successful booking.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/book_entities.dart';
import '../../domain/repositories/book_repository.dart';
import '../../domain/usecases/book_usecases.dart';

final bookRepositoryProvider = Provider<BookRepository>((ref) => getIt<BookRepository>());

final selectedBookCategoryProvider = StateProvider<BookCategory?>((ref) => null);

final listingsControllerProvider =
    AsyncNotifierProvider<ListingsController, List<BookListingEntity>>(
  ListingsController.new,
);

class ListingsController extends AsyncNotifier<List<BookListingEntity>> {
  @override
  Future<List<BookListingEntity>> build() async {
    ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
    final repository = ref.read(bookRepositoryProvider);
    final useCase = BrowseListingsUseCase(repository);

    // Re-run automatically whenever the category filter changes.
    final category = ref.watch(selectedBookCategoryProvider);
    // The catalogue spans many verticals: load every page (100 per page).
    final items = <BookListingEntity>[];
    final seen = <String>{};
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final result = await useCase(category: category, cursor: cursor);
      final data = result.when(
          success: (value) => value, failure: (failure) => throw failure);
      for (final item in data.items) {
        if (seen.add(item.id)) items.add(item);
      }
      if (!data.hasMore || data.nextCursor == null || data.nextCursor == cursor) {
        break;
      }
      cursor = data.nextCursor;
    }
    return items;
  }
}

final myBookingsProvider = FutureProvider.autoDispose<List<BookingEntity>>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final repository = ref.watch(bookRepositoryProvider);
  final result = await repository.myBookings();
  return result.when(success: (page) => page.items, failure: (failure) => throw failure);
});
