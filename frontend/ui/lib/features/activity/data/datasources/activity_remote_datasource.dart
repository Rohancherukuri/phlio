import '../../../../core/network/api_client.dart';

class ActivityRemoteDataSource {
  const ActivityRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> feed({String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/activity',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> markAllRead() async {
    await _apiClient.dio.post('/activity/read-all');
  }
}
