// Disk caches for images and videos, so content that has loaded once
// shows instantly afterwards — on Wi-Fi, mobile data, or a flaky network.
//
//  * [PhlioMediaCache.images] — every network image in the app (avatars,
//    thumbnails, post photos, covers). Kept for 60 days, up to 3000 files.
//    The default cache of `cached_network_image` keeps only 200, which
//    meant feeds re-downloaded their images on every visit.
//  * [PhlioMediaCache.videos] — short videos (Clips, moments). A clip is
//    streamed the first time while it downloads in the background; the
//    next view, and the next clip in the feed (prefetched while you watch),
//    play straight from disk.
//  * [phlioNetworkImage] / [phlioImageProvider] — drop-in replacements for
//    `Image.network` / `NetworkImage` that go through the image cache.
//
// Media URLs come from the API host (`/media/...`); the server streams
// bucket files itself, so phones never depend on a third-party domain that
// a mobile carrier might block (see backend MediaFiles, MEDIA_DELIVERY).

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

abstract final class PhlioMediaCache {
  static final CacheManager images = CacheManager(Config(
    'phlioImages',
    stalePPeriodFix: null,
  ));
}
