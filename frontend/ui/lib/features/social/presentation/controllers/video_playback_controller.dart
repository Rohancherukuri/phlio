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
  return VideoPlaybackController();
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
  SocialPlayerMode mode = SocialPlayerMode.hidden;
  bool loading = false;
  bool fill = false;
  String? error;
  String? notice;
  double speed = 1;
  double volume = 1;
  bool loop = false;
  int _generation = 0;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open(PlayableVideo source) async {
    if (video?.id == source.id && player != null && error == null) {
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
      final next = _factory(source);
      player = next;
      await next.initialize();
      if (_disposed || generation != _generation) return;
      await next.setPlaybackSpeed(speed);
      await next.setVolume(volume);
      await next.setLooping(loop);
      if (_disposed || generation != _generation) return;
      next.addListener(_tick);
      loading = false;
      await next.play();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        loading = false;
        error =
            'Could not play this video. Check the connection or file format.';
      }
    }
    if (generation == _generation) _changed();
  }

  void _tick() {
    if (player?.value.hasError == true) {
      error = 'Playback interrupted. Retry to continue.';
    }
    _changed();
  }

  void setMode(SocialPlayerMode value) {
    final wasFullscreen = mode == SocialPlayerMode.fullscreen;
    mode = value;
    if (value == SocialPlayerMode.fullscreen) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    } else if (wasFullscreen)
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
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
