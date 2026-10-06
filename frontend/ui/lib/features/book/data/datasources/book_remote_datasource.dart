import '../../../../core/network/api_client.dart';

class BookRemoteDataSource {
  const BookRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> browseListings({
    String? category,
    int? maxPriceMinorUnits,
    String? cursor,
  }) async {
    final response = await _apiClient.dio.get(
      '/book/listings',
      queryParameters: {
        if (category != null) 'category': category,
        if (maxPriceMinorUnits != null) 'max_price_minor_units': maxPriceMinorUnits,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createBooking({
    required String listingId,
    required DateTime date,
    DateTime? time,
    required int participants,
  }) async {
    final response = await _apiClient.dio.post(
      '/book/bookings',
      data: {
        'listing_id': listingId,
        'date': date.toIso8601String().substring(0, 10),
        if (time != null)
          'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        'participants': participants,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> myBookings({String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/book/bookings',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return response.data as Map<String, dynamic>;
  }
}
