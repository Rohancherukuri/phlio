// Push notifications through OneSignal.
//
// The server sends every Phlio notification (DMs, rooms, comments, Shop,
// News, Stream…) as a push when OneSignal is set up — see
// backend/app/infrastructure/onesignal.py. This side:
//
//   * asks the server for the OneSignal app id (GET /notifications/push/status,
//     so nothing is baked into the build), initialises the SDK and logs in
//     with the Phlio user id as the external id — that's how a push finds
//     your phone. Sign out → OneSignal.logout();
//   * while the app is open, pushes are not shown by the system: the island
//     (phlio_island.dart) shows them instead, so you never get both;
//   * tapping a push opens its chat / room / post / product; tapping an
//     action button does it: Reply (opens the chat), ❤️ (reacts), Add to bag,
//     Bookmark (offers your News playlists or saves to "Saved"), Play.
//
// Only Android and iOS have push; elsewhere this does nothing.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../app/config/app_config.dart';
import '../../app/router/app_router.dart' show routerProvider;
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/rooms/data/datasources/messaging_api.dart';
import '../../features/stream/music/music_models.dart';
import '../../features/stream/music/music_player.dart';

class PhlioPush {
  PhlioPush._();
  static final instance = PhlioPush._();

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool _ready = false;
  String? _user;
  Ref? _ref;

