// Phlio notifications on the phone: the feed (GET /notifications), polled
// while the app is open, plus a queue of new ones for the island banner
// (phlio_island.dart).
//
//   * Every notification belongs to one platform — Messages, Social, Rooms,
//     Shop, News, Stream, Book, Pay, Foxy — with its own colour and icon
//     ([NotifPlatform]), so you can tell them apart at a glance.
//   * Opening a chat or room marks its notifications read; so does opening
//     a notification.
//
// Backend: backend/app/api/v1/notifications.py.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart' show routerProvider;
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import 'push.dart';

/// How each platform looks in a notification.
class NotifPlatform {
  const NotifPlatform(this.id, this.label, this.icon, this.color, [this.second]);
  final String id, label;
  final IconData icon;
  final Color color;

  /// Second gradient stop for the badge.
  final Color? second;

  LinearGradient get gradient => LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, second ?? Color.lerp(color, Colors.black, .25)!]);

  static const all = <NotifPlatform>[
    NotifPlatform('dm', 'Messages', Icons.chat_bubble_rounded, Color(0xFFFF5FA2), Color(0xFFB04CFF)),
    NotifPlatform('social', 'Social', Icons.people_alt_rounded, Color(0xFF8D78FF), Color(0xFF5B48E8)),
    NotifPlatform('rooms', 'Rooms', Icons.forum_rounded, Color(0xFF3DD6C6), Color(0xFF168F86)),
    NotifPlatform('shop', 'Shop', Icons.shopping_bag_rounded, Color(0xFFFF9F5A), Color(0xFFE8613A)),
    NotifPlatform('news', 'News', Icons.newspaper_rounded, Color(0xFF4C9BFF), Color(0xFF2759D6)),
    NotifPlatform('stream', 'Stream', Icons.play_circle_fill_rounded, Color(0xFFFF4D5E), Color(0xFFB3123A)),
    NotifPlatform('book', 'Book', Icons.local_activity_rounded, Color(0xFFE795D7), Color(0xFFB45BAA)),
    NotifPlatform('pay', 'Pay', Icons.account_balance_wallet_rounded, Color(0xFFF6C343), Color(0xFFD08A10)),
    NotifPlatform('agent', 'Foxy', Icons.auto_awesome_rounded, Color(0xFFFFB58F), Color(0xFFFF7A59)),
  ];

  static NotifPlatform of(String id) => all.firstWhere((p) => p.id == id, orElse: () => all[1]);
}

class PhlioNotification {
  PhlioNotification(Map j)
      : id = '${j['id']}',
        platform = NotifPlatform.of('${j['platform']}'),
        kind = '${j['kind']}',
        title = '${j['title'] ?? ''}',
        body = '${j['body'] ?? ''}',
        actor = j['actor'] is Map ? Map<String, dynamic>.from(j['actor'] as Map) : null,
        data = j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : <String, dynamic>{},
        group = j['group'] as String?,
        count = (j['count'] as num?)?.toInt() ?? 1,
        read = j['read'] == true,
        at = DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now();

  final String id, kind, title, body;
  final NotifPlatform platform;
  final Map<String, dynamic>? actor;
  final Map<String, dynamic> data;
  final String? group;
  final int count;
  bool read;
  final DateTime at;

  /// The in-app place this notification opens.
  String? get route => switch (platform.id) {
        'dm' => data['peer'] == null ? null : '/dm/${Uri.encodeComponent('${data['peer']}')}',
        'rooms' => data['room_id'] == null ? null : '/rooms/${data['room_id']}',
        _ => data['path'] is String && '${data['path']}'.contains('/')
            ? '/shared/${'${data['path']}'.split('/').first}/${Uri.encodeComponent('${data['path']}'.split('/').skip(1).join('/'))}'
            : null,
      };

  /// Messages and comments can be answered right from the banner.
  bool get canReply =>
      (platform.id == 'dm' && data['peer'] != null) ||
      (platform.id == 'rooms' && data['room_id'] != null) ||
      (const {'comment', 'reply', 'mention'}.contains(kind) && data['comment_id'] != null);
}

class NotificationCenter extends ChangeNotifier with WidgetsBindingObserver {
  NotificationCenter(this.ref) {
    WidgetsBinding.instance.addObserver(this);
    _auth = ref.listen(authControllerProvider.select((v) => v.valueOrNull?.id), (_, id) {
      _reset();
      if (id != null) {
        _start();
        // Pushes for when the app is closed; while it's open the island
        // shows them, so a push that arrives now just triggers a poll.
        PhlioPush.instance.signIn(ref, id, onForeground: () => _poll());
      } else {
        PhlioPush.instance.signOut();
      }
    }, fireImmediately: true);
  }

  final Ref ref;
  late final ProviderSubscription<String?> _auth;
  Timer? _timer;
  String? _since;
  bool _foreground = true, _loading = false;
  VoidCallback? _routeListener;

  List<PhlioNotification> items = [];
  int unread = 0;

