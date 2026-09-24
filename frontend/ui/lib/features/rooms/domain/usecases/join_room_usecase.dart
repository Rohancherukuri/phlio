import '../../../../core/result/result.dart';
import '../entities/room_entity.dart';
import '../repositories/rooms_repository.dart';

class JoinRoomUseCase {
  const JoinRoomUseCase(this._repository);

  final RoomsRepository _repository;

  Future<Result<RoomEntity>> call(String roomId) => _repository.joinRoom(roomId);
}