  /// Called by the notification centre when you're signed in.
  /// [onForeground] gets pushes that arrive while the app is open.
  Future<void> signIn(Ref ref, String userId, {required VoidCallback onForeground}) async {
    if (!supported) return;
    _ref = ref;
    try {
      if (!_ready) {
        final status = (await getIt<ApiClient>().dio.get('/notifications/push/status')).data as Map;
        final appId = status['app_id'] as String?;
        if (status['enabled'] != true || appId == null || appId.isEmpty) {
          debugPrint('Push: off — set ONESIGNAL_APP_ID and ONESIGNAL_REST_API_KEY in backend/.env and restart it.');
          return;
        }
        OneSignal.Debug.setLogLevel(kDebugMode ? OSLogLevel.warn : OSLogLevel.none);
        OneSignal.initialize(appId);
        OneSignal.Notifications.addForegroundWillDisplayListener((event) {
          if (event.notification.additionalData?['phlio'] == true) {
            event.preventDefault(); // the island shows it
            onForeground();
          }
        });
        OneSignal.Notifications.addClickListener(_clicked);
        _ready = true;
      }
      if (_user != userId) {
        await OneSignal.login(userId);
        _user = userId;
      }
      if (!OneSignal.Notifications.permission) {
        await OneSignal.Notifications.requestPermission(true);
      }
    } on DioException catch (e) {
      // Not fatal: in-app notifications keep working; we try again the next
      // time the app comes back to the foreground.
      if (e.response?.statusCode == 404) {
        debugPrint('Push: the server has no /notifications/push/status yet — '
            'restart (or redeploy) the backend to pick up the push code.');
      } else {
        debugPrint('Push: could not reach the server (${e.type.name}); will retry.');
      }
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
  }

  /// Retries setup when the app returns to the foreground, if it failed.
  Future<void> retry(Ref ref, String userId, {required VoidCallback onForeground}) async {
    if (_ready && _user == userId) return;
    await signIn(ref, userId, onForeground: onForeground);
  }

  Future<void> signOut() async {
    if (!_ready || _user == null) return;
    _user = null;
    try {
      await OneSignal.logout();
    } catch (_) {}
  }

  /// Sends one push of each kind after [delay] — lock the phone to see them.
  Future<String> test({Duration delay = const Duration(seconds: 10)}) async {
    if (!supported) return 'Push works on Android and iOS only.';
    if (!_ready) return 'Push is not set up yet (the server has no OneSignal keys, or you denied notifications).';
    if (!OneSignal.Notifications.permission) {
      final ok = await OneSignal.Notifications.requestPermission(true);
      if (!ok) return 'Notifications are off for Phlio in your phone settings.';
    }
    await getIt<ApiClient>().dio.post('/notifications/push/test', data: {'delay_seconds': delay.inSeconds});
    return 'Sample pushes arrive in ${delay.inSeconds} s: lock your phone or leave the app.';
  }

  BuildContext? get _navigator => _ref?.read(routerProvider).routerDelegate.navigatorKey.currentContext;

  void _toast(String text) {
    final context = _navigator;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _clicked(OSNotificationClickEvent event) async {
    final data = event.notification.additionalData ?? const {};
    if (data['phlio'] != true) return;
    final action = event.result.actionId;
    final dio = getIt<ApiClient>().dio;
    final id = data['notification_id'];
    if (id != null) {
      unawaited(dio.post('/notifications/read', data: {'ids': [id]}).then((_) {}, onError: (_) {}));
    }
    // The app may still be starting: wait for the router's Navigator.
    for (var i = 0; i < 40 && _navigator == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final ref = _ref;
    final route = data['route'] as String?;
    try {
      switch (action) {
        case 'react':
          if (data['platform'] == 'dm' && data['peer'] != null && ref != null) {
            await ref.read(messagingApiProvider).send('${data['peer']}', '❤️');
          } else if (data['room_id'] != null) {
            await dio.post('/rooms/${data['room_id']}/messages', data: {'text': '❤️', 'attachments': []});
          }
          _toast('Sent ❤️');
          return;
        case 'like':
          final path = '${data['path']}';
          final platform = path.split('/').first;
          await dio.put('/social/content/${path.substring(platform.length + 1)}/comments/${data['comment_id']}/like',
              queryParameters: {'platform': platform, 'liked': true});
          _toast('Liked the comment');
          return;
        case 'bag':
          await dio.put('/shop/cart/${Uri.encodeComponent('${data['product_id']}')}', data: {'quantity': 1});
          _toast('Added to your bag');
          return;
        case 'bookmark':
          await _bookmark('${data['ref']}');
          return;
        case 'play':
          if (ref != null && data['media_url'] != null) {
            await ref.read(musicPlayerProvider).playTracks([
              Track(
                id: 'phlio-${data['ref']}',
                title: '${data['title'] ?? ''}',
                artist: '${data['artist'] ?? ''}',
                album: 'Phlio Stream',
                uri: '${data['media_url']}',
                artUrl: data['image_url'] == null ? null : AppConfig.mediaUrl('${data['image_url']}'),
                ref: '${data['ref']}',
                genre: 'Music',
              ),
            ]);
          }
          return;
      }
    } catch (_) {
      _toast('Could not do that. Try again from the app.');
      return;
    }
    // A tap on the push itself, Reply or "See all": open it.
    if (route != null && ref != null) ref.read(routerProvider).push(route);
  }

  /// Your News playlists to choose from, or straight into "Saved".
  Future<void> _bookmark(String newsRef) async {
    final dio = getIt<ApiClient>().dio;
    final lists = (((await dio.get('/playlists', queryParameters: {'platform': 'news'})).data as Map)['items'] as List)
        .whereType<Map>()
        .toList();
    String? playlistId;
    final context = _navigator;
    if (lists.isNotEmpty && context != null && context.mounted) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Save to playlist', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            for (final p in lists)
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: Text('${p['name']}'),
                onTap: () => Navigator.pop(sheet, '${p['id']}'),
              ),
            if (!lists.any((p) => p['name'] == 'Saved'))
              ListTile(
                leading: const Icon(Icons.bookmark_rounded),
                title: const Text('Saved'),
                onTap: () => Navigator.pop(sheet, ''),
              ),
          ]),
        ),
      );
      if (picked == null) return;
      playlistId = picked.isEmpty ? null : picked;
    }
    final res = await dio.post('/playlists/save/bookmark', data: {
      'platform': 'news',
      'ref': newsRef,
      if (playlistId != null) 'playlist_id': playlistId,
    });
    _toast('Saved to “${(res.data as Map)['name'] ?? 'Saved'}”');
  }
}
