// The Phlio island: in-app notification banner that grows with its
// content, like the iPhone's Dynamic Island.
//
//   compact   a black pill at the top — the sender's photo with the
//             platform's badge (Messages, Social, Rooms, Shop, News, Stream…),
//             the title and one line of the message.
//   expanded  tap or pull it down: it morphs into a card sized to what it
//             holds —
//               · Messages / Rooms / comments: the full message, quick
//                 reactions, a reply box, GIFs and stickers;
//               · Shop: similar items, each with a bag button;
//               · News: the story with a Bookmark button that offers your
//                 News playlists (or saves to a default one);
//               · Stream: a song you can play right there, or a movie / show
//                 banner.
//   Swipe it up to dismiss. Compact banners leave after 5 s; expanded ones
//   stay while you use them.
//
// It sits above the app's Navigator (MaterialApp builder), so pickers that
// need a Navigator (GIFs, stickers) open on the router's Navigator while the
// island steps aside.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../app/router/app_router.dart' show routerProvider;
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/rooms/data/datasources/messaging_api.dart';
import '../../features/stream/music/music_models.dart';
import '../../features/stream/music/music_player.dart';
import '../content/mentions.dart';
import '../giphy/giphy_picker.dart';
import 'notification_center.dart';
import 'package:phlio/core/network/media_cache.dart';

const _ink = Color(0xFF050608);
const _quick = ['❤️', '😂', '😮', '😢', '👏', '🔥'];

class PhlioIsland extends ConsumerStatefulWidget {
  const PhlioIsland({super.key});
  @override
  ConsumerState<PhlioIsland> createState() => _PhlioIslandState();
}

