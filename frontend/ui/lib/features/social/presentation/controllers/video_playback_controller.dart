import '../../../../shared/content/content_surface.dart' show engagementProvider;
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../../app/config/app_config.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import 'video_library.dart';

enum SocialPlayerMode { hidden, expanded, fullscreen, floating }

final videoPlaybackProvider =
    ChangeNotifierProvider<VideoPlaybackController>((ref) {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final controller = VideoPlaybackController();
  // Refresh the view count wherever this video's engagement is shown.
  controller.onViewed = (path) {
    try {
      ref.invalidate(engagementProvider(path));
    } catch (_) {}
  };
  return controller;
});

class VideoPlaybackController extends ChangeNotifier {
  VideoPlaybackController({
    VideoPlayerController Function(PlayableVideo)? factory,
  }) : _factory = factory ?? _defaultFactory;
  final VideoPlayerController Function(PlayableVideo) _factory;
  static VideoPlayerController _defaultFactory(PlayableVideo video) =>
      video.localPath != null
          ? VideoPlayerController.file(File(video.localPath!))
          : VideoPlayerController.networkUrl(
              Uri.parse(AppConfig.mediaUrl(video.url)),
            );
  PlayableVideo? video;
  VideoPlayerController? player;

  /// Called with `platform/ref` once a view has been recorded.
  void Function(String path)? onViewed;
  SocialPlayerMode mode = SocialPlayerMode.hidden;
  bool loading = false;
  bool fill = false;
  String? error;
  String? notice;
  double speed = 1;
  double volume = 1;
  bool loop = false;
  String qualityLabel = 'Auto';
  String? qualityUrl;
  int _generation = 0;
  bool _disposed = false;

  /// Up-next queue ("Play next" / "Play last in queue"). When the current
  /// video finishes (and isn't looping) the head of the queue starts.
  final List<PlayableVideo> queue = [];
  bool _advancing = false;

  /// Queue [next] to play right after the current video, or start it now
  /// when nothing is playing.
  void playNext(PlayableVideo next) {
    if (video == null) {
      unawaited(open(next));
      return;
    }
    queue.removeWhere((v) => v.id == next.id);
    queue.insert(0, next);
    _changed();
  }

  /// Add [next] to the end of the queue (or start it when idle).
  void playLast(PlayableVideo next) {
    if (video == null) {
      unawaited(open(next));
      return;
    }
    queue.removeWhere((v) => v.id == next.id);
    queue.add(next);
    _changed();
  }
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open(PlayableVideo source,
      {bool force = false, Duration? position, bool autoplay = true}) async {
    if (video?.id != source.id) {
      qualityUrl = null;
      qualityLabel = 'Auto';
    }
    if (!force && video?.id == source.id && player != null && error == null) {
      setMode(SocialPlayerMode.expanded);
      return;
    }
    final generation = ++_generation;
    final old = player;
    old?.removeListener(_tick);
    video = source;
    player = null;
    loading = true;
    error = null;
    notice = null;
    setMode(SocialPlayerMode.expanded);
    if (old != null) unawaited(old.dispose());
    try {
      final next =
          _factory(qualityUrl == null ? source : source.withUrl(qualityUrl!));
      player = next;
      await next.initialize();
      if (_disposed || generation != _generation) return;
      await next.setPlaybackSpeed(speed);
      await next.setVolume(volume);
      await next.setLooping(loop);
      if (_disposed || generation != _generation) return;
      next.addListener(_tick);
      loading = false;
      if (position != null) await next.seekTo(position);
      if (autoplay) await next.play();
      if (!force &&
          source.localPath == null &&
          getIt.isRegistered<ApiClient>()) {
        unawaited(getIt<ApiClient>()
            .dio
            .put(
                '/content/${source.platform}/${source.contentId ?? source.id}/actions/viewed')
            .then<void>(
                (_) => onViewed?.call(
                    '${source.platform}/${source.contentId ?? source.id}'),
                onError: (Object _) {}));
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        loading = false;
        error =
            'Could not play this video. Check the connection or file format.';
      }
    }
    if (generation == _generation) _changed();
  }

  Future<void> setQuality(Map<String, dynamic>? source) async {
    if (video == null || loading) return;
    final position = player?.value.position;
    final playing = player?.value.isPlaying == true;
    qualityUrl = source?['url'] as String?;
    qualityLabel = source?['label'] as String? ?? 'Auto';
    await open(video!, force: true, position: position, autoplay: playing);
  }

  void _tick() {
    final value = player?.value;
    if (value?.hasError == true) {
      error = 'Playback interrupted. Retry to continue.';
    }
    if (value != null &&
        value.isInitialized &&
        !loop &&
        !_advancing &&
        queue.isNotEmpty &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying) {
      _advancing = true;
      final next = queue.removeAt(0);
      unawaited(open(next).whenComplete(() => _advancing = false));
    }
    _changed();
  }

  void setMode(SocialPlayerMode value) {
    final wasFullscreen = mode == SocialPlayerMode.fullscreen;
    mode = value;
    if (value == SocialPlayerMode.fullscreen) {
      unawaited(SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]));
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    } else if (wasFullscreen) {
      unawaited(SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _changed();
  }

  Future<void> toggle() async {
    final p = player;
    if (p == null || !p.value.isInitialized) return;
    try {
      if (p.value.isPlaying) {
        await p.pause();
      } else {
        if (p.value.position >= p.value.duration) await p.seekTo(Duration.zero);
        await p.play();
      }
    } catch (_) {
      error = 'Playback interrupted. Retry to continue.';
      _changed();
    }
  }

  Future<void> seek(Duration target) async {
    final p = player;
    if (p == null || !p.value.isInitialized) return;
    try {
      await p.seekTo(
        Duration(
          milliseconds:
              target.inMilliseconds.clamp(0, p.value.duration.inMilliseconds),
        ),
      );
    } catch (_) {
      notice = 'Seeking is unavailable for this video.';
      _changed();
    }
  }

  Future<void> setSpeed(double value) async {
    try {
      await player?.setPlaybackSpeed(value);
      speed = value;
      notice = null;
    } catch (_) {
      notice = 'This video does not support that playback speed.';
    }
    _changed();
  }

  Future<void> setVolume(double value) async {
    try {
      await player?.setVolume(value);
      volume = value;
      notice = null;
    } catch (_) {
      notice = 'Volume control is unavailable for this video.';
    }
    _changed();
  }

  Future<void> setLoop(bool value) async {
    try {
      await player?.setLooping(value);
      loop = value;
      notice = null;
    } catch (_) {
      notice = 'Looping is unavailable for this video.';
    }
    _changed();
  }

  void setFill(bool value) {
    fill = value;
    _changed();
  }

  void close() {
    ++_generation;
    final old = player;
    old?.removeListener(_tick);
    player = null;
    video = null;
    loading = false;
    error = null;
    notice = null;
    setMode(SocialPlayerMode.hidden);
    if (old != null) unawaited(old.dispose());
  }

  @override
  void dispose() {
    _disposed = true;
    close();
    super.dispose();
  }
}
