import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/book_entities.dart';
import '../repositories/book_repository.dart';

class BrowseListingsUseCase {
  const BrowseListingsUseCase(this._repository);

  final BookRepository _repository;

  Future<Result<PaginatedResponse<BookListingEntity>>> call({
    BookCategory? category,
    int? maxPriceMinorUnits,
    String? cursor,
  }) {
    return _repository.browseListings(
      category: category,
      maxPriceMinorUnits: maxPriceMinorUnits,
      cursor: cursor,
    );
  }
}

class CreateBookingUseCase {
  const CreateBookingUseCase(this._repository);

  final BookRepository _repository;

  Future<Result<BookingEntity>> call({
    required String listingId,
    required DateTime date,
    DateTime? time,
    int participants = 1,
  }) {
    return _repository.createBooking(
      listingId: listingId,
      date: date,
      time: time,
      participants: participants,
    );
  }
}

class MyBookingsUseCase {
  const MyBookingsUseCase(this._repository);

  final BookRepository _repository;

  Future<Result<PaginatedResponse<BookingEntity>>> call({String? cursor}) {
    return _repository.myBookings(cursor: cursor);
  }
}