class _PhlioIslandState extends ConsumerState<PhlioIsland> with TickerProviderStateMixin {
  PhlioNotification? current;
  bool expanded = false, visible = false, suspended = false;
  Timer? _dismiss;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(notificationCenterProvider, (_, center) => _maybeShowNext(), fireImmediately: true);
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }

  void _maybeShowNext() {
    if (visible || suspended) return;
    final next = ref.read(notificationCenterProvider).takeNext();
    if (next == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      current = next;
      expanded = false;
      visible = true;
      _drag = 0;
    });
    _arm(const Duration(seconds: 5));
  }

  /// Auto-dismiss after [after] unless you're using it.
  void _arm(Duration after) {
    _dismiss?.cancel();
    _dismiss = Timer(after, () {
      if (mounted && !_busy) _hide();
    });
  }

  bool get _busy => FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<_PhlioIslandState>() == this;

  void _keepAlive() => _arm(Duration(seconds: expanded ? 15 : 5));

  void _hide({bool read = false}) {
    _dismiss?.cancel();
    final n = current;
    FocusManager.instance.primaryFocus?.unfocus();
    if (read && n != null) ref.read(notificationCenterProvider).markRead([n]);
    setState(() {
      visible = false;
      expanded = false;
    });
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted || visible) return;
      setState(() => current = null);
      _maybeShowNext();
    });
  }

  void _expand() {
    HapticFeedback.selectionClick();
    setState(() => expanded = true);
    _keepAlive();
  }

  void _open() {
    final n = current;
    if (n == null) return;
    final route = n.route;
    _hide(read: true);
    if (route != null) ref.read(routerProvider).push(route);
  }

  /// Steps aside while a picker (on the app's Navigator) is open.
  Future<T?> _aside<T>(Future<T?> Function(BuildContext navigator) open) async {
    final navigator = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
    if (navigator == null) return null;
    _dismiss?.cancel();
    setState(() => suspended = true);
    try {
      return await open(navigator);
    } finally {
      if (mounted) {
        setState(() => suspended = false);
        _keepAlive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = current;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final show = visible && !suspended && n != null;
    final compactWidth = (width - 24).clamp(200.0, 380.0);
    final expandedWidth = (width - 16).clamp(200.0, 460.0);
    return Positioned(
      top: media.padding.top + 6,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !show,
        child: Center(
          child: AnimatedSlide(
            offset: show ? Offset(0, _drag / 200) : const Offset(0, -1.6),
            duration: Duration(milliseconds: _drag == 0 ? 420 : 0),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: n == null
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: expanded ? null : _expand,
                      onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(-120.0, 60.0)),
                      onVerticalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (_drag < -24 || v < -300) {
                          _drag = 0;
                          _hide();
                        } else if (!expanded && (_drag > 18 || v > 300)) {
                          setState(() => _drag = 0);
                          _expand();
                        } else {
                          setState(() => _drag = 0);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 460),
                        curve: Curves.easeOutBack,
                        width: expanded ? expandedWidth : compactWidth,
                        decoration: BoxDecoration(
                          color: _ink,
                          borderRadius: BorderRadius.circular(expanded ? 32 : 28),
                          border: Border.all(color: Colors.white.withValues(alpha: .08)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: .55), blurRadius: 30, offset: const Offset(0, 12)),
                            BoxShadow(color: n.platform.color.withValues(alpha: .18), blurRadius: 24, spreadRadius: -6),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(expanded ? 32 : 28),
                          child: Material(
                            type: MaterialType.transparency,
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOut,
                                child: expanded
                                    ? _Expanded(
                                        key: ValueKey('x-${n.id}-${n.count}'),
                                        n: n,
                                        onOpen: _open,
                                        onClose: () => _hide(read: true),
                                        onActivity: _keepAlive,
                                        aside: _aside,
                                      )
                                    : _Compact(key: ValueKey('c-${n.id}-${n.count}'), n: n),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// -- pieces ---------------------------------------------------------------------------------

/// The sender's photo with the platform badge in the corner (or just the
/// platform tile when there's no person).
class _Face extends StatelessWidget {
  const _Face({required this.n, this.size = 34});
  final PhlioNotification n;
  final double size;

  @override
  Widget build(BuildContext context) {
    final actor = n.actor;
    final badge = size * .5;
    if (actor == null) {
      final art = n.data['image_url'] as String? ?? ((n.data['products'] as List?)?.firstOrNull as Map?)?['image_url'] as String?;
      return Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(gradient: n.platform.gradient, borderRadius: BorderRadius.circular(size * .3)),
          clipBehavior: Clip.antiAlias,
          child: art == null
              ? Icon(n.platform.icon, color: Colors.white, size: size * .56)
              : CachedNetworkImage(cacheManager: PhlioMediaCache.images, 
                  imageUrl: AppConfig.mediaUrl(art),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(n.platform.icon, color: Colors.white, size: size * .56)),
        ),
        if (art != null) Positioned(right: -4, bottom: -4, child: _Badge(n.platform, badge)),
      ]);
    }
    return Stack(clipBehavior: Clip.none, children: [
      PhlioAvatar(
          name: '${actor['display_name'] ?? actor['username'] ?? ''}',
          imageUrl: actor['avatar_url'] as String?,
          size: size,
          showMomentRing: false),
      Positioned(right: -4, bottom: -4, child: _Badge(n.platform, badge)),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.platform, this.size);
  final NotifPlatform platform;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: platform.gradient,
          shape: BoxShape.circle,
          border: Border.all(color: _ink, width: 2),
        ),
        child: Icon(platform.icon, color: Colors.white, size: size * .56),
      );
}

class _PlatformTag extends StatelessWidget {
  const _PlatformTag(this.platform);
  final NotifPlatform platform;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(5, 3, 8, 3),
        decoration: BoxDecoration(color: platform.color.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(platform.icon, size: 13, color: platform.color),
          const SizedBox(width: 4),
          Text(platform.label,
              style: TextStyle(color: platform.color, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .2)),
        ]),
      );
}

class _Compact extends StatelessWidget {
  const _Compact({required this.n, super.key});
  final PhlioNotification n;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
        child: Row(children: [
          _Face(n: n, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(
                  child: Text(n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                if (n.count > 1) ...[
                  const SizedBox(width: 6),
                  Text('${n.count}', style: TextStyle(color: n.platform.color, fontSize: 12, fontWeight: FontWeight.w800)),
                ],
              ]),
              const SizedBox(height: 1),
              Text(n.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(n.platform.icon, color: n.platform.color, size: 20),
        ]),
      );
}

class _Expanded extends StatelessWidget {
  const _Expanded({
    required this.n,
    required this.onOpen,
    required this.onClose,
    required this.onActivity,
    required this.aside,
    super.key,
  });
  final PhlioNotification n;
  final VoidCallback onOpen, onClose, onActivity;
  final Future<T?> Function<T>(Future<T?> Function(BuildContext navigator) open) aside;

  @override
  Widget build(BuildContext context) {
    final action = switch ((n.platform.id, n.kind)) {
      ('shop', 'similar_items') => _ShopItems(n: n, onActivity: onActivity),
      ('news', _) => _NewsBookmark(n: n, onActivity: onActivity),
      ('stream', 'song') => _SongPlayer(n: n, onActivity: onActivity),
      ('stream', _) => _Banner(n: n, onOpen: onOpen),
      _ when n.canReply => _Reply(n: n, onActivity: onActivity, aside: aside, onSent: onClose),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _PlatformTag(n.platform),
          const SizedBox(width: 8),
          Text(notifAgo(n.at), style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const Spacer(),
          if (n.route != null)
            _Pill(label: 'Open', onTap: onOpen),
          const SizedBox(width: 6),
          InkResponse(
            onTap: onClose,
            radius: 18,
            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, color: Colors.white54, size: 20)),
          ),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onOpen,
          behavior: HitTestBehavior.opaque,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Face(n: n, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                MentionText(n.body, style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.3)),
                if (n.count > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${n.count} new', style: TextStyle(color: n.platform.color, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ]),
        ),
        if (action != null) ...[const SizedBox(height: 12), action],
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.icon, this.color});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
        color: (color ?? Colors.white).withValues(alpha: color == null ? .1 : 1),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color == null ? Colors.white : Colors.black),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      color: color == null ? Colors.white : Colors.black, fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

String _apiError(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['detail'] is String) return d['detail'] as String;
    if (d is Map && d['error'] is Map) return '${(d['error'] as Map)['message']}';
  }
  return 'Could not do that. Try again.';
}

