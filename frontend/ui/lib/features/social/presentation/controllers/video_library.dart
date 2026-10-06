import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';

class PlayableVideo {
  const PlayableVideo({
    required this.id,
    required this.title,
    required this.creator,
    required this.url,
    this.localPath,
    this.creatorName,
    this.avatarUrl,
  });
  final String id, title, creator, url;
  final String? localPath, creatorName, avatarUrl;
  factory PlayableVideo.fromJson(Map json) => PlayableVideo(
        id: json['id'] as String,
        title: json['title'] as String,
        creator: json['creator'] as String,
        url: json['url'] as String,
        creatorName: json['creator_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class SocialVideoApi {
  SocialVideoApi(this.dio);
  final Dio dio;
  Future<List<PlayableVideo>> videos() async {
    final items = <PlayableVideo>[];
    String? before;
    do {
      final page =
          (await dio.get('/social/videos', queryParameters: {'before': before}))
              .data as List;
      items.addAll(page.map((v) => PlayableVideo.fromJson(v as Map)));
      if (page.length < 50) break;
      final next = (page.last as Map)['created_at'] as String?;
      if (next == null || next == before) break;
      before = next;
    } while (true);
    return items;
  }

  Future<Set<String>> following() async =>
      ((await dio.get('/social/following')).data as List)
          .cast<String>()
          .toSet();
  Future<void> follow(String creator, bool enabled) async {
    final path = '/social/creators/${Uri.encodeComponent(creator)}/follow';
    if (enabled) {
      await dio.put(path);
    } else {
      await dio.delete(path);
    }
  }

  Future<PlayableVideo> upload(
    String path,
    String title, {
    ProgressCallback? onProgress,
  }) async =>
      PlayableVideo.fromJson(
        (await dio.post(
          '/social/videos',
          data: FormData.fromMap(
            {'title': title, 'file': await MultipartFile.fromFile(path)},
          ),
          options: Options(
            sendTimeout: const Duration(minutes: 30),
            receiveTimeout: const Duration(minutes: 2),
          ),
          onSendProgress: onProgress,
        ))
            .data as Map,
      );
}

final socialVideoApiProvider =
    Provider((ref) => SocialVideoApi(getIt<ApiClient>().dio));
final socialVideoCatalogProvider = FutureProvider.autoDispose((ref) {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return ref.watch(socialVideoApiProvider).videos();
});
final creatorFollowingProvider = FutureProvider((ref) {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return ref.watch(socialVideoApiProvider).following();
});
