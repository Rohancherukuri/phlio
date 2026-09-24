import '../../../../core/result/result.dart';
import '../entities/agent_message_entity.dart';

abstract interface class AgentRepository {
  Future<Result<AgentMessageEntity>> sendMessage({required String text, String? conversationId});

  Future<Result<List<AgentMessageEntity>>> getConversation(String conversationId);
}
