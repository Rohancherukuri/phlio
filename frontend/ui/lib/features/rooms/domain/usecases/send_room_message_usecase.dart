import '../../../../core/result/result.dart';
import '../entities/room_message_entity.dart';
import '../repositories/rooms_repository.dart';

class SendRoomMessageUseCase {
  const SendRoomMessageUseCase(this._repository);

  final RoomsRepository _repository;

  Future<Result<RoomMessageEntity>> call({
    required String roomId,
    required String text,
    List<OutgoingAttachment> attachments = const [],
  }) {
    return _repository.sendMessage(
        roomId: roomId, text: text, attachments: attachments);
  }
}
