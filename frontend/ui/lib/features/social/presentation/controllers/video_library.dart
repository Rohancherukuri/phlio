import 'dart:async';
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
    this.songTitle,
    this.songArtist,
    this.kind = 'video',
    this.durationSeconds = 0,
    this.platform = 'social',
    this.contentId,
    this.attribution,
    this.thumbnailUrl,
    this.sources = const [],
    this.createdAt,
    this.description = '',
    this.tags = const [],
    this.location,
  });

  /// Long-form description and place from the Add details page.
  final String description;
  final List<String> tags;
  final String? location;

  /// When the video was uploaded (null for local/legacy items).
  final DateTime? createdAt;
  final String id, title, creator, url, kind;
  final int durationSeconds;
  final String platform;
  final String? contentId;
  final String? attribution;
  final String? thumbnailUrl;
  final List<Map<String, dynamic>> sources;
  PlayableVideo withUrl(String value) => PlayableVideo(
      id: id,
      title: title,
      creator: creator,
      url: value,
      creatorName: creatorName,
      avatarUrl: avatarUrl,
      songTitle: songTitle,
      songArtist: songArtist,
      kind: kind,
      durationSeconds: durationSeconds,
      platform: platform,
      contentId: contentId,
      attribution: attribution,
      thumbnailUrl: thumbnailUrl,
      sources: sources,
      createdAt: createdAt,
      description: description,
      tags: tags,
      location: location);
  final String? localPath, creatorName, avatarUrl, songTitle, songArtist;
  factory PlayableVideo.fromJson(Map json) => PlayableVideo(
        sources: (json['sources'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        attribution: json['attribution'] as String?,
        id: json['id'] as String,
        title: json['title'] as String,
        creator: json['creator'] as String,
        url: json['url'] as String,
        songTitle: json['song_title'] as String?,
        songArtist: json['song_artist'] as String?,
        creatorName: json['creator_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        kind: json['kind'] as String? ?? 'video',
        durationSeconds: json['duration_seconds'] as int? ?? 0,
        thumbnailUrl: json['thumbnail_url'] as String?,
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
        description: json['description'] as String? ?? '',
        tags: (json['tags'] as List? ?? []).whereType<String>().toList(),
        location: json['location'] as String?,
      );
}

class SocialVideoApi {
  SocialVideoApi(this.dio);
  final Dio dio;
  Future<List<PlayableVideo>> videos() async {
    final items = <PlayableVideo>[];
    String? before;
    do {
      final page = (await dio.get('/social/videos',
              queryParameters: {if (before != null) 'before': before}))
          .data as List;
      items.addAll(page.map((v) => PlayableVideo.fromJson(v as Map)));
      if (page.length < 50) break;
      final next = (page.last as Map)['created_at'] as String?;
      if (next == null || next == before) break;
      before = next;
    } while (true);
    final preferences =
        (await dio.get('/social/clips/preferences')).data as List;
    return rankClips(items, preferences.cast<Map>());
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
    String kind = 'video',
    String? musicId,
    Map<String, dynamic> details = const {},
  }) async =>
      PlayableVideo.fromJson(
        (await dio.post(
          '/social/videos',
          data: FormData.fromMap(
            {
              'title': title,
              'kind': kind,
              if (musicId != null) 'music_id': musicId,
              ...details,
              'file': await MultipartFile.fromFile(path)
            },
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
  final refresh =
      Timer.periodic(const Duration(minutes: 1), (_) => ref.invalidateSelf());
  ref.onDispose(refresh.cancel);
  return ref.watch(socialVideoApiProvider).videos();
});
final creatorFollowingProvider = FutureProvider((ref) {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return ref.watch(socialVideoApiProvider).following();
});

List<PlayableVideo> rankClips(
    List<PlayableVideo> items, List<Map> preferences) {
  Set<String> words(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\w]+'))
      .where((word) => word.length > 3)
      .toSet();
  final hidden = preferences
      .where((p) => p['preference'] == 'not_interested')
      .map((p) => p['clip_id'])
      .toSet();
  final interests = preferences.where((p) => p['preference'] == 'interested');
  int score(PlayableVideo v) => v.kind != 'clip'
      ? 0
      : interests.fold(
          0,
          (sum, p) =>
              sum +
              (p['creator'] == v.creator ? 3 : 0) +
              words(v.title)
                  .intersection(words(p['title'] as String? ?? ''))
                  .length);
  // "Don't recommend creator" hides every clip and video from them.
  final hiddenCreators = preferences
      .where((p) => p['preference'] == 'hide_creator')
      .map((p) => p['creator'])
      .toSet();
  final indexed = items
      .asMap()
      .entries
      .where((e) =>
          !hidden.contains(e.value.id) &&
          !hiddenCreators.contains(e.value.creator))
      .toList();
  indexed.sort((a, b) {
    final comparison = score(b.value).compareTo(score(a.value));
    return comparison == 0 ? a.key.compareTo(b.key) : comparison;
  });
  return indexed.map((e) => e.value).toList();
}

final friendsLikedClipsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final data = (await getIt<ApiClient>().dio.get('/social/clips/friends-liked'))
      .data as Map;
  return data
      .map((key, value) => MapEntry(key.toString(), (value as num).toInt()));
});
