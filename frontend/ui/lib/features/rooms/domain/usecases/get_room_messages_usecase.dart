import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/room_message_entity.dart';
import '../repositories/rooms_repository.dart';

class GetRoomMessagesUseCase {
  const GetRoomMessagesUseCase(this._repository);

  final RoomsRepository _repository;

  Future<Result<PaginatedResponse<RoomMessageEntity>>> call(String roomId, {String? cursor}) {
    return _repository.getMessages(roomId, cursor: cursor);
  }
}
