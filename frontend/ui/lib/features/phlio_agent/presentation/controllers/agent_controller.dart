// Phlio Agent chat state management (Riverpod).
//
// Unlike the feed/rooms controllers, this one starts empty (no history to
// load on `build()` — conversations are ephemeral per-app-open in this
// build stage, matching the backend's short-term-only agent memory; see
// `backend/app/domains/agent/repository.py`) and grows as the user chats.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/agent_message_entity.dart';
import '../../domain/repositories/agent_repository.dart';
import '../../domain/usecases/send_agent_message_usecase.dart';

final agentRepositoryProvider = Provider<AgentRepository>((ref) => getIt<AgentRepository>());

final agentControllerProvider = AsyncNotifierProvider<AgentController, List<AgentMessageEntity>>(
  AgentController.new,
);

class AgentController extends AsyncNotifier<List<AgentMessageEntity>> {
  late final SendAgentMessageUseCase _sendMessageUseCase;
  String? _conversationId;

  @override
  Future<List<AgentMessageEntity>> build() async {
    _sendMessageUseCase = SendAgentMessageUseCase(ref.read(agentRepositoryProvider));
    return [];
  }

  Future<Result<void>> sendMessage(String text) async {
    // Show the user's own message immediately — no need to wait on the
    // network for something that's purely local echo.
    final optimisticUserMessage = AgentMessageEntity(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: _conversationId ?? '',
      role: MessageRole.user,
      text: text,
      createdAt: DateTime.now(),
    );
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, optimisticUserMessage]);

    final result = await _sendMessageUseCase(text: text, conversationId: _conversationId);
    return result.when(
      success: (agentReply) {
        _conversationId = agentReply.conversationId;
        state = AsyncData([...current, optimisticUserMessage, agentReply]);
        return const Result.success(null);
      },
      failure: (failure) {
        // Roll back the optimistic user message so a failed send doesn't
        // leave a "sent" bubble the agent never actually saw.
        state = AsyncData(current);
        return Result.failure(failure);
      },
    );
  }
}
