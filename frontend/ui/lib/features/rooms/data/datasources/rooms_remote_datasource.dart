// Talks to `/api/v1/rooms/*`.

import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/room_entity.dart';
import '../models/room_message_model.dart';
import '../models/room_model.dart';

class RoomsRemoteDataSource {
  const RoomsRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> discover(
      {RoomCategory? category, String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/rooms/discover',
      queryParameters: {
        if (category != null) 'category': category.apiValue,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<RoomModel>> myRooms() async {
    final response = await _apiClient.dio.get('/rooms/mine');
    return (response.data as List<dynamic>)
        .map((json) => RoomModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<RoomModel> createRoom({
    required String name,
    required String description,
    required RoomCategory category,
    required String icon,
  }) async {
    final response = await _apiClient.dio.post(
      '/rooms',
      data: {
        'name': name,
        'description': description,
        'category': category.apiValue,
        'icon': icon
      },
    );
    return RoomModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<RoomModel> joinRoom(String roomId) async {
    final response = await _apiClient.dio.post('/rooms/$roomId/join');
    return RoomModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getMessages(String roomId,
      {String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/rooms/$roomId/messages',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<RoomMessageModel> sendMessage({
    required String roomId,
    required String text,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final response = await _apiClient.dio.post(
      '/rooms/$roomId/messages',
      data: {
        'text': text,
        if (attachments.isNotEmpty) 'attachments': attachments
      },
    );
    return RoomMessageModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Uploads files for a message. Dio streams each part from disk, so
  /// multi-hundred-MB documents upload without ballooning memory.
  Future<List<Map<String, dynamic>>> uploadFiles({
    required String roomId,
    required List<String> filePaths,
  }) async {
    final form = FormData();
    for (final path in filePaths) {
      form.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(path,
            filename: path.split(Platform.pathSeparator).last),
      ));
    }
    final response =
        await _apiClient.dio.post('/rooms/$roomId/files', data: form);
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Toggles the current user's reaction on a message and returns the
  /// updated message.
  Future<RoomMessageModel> toggleReaction({
    required String roomId,
    required String messageId,
    required String kind,
    required String value,
  }) async {
    final response = await _apiClient.dio.post(
      '/rooms/$roomId/messages/$messageId/reactions',
      data: {'kind': kind, 'value': value},
    );
    return RoomMessageModel.fromJson(response.data as Map<String, dynamic>);
  }
}
