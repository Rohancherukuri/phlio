// Per-room chat state management (Riverpod).
//
// A `family` provider keyed by `roomId` — Riverpod creates and disposes a
// separate `RoomChatController` instance per room automatically, so
// switching between rooms never mixes up message lists.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../domain/entities/room_message_entity.dart';
import '../../domain/usecases/get_room_messages_usecase.dart';
import '../../domain/usecases/send_room_message_usecase.dart';
import 'rooms_controller.dart';

final roomChatControllerProvider =
    AsyncNotifierProvider.family<RoomChatController, List<RoomMessageEntity>, String>(
  RoomChatController.new,
);

class RoomChatController extends FamilyAsyncNotifier<List<RoomMessageEntity>, String> {
  late final GetRoomMessagesUseCase _getMessagesUseCase;
  late final SendRoomMessageUseCase _sendMessageUseCase;

  @override
  Future<List<RoomMessageEntity>> build(String roomId) async {
    final repository = ref.read(roomsRepositoryProvider);
    _getMessagesUseCase = GetRoomMessagesUseCase(repository);
    _sendMessageUseCase = SendRoomMessageUseCase(repository);

    final result = await _getMessagesUseCase(roomId);
    return result.when(
      // Messages come back newest-first from the API; the chat UI wants
      // oldest-first (reading top to bottom), so reverse here once.
      success: (page) => page.items.reversed.toList(),
      failure: (failure) => throw failure,
    );
  }

  Future<Result<void>> sendMessage(String text) async {
    final result = await _sendMessageUseCase(roomId: arg, text: text);
    return result.when(
      success: (message) {
        final current = state.valueOrNull ?? [];
        state = AsyncData([...current, message]);
        return const Result.success(null);
      },
      failure: (failure) => Result.failure(failure),
    );
  }
}