// -- reply (Messages, Rooms, comments) ------------------------------------------------------

class _Reply extends ConsumerStatefulWidget {
  const _Reply({required this.n, required this.onActivity, required this.aside, required this.onSent});
  final PhlioNotification n;
  final VoidCallback onActivity, onSent;
  final Future<T?> Function<T>(Future<T?> Function(BuildContext navigator) open) aside;
  @override
  ConsumerState<_Reply> createState() => _ReplyState();
}

class _ReplyState extends ConsumerState<_Reply> {
  final _text = MentionTextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  String? _done, _error;

  PhlioNotification get n => widget.n;
  String get _who => '${n.actor?['username'] ?? n.title}';

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _deliver({String text = '', Map<String, dynamic>? attachment, String? reaction}) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    widget.onActivity();
    final dio = getIt<ApiClient>().dio;
    try {
      switch (n.platform.id) {
        case 'dm':
          final peer = '${n.data['peer']}';
          if (reaction != null && n.data['message_id'] != null) {
            await dio.post('/messaging/peers/${Uri.encodeComponent(peer)}/messages/${n.data['message_id']}/reactions',
                data: {'kind': 'emoji', 'value': reaction});
          } else {
            await ref.read(messagingApiProvider).send(peer, reaction ?? text,
                attachments: [if (attachment != null) attachment]);
          }
        case 'rooms':
          await dio.post('/rooms/${n.data['room_id']}/messages', data: {
            'text': reaction ?? text,
            'attachments': [if (attachment != null) attachment],
          });
        default: // a comment: like it, or reply in its thread
          final path = '${n.data['path']}';
          final platform = path.split('/').first;
          final contentRef = path.substring(platform.length + 1);
          final base = '/social/content/$contentRef/comments';
          if (reaction == '❤️') {
            await dio.put('$base/${n.data['comment_id']}/like', queryParameters: {'platform': platform, 'liked': true});
          } else {
            await dio.post(base,
                queryParameters: {'platform': platform},
                data: FormData.fromMap({
                  'text': reaction ?? text,
                  'parent_id': n.data['comment_id'],
                  if (attachment != null) 'sticker_id': attachment['value'],
                }));
          }
      }
      HapticFeedback.mediumImpact();
      _text.clear();
      setState(() => _done = reaction != null
          ? (n.platform.id == 'dm' || (reaction == '❤️' && n.platform.id != 'rooms') ? 'Reacted $reaction' : 'Sent $reaction')
          : attachment != null
              ? 'Sent ${attachment['kind'] == 'gif' ? 'a GIF' : 'a sticker'}'
              : 'Replied to $_who');
      ref.read(notificationCenterProvider).markRead([n]);
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) widget.onSent();
      });
    } catch (e) {
      setState(() => _error = _apiError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pick(String kind) async {
    final item = await widget.aside<GiphyItem>((navigator) => showGiphyPicker(navigator, kind: kind));
    if (item == null || !mounted) return;
    await _deliver(attachment: {
      'kind': item.isFoxy ? 'sticker' : item.kind,
      'name': item.title,
      'value': item.reference,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) {
      return Row(children: [
        Icon(Icons.check_circle_rounded, color: n.platform.color, size: 20),
        const SizedBox(width: 8),
        Text(_done!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]);
    }
    final hasText = _text.text.trim().isNotEmpty;
    final comment = !const {'dm', 'rooms'}.contains(n.platform.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final e in comment ? const ['❤️', '😂', '🔥', '👏'] : _quick)
          GestureDetector(
            onTap: _sending ? null : () => _deliver(reaction: e),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .07), shape: BoxShape.circle),
              child: Text(e, style: const TextStyle(fontSize: 22)),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Container(
        height: 46,
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: !_sending,
              onChanged: (_) {
                widget.onActivity();
                setState(() {});
              },
              onTap: widget.onActivity,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) => v.trim().isEmpty ? null : _deliver(text: v.trim()),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: n.platform.color,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: comment ? 'Reply to $_who…' : 'Reply to $_who…',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 15),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              tooltip: 'Send',
              onPressed: _sending ? null : () => _deliver(text: _text.text.trim()),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.arrow_upward_rounded, color: n.platform.color),
            )
          else ...[
            IconButton(
              tooltip: 'Send a GIF',
              visualDensity: VisualDensity.compact,
              onPressed: _sending ? null : () => _pick('gif'),
              icon: const Icon(Icons.gif_box_outlined, color: Colors.white70),
            ),
            IconButton(
              tooltip: 'Send a sticker',
              visualDensity: VisualDensity.compact,
              onPressed: _sending ? null : () => _pick('sticker'),
              icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
            ),
          ],
        ]),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 6),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12.5)),
        ),
    ]);
  }
}

