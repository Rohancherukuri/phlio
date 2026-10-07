import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';

final messagingApiProvider = Provider<MessagingApi>((ref) {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return MessagingApi(getIt<ApiClient>().dio);
});

class MessagingApi {
  MessagingApi(this.dio);
  final Dio dio;
  final Map<String, String> _files = {};

  Future<List<Map<String, dynamic>>> search(String query, String kind) async =>
      ((await dio.get(
        '/messaging/search',
        queryParameters: {'q': query, 'kind': kind},
      ))
              .data as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<List<Map<String, dynamic>>> friends() async =>
      ((await dio.get('/messaging/friends')).data as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<void> addFriend(String peer) async =>
      dio.post('/messaging/friends', data: {'peer': peer});
  Future<void> friendAction(String peer, String action) async =>
      dio.post('/messaging/friends/${Uri.encodeComponent(peer)}/$action');

  String peerPath(String peer) =>
      '/messaging/peers/${Uri.encodeComponent(peer)}';

  Future<Map<String, dynamic>> peer(String peer) async =>
      Map<String, dynamic>.from((await dio.get(peerPath(peer))).data as Map);

  Future<List<Map<String, dynamic>>> conversations() async =>
      ((await dio.get('/messaging/conversations')).data as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();

  Future<List<Map<String, dynamic>>> messages(
    String peer, {
    String? before,
  }) async =>
      ((await dio.get(
        '${peerPath(peer)}/messages',
        queryParameters: {'before': before},
      ))
              .data as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();

  Future<void> send(
    String peer,
    String text, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    await dio.post(
      '${peerPath(peer)}/messages',
      data: {'text': text, 'attachments': attachments},
    );
  }

  /// Instagram-style message reaction; the backend toggles the emoji for
  /// this user and returns the message's updated reaction list.
  Future<void> react(
    String peer,
    String messageId,
    String kind,
    String value,
  ) =>
      dio.post(
        '${peerPath(peer)}/messages/$messageId/reactions',
        data: {'kind': kind, 'value': value},
      );

  Future<List<Map<String, dynamic>>> upload(
    String peer,
    List<String> paths, {
    List<Map<String, dynamic>?> edits = const [],
  }) async {
    final parts = <MultipartFile>[];
    for (final path in paths) {
      parts.add(await MultipartFile.fromFile(path));
    }
    final response = await dio.post(
      '${peerPath(peer)}/files',
      data: FormData.fromMap({'files': parts, 'edits': jsonEncode(edits)}),
      options: Options(
        sendTimeout: const Duration(minutes: 3),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    return (response.data as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  Future<void> setOverlays(
    String peer,
    String id,
    List<Map<String, dynamic>> overlays,
  ) async {
    await dio.put(
      '${peerPath(peer)}/messages/$id/overlays',
      data: {'overlays': overlays},
    );
  }

  Future<List<Map<String, dynamic>>> creatorChat(String creator) async =>
      ((await dio.get('/social/creators/${Uri.encodeComponent(creator)}/chat'))
              .data as List)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
  Future<void> sendCreatorChat(
    String creator,
    String text,
    List<Map<String, dynamic>> attachments,
  ) async {
    await dio.post(
      '/social/creators/${Uri.encodeComponent(creator)}/chat',
      data: {'text': text, 'attachments': attachments},
    );
  }

  /// Private media is fetched through Dio so authentication and token refresh apply.
  Future<String> localFile(String url) async {
    if (_files.containsKey(url) && await File(_files[url]!).exists()) {
      return _files[url]!;
    }
    final id = Uri.parse(url).pathSegments.last;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid attachment');
    }
    final dir = await Directory.systemTemp.createTemp('phlio_dm_');
    final path = '${dir.path}/$id';
    await dio.download('/messaging/files/$id', path);
    _files[url] = path;
    return path;
  }

  Future<Map<String, dynamic>> startCall(String peer, bool video) async =>
      Map<String, dynamic>.from(
        (await dio
                .post('/messaging/calls', data: {'peer': peer, 'video': video}))
            .data as Map,
      );
  Future<List<Map<String, dynamic>>> incoming() async =>
      ((await dio.get('/messaging/calls/incoming')).data as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<Map<String, dynamic>> call(String id, int after) async =>
      Map<String, dynamic>.from(
        (await dio
                .get('/messaging/calls/$id', queryParameters: {'after': after}))
            .data as Map,
      );
  Future<void> action(String id, String action) async =>
      dio.post('/messaging/calls/$id/actions/$action');
  Future<void> signal(
    String id,
    String kind,
    Map<String, dynamic> payload,
  ) async =>
      dio.post(
        '/messaging/calls/$id/signals',
        data: {'kind': kind, 'payload': payload},
      );
  Future<Map<String, dynamic>> callConfig() async => Map<String, dynamic>.from(
        (await dio.get('/messaging/calls/config')).data as Map,
      );
}
