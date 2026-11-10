import '../../../../core/result/result.dart';
import '../entities/agent_attachment_entity.dart';
import '../entities/agent_message_entity.dart';

abstract interface class AgentRepository {
  Future<Result<AgentMessageEntity>> sendMessage({
    required String text,
    String? conversationId,
    List<String> attachmentIds = const [],
  });

  Future<Result<List<AgentAttachmentEntity>>> uploadFiles(
    List<String> paths, {
    void Function(double progress)? onProgress,
  });

  Future<Result<List<AgentMessageEntity>>> getConversation(String conversationId);
}