// -- Shop: similar items with a bag button ---------------------------------------------------

class _ShopItems extends StatefulWidget {
  const _ShopItems({required this.n, required this.onActivity});
  final PhlioNotification n;
  final VoidCallback onActivity;
  @override
  State<_ShopItems> createState() => _ShopItemsState();
}

class _ShopItemsState extends State<_ShopItems> {
  final _added = <String>{};
  final _busy = <String>{};
  String? _error;

  Future<void> _bag(Map p) async {
    final id = '${p['id']}';
    widget.onActivity();
    setState(() {
      _busy.add(id);
      _error = null;
    });
    try {
      await getIt<ApiClient>().dio.put('/shop/cart/${Uri.encodeComponent(id)}', data: {'quantity': 1});
      HapticFeedback.mediumImpact();
      setState(() => _added.add(id));
    } catch (e) {
      setState(() => _error = _apiError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  static String _price(Map p) {
    final minor = (p['price_minor_units'] as num?) ?? 0;
    final symbol = switch ('${p['currency']}'.toUpperCase()) {
      'INR' => '₹',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      final other => '$other ',
    };
    final major = minor / 100;
    return '$symbol${major == major.roundToDouble() ? major.toStringAsFixed(0) : major.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final products = (widget.n.data['products'] as List? ?? const []).whereType<Map>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 186,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final p = products[i];
            final id = '${p['id']}';
            final added = _added.contains(id);
            return Container(
              width: 132,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stack(children: [
                  SizedBox(
                    width: 132,
                    height: 104,
                    child: p['image_url'] == null
                        ? const ColoredBox(color: Color(0xFF1A1F27), child: Icon(Icons.shopping_bag_outlined, color: Colors.white38))
                        : CachedNetworkImage(cacheManager: PhlioMediaCache.images, imageUrl: AppConfig.mediaUrl('${p['image_url']}'), fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: GestureDetector(
                      onTap: added || _busy.contains(id) ? null : () => _bag(p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: added ? null : NotifPlatform.of('shop').gradient,
                          color: added ? const Color(0xFF3DD6C6) : null,
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                        ),
                        child: _busy.contains(id)
                            ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(added ? Icons.check_rounded : Icons.shopping_bag_rounded, color: Colors.white, size: 19),
                      ),
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Text('${p['title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                  child: Text(added ? 'In your bag' : _price(p),
                      style: TextStyle(
                          color: added ? const Color(0xFF3DD6C6) : NotifPlatform.of('shop').color,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
            );
          },
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12.5)),
        ),
    ]);
  }
}

// -- News: bookmark into a playlist ------------------------------------------------------------

class _NewsBookmark extends StatefulWidget {
  const _NewsBookmark({required this.n, required this.onActivity});
  final PhlioNotification n;
  final VoidCallback onActivity;
  @override
  State<_NewsBookmark> createState() => _NewsBookmarkState();
}

class _NewsBookmarkState extends State<_NewsBookmark> {
  List<Map>? _playlists;
  bool _busy = false, _naming = false;
  String? _saved, _error;
  final _name = TextEditingController();

  PhlioNotification get n => widget.n;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Existing News playlists to pick from; none yet → straight into the
  /// default "Saved" playlist.
  Future<void> _bookmark() async {
    widget.onActivity();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = ((await getIt<ApiClient>().dio.get('/playlists', queryParameters: {'platform': 'news'})).data
          as Map)['items'] as List;
      final lists = rows.whereType<Map>().toList();
      if (lists.isEmpty) {
        await _save(null);
      } else {
        setState(() => _playlists = lists);
      }
    } catch (e) {
      setState(() => _error = _apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String? playlistId) async {
    widget.onActivity();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await getIt<ApiClient>().dio.post('/playlists/save/bookmark', data: {
        'platform': 'news',
        'ref': '${n.data['ref']}',
        if (playlistId != null) 'playlist_id': playlistId,
      });
      HapticFeedback.mediumImpact();
      setState(() {
        _saved = '${(res.data as Map)['name'] ?? 'Saved'}';
        _playlists = null;
      });
    } catch (e) {
      setState(() => _error = _apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await getIt<ApiClient>().dio.post('/playlists', data: {'name': name, 'platform': 'news'});
      await _save('${(res.data as Map)['id']}');
    } catch (e) {
      setState(() {
        _error = _apiError(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = n.platform.color;
    final image = n.data['image_url'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (image != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 8,
            child: CachedNetworkImage(cacheManager: PhlioMediaCache.images, imageUrl: AppConfig.mediaUrl(image), fit: BoxFit.cover),
          ),
        ),
      const SizedBox(height: 10),
      if (_saved != null)
        Row(children: [
          Icon(Icons.bookmark_added_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Saved to “$_saved”',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ])
      else if (_playlists != null)
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Save to playlist', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _playlists!)
              _Pill(label: '${p['name']}', icon: Icons.playlist_add_rounded, onTap: _busy ? null : () => _save('${p['id']}')),
            if (!_playlists!.any((p) => p['name'] == 'Saved'))
              _Pill(label: 'Saved', icon: Icons.bookmark_rounded, onTap: _busy ? null : () => _save(null)),
            _Pill(label: 'New playlist', icon: Icons.add_rounded, onTap: _busy ? null : () => setState(() => _naming = true)),
          ]),
          if (_naming)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    onChanged: (_) => widget.onActivity(),
                    onSubmitted: (_) => _create(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Playlist name',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: .08),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Pill(label: 'Create', color: color, onTap: _busy ? null : _create),
              ]),
            ),
        ])
      else
        Row(children: [
          Expanded(
            child: Text('${n.data['publisher'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
          ),
          _Pill(
            label: _busy ? 'Saving…' : 'Bookmark',
            icon: Icons.bookmark_add_outlined,
            color: color,
            onTap: _busy ? null : _bookmark,
          ),
        ]),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12.5)),
        ),
    ]);
  }
}

// -- Stream: play a song / a title banner --------------------------------------------------------

class _SongPlayer extends ConsumerWidget {
  const _SongPlayer({required this.n, required this.onActivity});
  final PhlioNotification n;
  final VoidCallback onActivity;

  Track get _track => Track(
        id: 'phlio-${n.data['ref']}',
        title: '${n.data['title'] ?? ''}',
        artist: '${n.data['artist'] ?? ''}',
        album: 'Phlio Stream',
        uri: '${n.data['media_url'] ?? ''}',
        artUrl: n.data['image_url'] == null ? null : AppConfig.mediaUrl('${n.data['image_url']}'),
        ref: '${n.data['ref']}',
        genre: 'Music',
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    final track = _track;
    final mine = player.current?.id == track.id;
    final playing = mine && player.player.playing;
    final position = mine ? player.player.position : Duration.zero;
    final total = mine ? (player.player.duration ?? Duration.zero) : Duration.zero;
    final color = n.platform.color;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 56,
            height: 56,
            child: track.artUrl == null
                ? DecoratedBox(decoration: BoxDecoration(gradient: n.platform.gradient), child: const Icon(Icons.music_note_rounded, color: Colors.white))
                : CachedNetworkImage(cacheManager: PhlioMediaCache.images, imageUrl: track.artUrl!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(track.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: total.inMilliseconds == 0 ? 0 : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0),
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () async {
            onActivity();
            HapticFeedback.selectionClick();
            if (mine) {
              await player.toggle();
            } else {
              await player.playTracks([track]);
            }
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 30),
          ),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.n, required this.onOpen});
  final PhlioNotification n;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final image = n.data['image_url'] as String?;
    if (image == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            CachedNetworkImage(cacheManager: PhlioMediaCache.images, imageUrl: AppConfig.mediaUrl(image), fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xD9000000)]),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    if (n.data['category'] != null)
                      Text('${n.data['category']}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ]),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      color: Colors.white.withValues(alpha: .18),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.info_outline_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 5),
                        Text('Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
