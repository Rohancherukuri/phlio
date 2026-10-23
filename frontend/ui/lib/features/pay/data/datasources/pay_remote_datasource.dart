import '../../../../core/network/api_client.dart';

class PayRemoteDataSource {
  const PayRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> overview() async {
    final response = await _apiClient.dio.get('/pay/overview');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> transactions({String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/pay/transactions',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendMoney({
    required String counterparty,
    required int amountMinorUnits,
    required String note,
  }) async {
    final response = await _apiClient.dio.post(
      '/pay/transactions',
      data: {
        'counterparty': counterparty,
        'amount_minor_units': amountMinorUnits,
        'note': note,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createSplit({
    required int totalMinorUnits,
    required List<String> participantNames,
    required String note,
  }) async {
    final response = await _apiClient.dio.post(
      '/pay/splits',
      data: {
        'total_minor_units': totalMinorUnits,
        'participant_names': participantNames,
        'note': note,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> splits({String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/pay/splits',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return response.data as Map<String, dynamic>;
  }
}
