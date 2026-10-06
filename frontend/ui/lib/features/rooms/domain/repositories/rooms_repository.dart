import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/room_entity.dart';
import '../entities/room_message_entity.dart';

/// Attachment metadata sent alongside a message (uploaded files carry the
/// url returned by the upload step; pack stickers/GIFs just a value id).
class OutgoingAttachment {
  const OutgoingAttachment({
    required this.kind,
    required this.name,
    this.size = 0,
    this.mime = '',
    this.url = '',
    this.value = '',
  });

  final String kind;
  final String name;
  final int size;
  final String mime;
  final String url;
  final String value;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'name': name,
        'size': size,
        'mime': mime,
        'url': url,
        'value': value,
      };
}

abstract interface class RoomsRepository {
  Future<Result<PaginatedResponse<RoomEntity>>> discover(
      {RoomCategory? category, String? cursor});

  Future<Result<List<RoomEntity>>> myRooms();

  Future<Result<RoomEntity>> createRoom({
    required String name,
    required String description,
    required RoomCategory category,
    required String icon,
  });

  Future<Result<RoomEntity>> joinRoom(String roomId);

  Future<Result<PaginatedResponse<RoomMessageEntity>>> getMessages(
      String roomId,
      {String? cursor});

  Future<Result<RoomMessageEntity>> sendMessage({
    required String roomId,
    required String text,
    List<OutgoingAttachment> attachments,
  });

  /// Uploads files and returns their server-side metadata (kind, name,
  /// size, url). Streams from disk, so large documents are fine.
  Future<Result<List<OutgoingAttachment>>> uploadFiles({
    required String roomId,
    required List<String> filePaths,
  });

  Future<Result<RoomMessageEntity>> toggleReaction({
    required String roomId,
    required String messageId,
    required String kind,
    required String value,
  });
}
