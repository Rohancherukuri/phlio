import '../../../../core/result/result.dart';
import '../entities/agent_message_entity.dart';
import '../repositories/agent_repository.dart';

class SendAgentMessageUseCase {
  const SendAgentMessageUseCase(this._repository);

  final AgentRepository _repository;

  Future<Result<AgentMessageEntity>> call({required String text, String? conversationId}) {
    return _repository.sendMessage(text: text, conversationId: conversationId);
  }
}
