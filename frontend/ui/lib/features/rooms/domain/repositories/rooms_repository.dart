import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/room_entity.dart';
import '../entities/room_message_entity.dart';

abstract interface class RoomsRepository {
  Future<Result<PaginatedResponse<RoomEntity>>> discover({RoomCategory? category, String? cursor});

  Future<Result<List<RoomEntity>>> myRooms();

  Future<Result<RoomEntity>> createRoom({
    required String name,
    required String description,
    required RoomCategory category,
    required String icon,
  });

  Future<Result<RoomEntity>> joinRoom(String roomId);

  Future<Result<PaginatedResponse<RoomMessageEntity>>> getMessages(String roomId, {String? cursor});

  Future<Result<RoomMessageEntity>> sendMessage({required String roomId, required String text});
}
