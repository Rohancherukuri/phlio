import '../../../authentication/presentation/controllers/auth_controller.dart';
// Phlio Agent chat state management (Riverpod).
//
// Unlike the feed/rooms controllers, this one starts empty (no history to
// load on `build()` — conversations are ephemeral per-app-open in this
// build stage, matching the backend's short-term-only agent memory; see
// `backend/app/domains/agent/repository.py`) and grows as the user chats.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/agent_attachment_entity.dart';
import '../../domain/entities/agent_message_entity.dart';
import '../../domain/repositories/agent_repository.dart';
import '../../domain/usecases/send_agent_message_usecase.dart';
import 'agent_chats_controller.dart';

final agentRepositoryProvider = Provider<AgentRepository>((ref) => getIt<AgentRepository>());

final agentControllerProvider = AsyncNotifierProvider<AgentController, List<AgentMessageEntity>>(
  AgentController.new,
);

class AgentController extends AsyncNotifier<List<AgentMessageEntity>> {
  late SendAgentMessageUseCase _sendMessageUseCase;
  String? _conversationId;
  String? _chatId;

  /// The chat on screen (null for a fresh, not-yet-sent chat).
  String? get activeChatId => _chatId;

  @override
  Future<List<AgentMessageEntity>> build() async {
    ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
    _sendMessageUseCase = SendAgentMessageUseCase(ref.read(agentRepositoryProvider));
    _conversationId = null;
    _chatId = null;
    return [];
  }

  /// Clears the screen for a fresh conversation with Foxy.
  void newChat() {
    _chatId = null;
    _conversationId = null;
    state = const AsyncData([]);
  }

  /// Re-opens a previous chat from the history.
  void openChat(AgentChat chat) {
    _chatId = chat.id;
    _conversationId = chat.conversationId;
    state = AsyncData(chat.messages);
  }

  /// Called when a chat is deleted from the history.
  void forgetChat(String id) {
    if (_chatId == id) newChat();
  }

  /// Uploads files for the next message (see the composer's attach tray).
  Future<Result<List<AgentAttachmentEntity>>> uploadFiles(
    List<String> paths, {
    void Function(double progress)? onProgress,
  }) =>
      ref.read(agentRepositoryProvider).uploadFiles(paths, onProgress: onProgress);

  Future<Result<void>> sendMessage(
    String text, {
    List<AgentAttachmentEntity> attachments = const [],
  }) async {
    // Show the user's own message immediately — no need to wait on the
    // network for something that's purely local echo.
    final optimisticUserMessage = AgentMessageEntity(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: _conversationId ?? '',
      role: MessageRole.user,
      text: text,
      createdAt: DateTime.now(),
      attachments: attachments,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, optimisticUserMessage]);

    final result = await _sendMessageUseCase(
      text: text,
      conversationId: _conversationId,
      attachmentIds: [for (final a in attachments) a.id],
    );
    return result.when(
      success: (agentReply) {
        _conversationId = agentReply.conversationId;
        final messages = [...current, optimisticUserMessage, agentReply];
        state = AsyncData(messages);
        _chatId ??= 'chat-${DateTime.now().microsecondsSinceEpoch}';
        ref.read(agentChatsProvider.notifier).save(
              _chatId!,
              conversationId: _conversationId,
              messages: messages,
            );
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
