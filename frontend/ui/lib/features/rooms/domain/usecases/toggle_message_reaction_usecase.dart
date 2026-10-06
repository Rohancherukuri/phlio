import '../../../../core/result/result.dart';
import '../entities/room_message_entity.dart';
import '../repositories/rooms_repository.dart';

class ToggleMessageReactionUseCase {
  const ToggleMessageReactionUseCase(this._repository);

  final RoomsRepository _repository;

  Future<Result<RoomMessageEntity>> call({
    required String roomId,
    required String messageId,
    required String kind,
    required String value,
  }) {
    return _repository.toggleReaction(
      roomId: roomId,
      messageId: messageId,
      kind: kind,
      value: value,
    );
  }
}
