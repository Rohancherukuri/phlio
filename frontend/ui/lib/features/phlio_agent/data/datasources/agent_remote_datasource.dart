// Talks to `/api/v1/agent/*`.

import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/agent_attachment_entity.dart';
import '../models/agent_message_model.dart';

class AgentRemoteDataSource {
  const AgentRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<AgentMessageModel> sendMessage({
    required String text,
    String? conversationId,
    List<String> attachmentIds = const [],
  }) async {
    final response = await _apiClient.dio.post(
      '/agent/messages',
      data: {
        'text': text,
        if (conversationId != null) 'conversation_id': conversationId,
        if (attachmentIds.isNotEmpty) 'attachments': attachmentIds,
      },
    );
    return AgentMessageModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Uploads files for Foxy; returns them in the same order as [paths].
  Future<List<AgentAttachmentEntity>> uploadFiles(
    List<String> paths, {
    void Function(double progress)? onProgress,
  }) async {
    final form = FormData();
    for (final path in paths) {
      form.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(path, filename: path.split(RegExp(r'[\\/]')).last),
      ));
    }
    final response = await _apiClient.dio.post(
      '/agent/files',
      data: form,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) => onProgress(total > 0 ? sent / total : 0),
    );
    final list = response.data as List<dynamic>;
    return [
      for (var i = 0; i < list.length; i++)
        agentAttachmentFromJson(list[i] as Map<String, dynamic>,
            localPath: i < paths.length ? paths[i] : null),
    ];
  }

  Future<List<AgentMessageModel>> getConversation(String conversationId) async {
    final response = await _apiClient.dio.get('/agent/conversations/$conversationId/messages');
    return (response.data as List<dynamic>)
        .map((json) => AgentMessageModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
