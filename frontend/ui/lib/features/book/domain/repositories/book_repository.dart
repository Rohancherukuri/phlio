import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/book_entities.dart';

abstract interface class BookRepository {
  Future<Result<PaginatedResponse<BookListingEntity>>> browseListings({
    BookCategory? category,
    int? maxPriceMinorUnits,
    String? cursor,
  });

  Future<Result<BookingEntity>> createBooking({
    required String listingId,
    required DateTime date,
    DateTime? time,
    int participants,
  });

  Future<Result<PaginatedResponse<BookingEntity>>> myBookings({String? cursor});
}
