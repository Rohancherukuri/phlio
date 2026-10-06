import 'package:dio/dio.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../../domain/entities/book_entities.dart';
import '../../domain/repositories/book_repository.dart';
import '../datasources/book_remote_datasource.dart';
import '../models/book_models.dart';

final _logger = createLogger('phlio.book');

class BookRepositoryImpl implements BookRepository {
  const BookRepositoryImpl(this._remoteDataSource);

  final BookRemoteDataSource _remoteDataSource;

  @override
  Future<Result<PaginatedResponse<BookListingEntity>>> browseListings({
    BookCategory? category,
    int? maxPriceMinorUnits,
    String? cursor,
  }) async {
    try {
      final json = await _remoteDataSource.browseListings(
        category: category?.name,
        maxPriceMinorUnits: maxPriceMinorUnits,
        cursor: cursor,
      );
      final page = PaginatedResponse<BookListingEntity>.fromJson(
        json,
        (item) => BookListingModel.fromJson(item).toEntity(),
      );
      return Result.success(page);
    } on DioException catch (e) {
      _logger.warning('book.browse_listings failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<BookingEntity>> createBooking({
    required String listingId,
    required DateTime date,
    DateTime? time,
    int participants = 1,
  }) async {
    try {
      final json = await _remoteDataSource.createBooking(
        listingId: listingId,
        date: date,
        time: time,
        participants: participants,
      );
      return Result.success(BookingModel.fromJson(json).toEntity());
    } on DioException catch (e) {
      _logger.warning('book.create_booking failed listing_id=$listingId', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<PaginatedResponse<BookingEntity>>> myBookings({String? cursor}) async {
    try {
      final json = await _remoteDataSource.myBookings(cursor: cursor);
      final page = PaginatedResponse<BookingEntity>.fromJson(
        json,
        (item) => BookingModel.fromJson(item).toEntity(),
      );
      return Result.success(page);
    } on DioException catch (e) {
      _logger.warning('book.my_bookings failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
