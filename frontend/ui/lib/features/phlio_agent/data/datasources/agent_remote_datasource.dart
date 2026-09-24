// Talks to `/api/v1/agent/*`.

import '../../../../core/network/api_client.dart';
import '../models/agent_message_model.dart';

class AgentRemoteDataSource {
  const AgentRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<AgentMessageModel> sendMessage({required String text, String? conversationId}) async {
    final response = await _apiClient.dio.post(
      '/agent/messages',
      data: {'text': text, if (conversationId != null) 'conversation_id': conversationId},
    );
    return AgentMessageModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<AgentMessageModel>> getConversation(String conversationId) async {
    final response = await _apiClient.dio.get('/agent/conversations/$conversationId/messages');
    return (response.data as List<dynamic>)
        .map((json) => AgentMessageModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
