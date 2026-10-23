import '../../../../core/result/result.dart';
import '../repositories/rooms_repository.dart';

class UploadRoomFilesUseCase {
  const UploadRoomFilesUseCase(this._repository);

  final RoomsRepository _repository;

  Future<Result<List<OutgoingAttachment>>> call({
    required String roomId,
    required List<String> filePaths,
  }) {
    return _repository.uploadFiles(roomId: roomId, filePaths: filePaths);
  }
}
