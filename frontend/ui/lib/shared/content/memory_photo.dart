import 'dart:io';
import 'package:video_player/video_player.dart';
import '../../features/rooms/data/datasources/messaging_api.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';

final privatePhotoProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, path) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final result = await getIt<ApiClient>()
      .dio
      .get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
  return Uint8List.fromList(result.data!);
});

class MemoryPhoto extends ConsumerWidget {
  const MemoryPhoto(this.url,
      {super.key, this.fit = BoxFit.cover, this.isVideo = false});
  final bool isVideo;
  final String url;
  final BoxFit fit;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isVideo) return _MemoryVideo(url);
    if (!url.startsWith('/social/memories/'))
      return Image.network(AppConfig.mediaUrl(url),
          fit: fit,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined));
    return ref.watch(privatePhotoProvider(url)).when(
        data: (bytes) => Image.memory(bytes,
            fit: fit, width: double.infinity, height: double.infinity),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Photo unavailable')));
  }
}

class _MemoryVideo extends ConsumerStatefulWidget {
  const _MemoryVideo(this.url);
  final String url;
  @override
  ConsumerState<_MemoryVideo> createState() => _MemoryVideoState();
}

class _MemoryVideoState extends ConsumerState<_MemoryVideo> {
  VideoPlayerController? player;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final path = await ref.read(messagingApiProvider).localFile(widget.url);
      final next = VideoPlayerController.file(File(path));
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() => player = next);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) return const Center(child: Text('Video unavailable'));
    if (player == null) return const Center(child: CircularProgressIndicator());
    return Stack(alignment: Alignment.center, children: [
      AspectRatio(
          aspectRatio: player!.value.aspectRatio, child: VideoPlayer(player!)),
      IconButton.filledTonal(
          onPressed: () {
            player!.value.isPlaying ? player!.pause() : player!.play();
            setState(() {});
          },
          icon: Icon(player!.value.isPlaying ? Icons.pause : Icons.play_arrow))
    ]);
  }
}
