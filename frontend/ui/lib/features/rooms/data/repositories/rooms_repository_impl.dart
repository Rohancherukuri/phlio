import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../../domain/entities/room_entity.dart';
import '../../domain/entities/room_message_entity.dart';
import '../../domain/repositories/rooms_repository.dart';
import '../datasources/rooms_remote_datasource.dart';
import '../models/room_message_model.dart';
import '../models/room_model.dart';

class RoomsRepositoryImpl implements RoomsRepository {
  const RoomsRepositoryImpl(this._remoteDataSource);

  final RoomsRemoteDataSource _remoteDataSource;

  @override
  Future<Result<PaginatedResponse<RoomEntity>>> discover(
      {RoomCategory? category, String? cursor}) async {
    try {
      final json =
          await _remoteDataSource.discover(category: category, cursor: cursor);
      final page = PaginatedResponse<RoomEntity>.fromJson(
          json, (item) => RoomModel.fromJson(item).toEntity());
      return Result.success(page);
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<List<RoomEntity>>> myRooms() async {
    try {
      final rooms = await _remoteDataSource.myRooms();
      return Result.success(rooms.map((r) => r.toEntity()).toList());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<RoomEntity>> createRoom({
    required String name,
    required String description,
    required RoomCategory category,
    required String icon,
  }) async {
    try {
      final room = await _remoteDataSource.createRoom(
        name: name,
        description: description,
        category: category,
        icon: icon,
      );
      return Result.success(room.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<RoomEntity>> joinRoom(String roomId) async {
    try {
      final room = await _remoteDataSource.joinRoom(roomId);
      return Result.success(room.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<PaginatedResponse<RoomMessageEntity>>> getMessages(
      String roomId,
      {String? cursor}) async {
    try {
      final json = await _remoteDataSource.getMessages(roomId, cursor: cursor);
      final page = PaginatedResponse<RoomMessageEntity>.fromJson(
        json,
        (item) => RoomMessageModel.fromJson(item).toEntity(),
      );
      return Result.success(page);
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<RoomMessageEntity>> sendMessage({
    required String roomId,
    required String text,
    List<OutgoingAttachment> attachments = const [],
  }) async {
    try {
      final message = await _remoteDataSource.sendMessage(
        roomId: roomId,
        text: text,
        attachments: [for (final a in attachments) a.toJson()],
      );
      return Result.success(message.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<List<OutgoingAttachment>>> uploadFiles({
    required String roomId,
    required List<String> filePaths,
  }) async {
    try {
      final uploaded = await _remoteDataSource.uploadFiles(
          roomId: roomId, filePaths: filePaths);
      return Result.success([
        for (final a in uploaded)
          OutgoingAttachment(
            kind: a['kind'] as String? ?? 'document',
            name: a['name'] as String? ?? 'file',
            size: (a['size'] as num?)?.toInt() ?? 0,
            mime: a['mime'] as String? ?? '',
            url: a['url'] as String? ?? '',
            value: a['value'] as String? ?? '',
          ),
      ]);
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<RoomMessageEntity>> toggleReaction({
    required String roomId,
    required String messageId,
    required String kind,
    required String value,
  }) async {
    try {
      final message = await _remoteDataSource.toggleReaction(
        roomId: roomId,
        messageId: messageId,
        kind: kind,
        value: value,
      );
      return Result.success(message.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
