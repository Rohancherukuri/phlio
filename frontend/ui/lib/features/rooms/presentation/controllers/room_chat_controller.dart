// Per-room chat state management (Riverpod).
//
// A `family` provider keyed by `roomId` — Riverpod creates and disposes a
// separate `RoomChatController` instance per room automatically, so
// switching between rooms never mixes up message lists.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../domain/entities/room_message_entity.dart';
import '../../domain/repositories/rooms_repository.dart';
import '../../domain/usecases/get_room_messages_usecase.dart';
import '../../domain/usecases/send_room_message_usecase.dart';
import '../../domain/usecases/toggle_message_reaction_usecase.dart';
import '../../domain/usecases/upload_room_files_usecase.dart';
import 'rooms_controller.dart';

final roomChatControllerProvider = AsyncNotifierProvider.family<
    RoomChatController, List<RoomMessageEntity>, String>(
  RoomChatController.new,
);

class RoomChatController
    extends FamilyAsyncNotifier<List<RoomMessageEntity>, String> {
  late final GetRoomMessagesUseCase _getMessagesUseCase;
  late final SendRoomMessageUseCase _sendMessageUseCase;
  late final UploadRoomFilesUseCase _uploadFilesUseCase;
  late final ToggleMessageReactionUseCase _toggleReactionUseCase;

  @override
  Future<List<RoomMessageEntity>> build(String roomId) async {
    final repository = ref.read(roomsRepositoryProvider);
    _getMessagesUseCase = GetRoomMessagesUseCase(repository);
    _sendMessageUseCase = SendRoomMessageUseCase(repository);
    _uploadFilesUseCase = UploadRoomFilesUseCase(repository);
    _toggleReactionUseCase = ToggleMessageReactionUseCase(repository);

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

  /// Uploads the picked files (streamed from disk — large documents are
  /// fine), then posts the message carrying their attachment metadata.
  Future<Result<void>> sendFiles({
    required String text,
    required List<String> filePaths,
    List<OutgoingAttachment> extraAttachments = const [],
  }) async {
    var attachments = extraAttachments;
    if (filePaths.isNotEmpty) {
      final uploaded =
          await _uploadFilesUseCase(roomId: arg, filePaths: filePaths);
      final uploadedAttachments = uploaded.when(
        success: (list) => list,
        failure: (failure) => null,
      );
      if (uploadedAttachments == null) {
        return Result.failure(uploaded.when(
          success: (_) => const Failure.unknown(),
          failure: (failure) => failure,
        ));
      }
      attachments = [...uploadedAttachments, ...extraAttachments];
    }

    final result = await _sendMessageUseCase(
      roomId: arg,
      text: text,
      attachments: attachments,
    );
    return result.when(
      success: (message) {
        final current = state.valueOrNull ?? [];
        state = AsyncData([...current, message]);
        return const Result.success(null);
      },
      failure: (failure) => Result.failure(failure),
    );
  }

  /// Toggles a reaction (emoji glyph, Foxy sticker or GIF pack id) on a
  /// message and swaps the updated message into the list.
  Future<Result<void>> toggleReaction({
    required String messageId,
    required String kind,
    required String value,
  }) async {
    final result = await _toggleReactionUseCase(
      roomId: arg,
      messageId: messageId,
      kind: kind,
      value: value,
    );
    return result.when(
      success: (updated) {
        final current = state.valueOrNull ?? [];
        state = AsyncData([
          for (final message in current)
            if (message.id == updated.id) updated else message,
        ]);
        return const Result.success(null);
      },
      failure: (failure) => Result.failure(failure),
    );
  }
}
