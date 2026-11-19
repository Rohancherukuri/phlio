import '../media/smart_filters.dart';
import '../../features/profile/presentation/widgets/snap_decorations.dart';
import '../moments/stickers/sticker_model.dart';
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
import '../media/phlio_look_data.dart';
import '../media/phlio_look_view.dart';
import '../media/story_fx_view.dart';

final privatePhotoProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, path) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final result = await getIt<ApiClient>()
      .dio
      .get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
  return Uint8List.fromList(result.data!);
});

/// A snap / experience photo or video, with its decorations. [filter] is
/// the snap's look and effect ("look" or "look+effect",
/// shared/media/phlio_look_data.dart), drawn live on the GPU so animated
/// effects (drift, glitch…) keep moving on photos and videos alike.
class MemoryPhoto extends ConsumerWidget {
  const MemoryPhoto(this.url,
      {super.key,
      this.fit = BoxFit.cover,
      this.isVideo = false,
      this.decorations = const [],
      this.filter,
      this.filterSpec,
      this.takenAt,
      this.autoplay = false});

  /// When it was taken (date stamps of film / camcorder effects).
  final DateTime? takenAt;
  final List decorations;
  final bool isVideo;
  final String url;
  final BoxFit fit;
  final String? filter;

  /// Smart filter overlays (time, weather, place…) saved with the snap.
  final Object? filterSpec;

  /// Videos start playing (looping) instead of waiting for a tap.
  final bool autoplay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layers = decorations.whereType<Map>().map(MomentSticker.fromJson).whereType<MomentSticker>().toList();
    return layers.isEmpty ? _filtered(context, ref) : SnapDecorationCanvas(layers: layers, child: _filtered(context, ref));
  }

  /// The filter applies to the photo / video, under the decorations.
  Widget _filtered(BuildContext context, WidgetRef ref) {
    final (look, effect) = splitMomentFilter(filter);
    final smart = FilterSpec.fromJson(filterSpec);
    final looked = look == 'normal' && effect == 'none'
        ? _photo(context, ref)
        : PhlioLook(look: look, effect: effect, strength: smart?.strength ?? 1, child: _photo(context, ref));
    // Adjust sliders and the story effect, drawn live on the GPU.
    final base = smart == null || (smart.fx == null && smart.adjust.isEmpty)
        ? looked
        : StoryFxLayer(fx: smart.fx, amount: smart.fxAmount, adjust: smart.adjust, stamp: takenAt, child: looked);
    if (smart == null || smart.overlays.isEmpty) return base;
    return Stack(fit: StackFit.expand, children: [base, SmartFilterLayer(spec: smart)]);
  }

  Widget _photo(BuildContext context, WidgetRef ref) {
    if (isVideo) return _MemoryVideo(url, fit: fit, autoplay: autoplay);
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
  const _MemoryVideo(this.url, {this.fit = BoxFit.cover, this.autoplay = false});
  final String url;
  final BoxFit fit;
  final bool autoplay;
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
      await next.setLooping(true);
      if (!mounted) {
        await next.dispose();
        return;
      }
      if (widget.autoplay) await next.play();
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
      SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
              width: player!.value.size.width,
              height: player!.value.size.height,
              child: VideoPlayer(player!)),
        ),
      ),
      IconButton.filledTonal(
          onPressed: () {
            player!.value.isPlaying ? player!.pause() : player!.play();
            setState(() {});
          },
          icon: Icon(player!.value.isPlaying ? Icons.pause : Icons.play_arrow))
    ]);
  }
}
