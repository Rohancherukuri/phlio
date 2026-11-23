// Disk caches for images and videos, so content that has loaded once
// shows instantly afterwards — on Wi-Fi, mobile data, or a flaky network.
//
//  * [PhlioMediaCache.images] — every network image in the app (avatars,
//    thumbnails, post photos, covers). Kept for 60 days, up to 3000 files.
//    The default cache of `cached_network_image` keeps only 200, which
//    meant feeds re-downloaded their images on every visit.
//  * [PhlioMediaCache.videos] — short videos (Clips, moments). A clip is
//    streamed the first time while it downloads in the background; the next
//    view, and the next clip in the feed (prefetched while you watch), play
//    straight from disk.
//  * [phlioNetworkImage] / [phlioImageProvider] — drop-in replacements for
//    `Image.network` / `NetworkImage` that go through the image cache.
//
// Media URLs point at the API host (`/media/...`) and the server streams
// bucket files itself, so phones never depend on a domain that a mobile
// carrier might block (backend: MediaFiles / MEDIA_DELIVERY).

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

abstract final class PhlioMediaCache {
  static final CacheManager images = CacheManager(Config(
    'phlioImages',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 3000,
  ));

  static final CacheManager videos = CacheManager(Config(
    'phlioVideos',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 80,
  ));

  /// Videos known to be fully on disk this session (url → file path).
  static final Map<String, String> _onDisk = {};
  static final Set<String> _downloading = {};

  /// A player for a short video: from disk when it's cached, otherwise
  /// streamed while it's saved for next time.
  static VideoPlayerController shortVideo(String url) {
    final path = _onDisk[url];
    if (path != null && File(path).existsSync()) {
      return VideoPlayerController.file(File(path));
    }
    unawaited(prefetchVideo(url));
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }

  /// Make sure [url] is on disk (no-op if it already is). Used to warm the
  /// next clips in a feed so swiping never waits on the network.
  static Future<void> prefetchVideo(String url) async {
    if (_onDisk.containsKey(url) || !_downloading.add(url)) return;
    try {
      final cached = await videos.getFileFromCache(url);
      final file = cached?.file ?? await videos.getSingleFile(url);
      _onDisk[url] = file.path;
    } catch (_) {
      // Offline or the file is gone: it streams next time instead.
    } finally {
      _downloading.remove(url);
    }
  }

  /// Wipe both caches (Settings → storage, or sign-out).
  static Future<void> clear() async {
    _onDisk.clear();
    await Future.wait([images.emptyCache(), videos.emptyCache()]);
  }
}

/// `NetworkImage` that reads from / saves to [PhlioMediaCache.images].
ImageProvider phlioImageProvider(String url, {double scale = 1.0, Map<String, String>? headers}) =>
    CachedNetworkImageProvider(url, scale: scale, headers: headers, cacheManager: PhlioMediaCache.images);

/// Same parameters as `Image.network`, backed by [PhlioMediaCache.images].
Image phlioNetworkImage(
  String src, {
  Key? key,
  double scale = 1.0,
  ImageFrameBuilder? frameBuilder,
  ImageLoadingBuilder? loadingBuilder,
  ImageErrorWidgetBuilder? errorBuilder,
  String? semanticLabel,
  bool excludeFromSemantics = false,
  double? width,
  double? height,
  Color? color,
  Animation<double>? opacity,
  BlendMode? colorBlendMode,
  BoxFit? fit,
  AlignmentGeometry alignment = Alignment.center,
  ImageRepeat repeat = ImageRepeat.noRepeat,
  Rect? centerSlice,
  bool matchTextDirection = false,
  bool gaplessPlayback = false,
  FilterQuality filterQuality = FilterQuality.medium,
  bool isAntiAlias = false,
  Map<String, String>? headers,
  int? cacheWidth,
  int? cacheHeight,
}) =>
    Image(
      key: key,
      image: ResizeImage.resizeIfNeeded(
          cacheWidth, cacheHeight, phlioImageProvider(src, scale: scale, headers: headers)),
      frameBuilder: frameBuilder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      filterQuality: filterQuality,
      isAntiAlias: isAntiAlias,
    );