  /// New notifications waiting for the island, oldest first.
  final queue = <PhlioNotification>[];

  void _reset() {
    _timer?.cancel();
    _since = null;
    items = [];
    unread = 0;
    queue.clear();
    notifyListeners();
  }

  void _start() {
    _watchRoutes();
    _poll(initial: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_foreground) _poll();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _since != null) _poll();
  }

  /// Opening a chat or a room clears its notifications.
  void _watchRoutes() {
    if (_routeListener != null) return;
    final router = ref.read(routerProvider);
    _routeListener = () {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      final dm = RegExp(r'^/dm/([^/]+)').firstMatch(path)?.group(1);
      final room = RegExp(r'^/rooms/([^/]+)').firstMatch(path)?.group(1);
      if (dm != null) markWhere((n) => n.platform.id == 'dm' && '${n.data['peer']}' == Uri.decodeComponent(dm));
      if (room != null) markWhere((n) => n.platform.id == 'rooms' && '${n.data['room_id']}' == room);
    };
    router.routerDelegate.addListener(_routeListener!);
  }

  /// Where you are right now — a banner for that chat would be noise.
  bool _isOpen(PhlioNotification n) {
    final path = ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
    final route = n.route;
    return route != null && (n.platform.id == 'dm' || n.platform.id == 'rooms') && Uri.decodeComponent(path) == Uri.decodeComponent(route);
  }

  Future<void> refresh() => _poll(force: true);

  /// One sample banner of each kind (Messages, Rooms, Shop, News, a song,
  /// a movie / show) to try the island out. Returns what was created.
  Future<List<String>> preview() async {
    final res = await getIt<ApiClient>().dio.post('/notifications/preview');
    while (_loading) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _poll();
    return [for (final x in ((res.data as Map)['created'] as List? ?? const [])) '$x'];
  }

  Future<void> _poll({bool initial = false, bool force = false}) async {
    if (_loading && !force) return;
    _loading = true;
    try {
      final res = await getIt<ApiClient>().dio.get('/notifications', queryParameters: {
        if (_since != null && !force) 'since': _since,
        'limit': initial || force ? 60 : 20,
      });
      final data = res.data as Map;
      final fresh = [for (final j in (data['items'] as List? ?? const [])) PhlioNotification(j as Map)];
      unread = (data['unread'] as num?)?.toInt() ?? unread;
      if (initial || force) {
        items = fresh;
      } else if (fresh.isNotEmpty) {
        // Grouped chats update in place: drop the older copy.
        final ids = {for (final n in fresh) n.id};
        items = [...fresh, ...items.where((n) => !ids.contains(n.id))];
        final stale = DateTime.now().subtract(const Duration(seconds: 45));
        for (final n in fresh.reversed) {
          // Old news by now (it came as a push while you were away).
          if (n.read || _isOpen(n) || n.at.isBefore(stale)) continue;
          queue.removeWhere((q) => q.id == n.id);
          queue.add(n);
        }
      }
      // The server's clock, so phones with a skewed clock miss nothing.
      _since = (data['server_time'] as String?) ?? DateTime.now().toUtc().toIso8601String();
      notifyListeners();
    } catch (_) {
      // Offline: try again on the next tick.
    } finally {
      _loading = false;
    }
  }

  /// The island took the next banner.
  PhlioNotification? takeNext() {
    if (queue.isEmpty) return null;
    final next = queue.removeAt(0);
    notifyListeners();
    return next;
  }

  Future<void> markRead(Iterable<PhlioNotification> list) async {
    final ids = [for (final n in list) if (!n.read) n.id];
    if (ids.isEmpty) return;
    for (final n in list) {
      n.read = true;
    }
    unread = (unread - ids.length).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await getIt<ApiClient>().dio.post('/notifications/read', data: {'ids': ids});
    } catch (_) {}
  }

  void markWhere(bool Function(PhlioNotification) test) {
    final hits = items.where((n) => !n.read && test(n)).toList();
    queue.removeWhere(test);
    if (hits.isNotEmpty) markRead(hits);
  }

  Future<void> markAllRead() async {
    for (final n in items) {
      n.read = true;
    }
    unread = 0;
    notifyListeners();
    try {
      await getIt<ApiClient>().dio.post('/notifications/read-all');
    } catch (_) {}
  }

  Future<void> remove(PhlioNotification n) async {
    items.removeWhere((x) => x.id == n.id);
    if (!n.read) unread = (unread - 1).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await getIt<ApiClient>().dio.delete('/notifications/${Uri.encodeComponent(n.id)}');
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _auth.close();
    if (_routeListener != null) {
      try {
        ref.read(routerProvider).routerDelegate.removeListener(_routeListener!);
      } catch (_) {}
    }
    super.dispose();
  }
}

final notificationCenterProvider = ChangeNotifierProvider<NotificationCenter>((ref) => NotificationCenter(ref));

/// "now", "5m", "2h", "3d".
String notifAgo(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 45) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${at.day}/${at.month}';
}
