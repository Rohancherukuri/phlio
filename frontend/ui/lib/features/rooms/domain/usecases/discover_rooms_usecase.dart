import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/room_entity.dart';
import '../repositories/rooms_repository.dart';

class DiscoverRoomsUseCase {
  const DiscoverRoomsUseCase(this._repository);

  final RoomsRepository _repository;

  Future<Result<PaginatedResponse<RoomEntity>>> call(
      {RoomCategory? category, String? cursor}) {
    return _repository.discover(category: category, cursor: cursor);
  }
}
