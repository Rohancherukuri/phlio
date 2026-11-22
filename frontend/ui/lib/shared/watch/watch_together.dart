// Watch together — one synced player for a whole chat or call.
//
//   Phlio Social (DMs and DM calls): posts, videos and clips.
//   Phlio Rooms (channel or voice): posts, videos, clips and all of Phlio
//   Stream — movies, series, anime and music.
//
// [WatchStage]       the shared player. Everyone sees the same thing at the
//                    same moment: it polls the party (GET /watch/…) every
//                    second and corrects drift over 1.5 s; play / pause /
//                    seek by anyone goes to everyone. Reactions float up over
//                    the player for all viewers, and the viewers' faces sit
//                    on top. Shown inside calls (RealtimeScreen) and in
//                    [WatchPartyScreen].
// [WatchPartyScreen] Instagram's "watch together" layout: the player on top,
//                    everyone watching as tiles below, reactions, change
//                    title, end.
// [showWatchPicker]  choose what to watch (tabs per kind, search).
// [WatchChatCard]    the "🍿 Watching … together · Join" card in the chat.
//
// Backend: backend/app/api/v1/watch_party.py.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/widgets/phlio_card.dart';

/// Where the party lives: `dm/<username>`, `call/<callId>` or `room/<roomId>`.
class WatchCtx {
  const WatchCtx(this.ctx, this.target, {this.title = ''});
  final String ctx, target, title;
  bool get rooms => ctx == 'room';
  String get path => '/watch/$ctx/${Uri.encodeComponent(target)}';
}

Future<Map<String, dynamic>?> _fetchParty(WatchCtx w) async {
  final res = await getIt<ApiClient>().dio.get(w.path);
  final p = (res.data as Map)['party'];
  return p == null ? null : (p as Map).cast<String, dynamic>();
}

Future<Map<String, dynamic>?> _postParty(WatchCtx w, String action, [Map<String, dynamic>? body]) async {
  final res = await getIt<ApiClient>().dio.post('${w.path}/$action', data: body ?? const {});
  final p = (res.data as Map)['party'];
  return p == null ? null : (p as Map).cast<String, dynamic>();
}

String _media(String? url) => url == null || url.isEmpty ? '' : AppConfig.mediaUrl(url);

// -- picker ------------------------------------------------------------------------------------------

/// Choose what to watch; starts the party. Returns true when started.
Future<bool> showWatchPicker(BuildContext context, WatchCtx w) async {
  final started = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    backgroundColor: PhlioColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => FractionallySizedBox(heightFactor: .88, child: _Picker(w: w)),
  );
  return started == true;
}

class _Picker extends StatefulWidget {
  const _Picker({required this.w});
  final WatchCtx w;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late final _kinds = widget.w.rooms
      ? const [('all', 'All'), ('post', 'Posts'), ('video', 'Videos'), ('clip', 'Clips'), ('movie', 'Movies'),
          ('series', 'Series'), ('anime', 'Anime'), ('song', 'Music')]
      : const [('all', 'All'), ('post', 'Posts'), ('video', 'Videos'), ('clip', 'Clips')];
  String _kind = 'all', _q = '';
  Timer? _debounce;
  Future<List<Map>>? _items;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _load() {
    final future = getIt<ApiClient>()
        .dio
        .get('/watch/library', queryParameters: {'ctx': widget.w.ctx, 'kind': _kind, 'q': _q})
        .then((r) => ((r.data as Map)['items'] as List).cast<Map>());
    setState(() {
      _items = future;
    });
  }

  Future<void> _start(Map item) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await _postParty(widget.w, 'start', {'platform': item['platform'], 'ref': item['ref']});
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not start watching that.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
          child: Row(children: [
            const Icon(Icons.smart_display_rounded, color: Color(0xFFFF4D5E)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.w.rooms ? 'Watch together in this room' : 'Watch together',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: TextField(
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _q = v.trim();
                _load();
              });
            },
            decoration: InputDecoration(
              hintText: widget.w.rooms ? 'Search posts, clips, movies, shows, music…' : 'Search posts, videos and clips',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              for (final (id, label) in _kinds)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _kind == id,
                    onSelected: (_) {
                      _kind = id;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map>>(
            future: _items,
            builder: (context, snap) {
              if (snap.hasError) return const Center(child: Text('Could not load. Pull to retry.'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final items = snap.data!;
              if (items.isEmpty) return const Center(child: Text('Nothing here yet.', style: TextStyle(color: Colors.white54)));
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .62),
                itemCount: items.length,
                itemBuilder: (_, i) => _PickTile(item: items[i], onTap: () => _start(items[i])),
              );
            },
          ),
        ),
      ]);
}

class _PickTile extends StatelessWidget {
  const _PickTile({required this.item, required this.onTap});
  final Map item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final image = _media(item['image_url'] as String?);
    final kind = '${item['kind']}';
    final icon = switch (kind) {
      'song' => Icons.music_note_rounded,
      'movie' => Icons.movie_rounded,
      'series' || 'anime' => Icons.live_tv_rounded,
      'clip' => Icons.slow_motion_video_rounded,
      'video' => Icons.play_circle_fill_rounded,
      _ => Icons.photo_rounded,
    };
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              if (image.isNotEmpty)
                CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, errorWidget: (_, __, ___) => _fallback(icon))
              else
                _fallback(icon),
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 14, color: Colors.white),
                ),
              ),
              if (item['playable'] != true)
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Poster only', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: Colors.white70)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 5),
        Text('${item['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _fallback(IconData icon) => DecoratedBox(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2A2350), Color(0xFF13182A)])),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${item['title']}', maxLines: 5, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        ),
      );
}

// -- the shared player -------------------------------------------------------------------------------

class WatchStage extends StatefulWidget {
  const WatchStage({required this.w, this.compact = false, this.onParty, super.key});
  final WatchCtx w;

  /// Inside a call: hides itself when nothing is playing.
  final bool compact;

  /// Told after every update (is a party on?) so the layout around adapts.
  final ValueChanged<bool>? onParty;

  @override
  State<WatchStage> createState() => WatchStageState();
}

class WatchStageState extends State<WatchStage> {
  Map<String, dynamic>? _party;
  VideoPlayerController? _video;
  String? _loaded;
  Timer? _poll;
  DateTime _quietUntil = DateTime(0);
  final _seen = <String>{};
  final _floating = <({String id, String emoji, double x})>[];
  bool _busy = false;

  Map<String, dynamic>? get party => _party;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      _apply(await _fetchParty(widget.w));
    } catch (_) {
      // Offline for a moment: keep playing locally.
    } finally {
      _busy = false;
    }
  }

  Future<void> _apply(Map<String, dynamic>? p) async {
    if (!mounted) return;
    setState(() => _party = p);
    widget.onParty?.call(p != null);
    if (p == null) {
      await _video?.pause();
      return;
    }
    final item = (p['item'] as Map).cast<String, dynamic>();
    final media = _media(item['media_url'] as String?);
    final key = '${item['platform']}/${item['ref']}/$media';
    if (key != _loaded) {
      _loaded = key;
      final old = _video;
      _video = null;
      await old?.dispose();
      if (media.isNotEmpty) {
        final c = VideoPlayerController.networkUrl(Uri.parse(media));
        _video = c;
        try {
          await c.initialize();
          await c.setLooping('${item['kind']}' == 'clip');
        } catch (_) {}
        if (mounted) setState(() {});
      }
    }
    // Floating reactions.
    for (final r in (p['reactions'] as List? ?? const []).cast<Map>()) {
      final id = '${r['id']}';
      if (_seen.add(id)) {
        final x = (id.hashCode % 70) / 100 + .1;
        setState(() => _floating.add((id: id, emoji: '${r['emoji']}', x: x)));
        Future<void>.delayed(const Duration(milliseconds: 2600), () {
          if (mounted) setState(() => _floating.removeWhere((f) => f.id == id));
        });
      }
    }
    final c = _video;
    if (c == null || !c.value.isInitialized || DateTime.now().isBefore(_quietUntil)) return;
    final want = Duration(milliseconds: (p['position_ms'] as num).toInt());
    final playing = p['playing'] == true;
    final drift = (c.value.position - want).inMilliseconds.abs();
    if (drift > 1500 && want < c.value.duration) await c.seekTo(want);
    if (playing && !c.value.isPlaying) await c.play();
    if (!playing && c.value.isPlaying) await c.pause();
  }

  Future<void> _control(String action, [Duration? at]) async {
    final c = _video;
    final position = at ?? c?.value.position ?? Duration.zero;
    _quietUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    HapticFeedback.selectionClick();
    if (c != null) {
      if (action == 'play') await c.play();
      if (action == 'pause') await c.pause();
      if (at != null) await c.seekTo(at);
    }
    try {
      final p = await _postParty(widget.w, 'control', {'action': action, 'position_ms': position.inMilliseconds});
      if (mounted) setState(() => _party = p);
    } catch (_) {}
  }

  Future<void> react(String emoji) async {
    HapticFeedback.lightImpact();
    try {
      _apply(await _postParty(widget.w, 'react', {'emoji': emoji}));
    } catch (_) {}
  }

  Future<void> end() async {
    try {
      await getIt<ApiClient>().dio.delete(widget.w.path);
    } catch (_) {}
    _apply(null);
  }

  @override
  Widget build(BuildContext context) {
    final p = _party;
    if (p == null) {
      if (widget.compact) return const SizedBox.shrink();
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
          child: Center(
            child: FilledButton.icon(
              onPressed: () async {
                if (await showWatchPicker(context, widget.w)) _refresh();
              },
              icon: const Icon(Icons.smart_display_rounded),
              label: const Text('Pick something to watch'),
            ),
          ),
        ),
      );
    }
    final item = (p['item'] as Map).cast<String, dynamic>();
    final c = _video;
    final ready = c != null && c.value.isInitialized;
    final ratio = ready ? c!.value.aspectRatio : ('${item['kind']}' == 'clip' ? 9 / 16 : 16 / 9);
    final viewers = (p['viewers'] as List? ?? const []).cast<Map>();
    return LayoutBuilder(builder: (context, box) {
      final maxH = widget.compact ? 260.0 : MediaQuery.sizeOf(context).height * .55;
      var w = box.maxWidth;
      var h = w / ratio;
      if (h > maxH) {
        h = maxH;
        w = h * ratio;
      }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.compact ? 14 : 20),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Colors.black),
                if (ready)
                  FittedBox(fit: BoxFit.contain, child: SizedBox(width: c!.value.size.width, height: c.value.size.height, child: VideoPlayer(c)))
                else
                  _Poster(item: item),
                if (ready && '${item['kind']}' == 'song') _Poster(item: item, music: true),
                // Faces of everyone watching.
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(children: [
                    for (final v in viewers.take(5))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: PhlioAvatar(
                            name: '${v['display_name'] ?? v['username'] ?? ''}',
                            imageUrl: v['avatar_url'] as String?,
                            size: 24,
                            showMomentRing: false),
                      ),
                  ]),
                ),
                for (final f in _floating) _FloatingEmoji(key: ValueKey(f.id), emoji: f.emoji, x: f.x),
                if (ready)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _Controls(
                      video: c!,
                      onPlay: () => _control(c.value.isPlaying ? 'pause' : 'play'),
                      onSeek: (d) => _control('seek', d),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.groups_rounded, size: 16, color: Colors.white60),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${item['title']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () async {
                if (await showWatchPicker(context, widget.w)) _refresh();
              },
              child: const Text('Change'),
            ),
          ]),
        ),
      ]);
    });
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item, this.music = false});
  final Map<String, dynamic> item;
  final bool music;
  @override
  Widget build(BuildContext context) {
    final image = _media(item['image_url'] as String?);
    return Stack(fit: StackFit.expand, children: [
      if (image.isNotEmpty) CachedNetworkImage(imageUrl: image, fit: music ? BoxFit.cover : BoxFit.contain),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: .85)],
          ),
        ),
      ),
      Positioned(
        left: 14,
        right: 14,
        bottom: 46,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${item['title']}', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          if ('${item['description'] ?? ''}'.isNotEmpty && !music)
            Text('${item['description']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
          if ((item['media_url'] ?? '').toString().isEmpty && item['object_type'] != 'social.post')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Not playable in Phlio — you’re viewing its page together.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
        ]),
      ),
    ]);
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.video, required this.onPlay, required this.onSeek});
  final VideoPlayerController video;
  final VoidCallback onPlay;
  final ValueChanged<Duration> onSeek;

  String _t(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: video,
        builder: (_, v, __) {
          final total = v.duration.inMilliseconds;
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
            ),
            child: Row(children: [
              IconButton(
                onPressed: onPlay,
                icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
              ),
              Text(_t(v.position), style: const TextStyle(color: Colors.white, fontSize: 11.5)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                  child: Slider(
                    value: total == 0 ? 0 : v.position.inMilliseconds.clamp(0, total).toDouble(),
                    max: total == 0 ? 1 : total.toDouble(),
                    activeColor: const Color(0xFFFF4D5E),
                    onChanged: total == 0 ? null : (x) => video.seekTo(Duration(milliseconds: x.round())),
                    onChangeEnd: total == 0 ? null : (x) => onSeek(Duration(milliseconds: x.round())),
                  ),
                ),
              ),
              Text(_t(v.duration), style: const TextStyle(color: Colors.white, fontSize: 11.5)),
              const SizedBox(width: 10),
            ]),
          );
        },
      );
}

class _FloatingEmoji extends StatelessWidget {
  const _FloatingEmoji({required this.emoji, required this.x, super.key});
  final String emoji;
  final double x;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 2500),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => Align(
          alignment: Alignment(x * 2 - 1, 1 - 1.9 * t),
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Transform.scale(scale: .8 + .8 * t, child: Text(emoji, style: const TextStyle(fontSize: 30))),
          ),
        ),
      );
}

/// Quick reactions for the party.
class WatchReactions extends StatelessWidget {
  const WatchReactions({required this.onReact, super.key});
  final ValueChanged<String> onReact;
  static const _emoji = ['😂', '😍', '🔥', '😮', '😢', '👏'];
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final e in _emoji)
          InkResponse(
            onTap: () => onReact(e),
            radius: 26,
            child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 26))),
          ),
      ]);
}

// -- full screen ---------------------------------------------------------------------------------------

class WatchPartyScreen extends StatefulWidget {
  const WatchPartyScreen({required this.w, this.pickFirst = false, super.key});
  final WatchCtx w;

  /// Open the picker straight away (starting a new party).
  final bool pickFirst;

  @override
  State<WatchPartyScreen> createState() => _WatchPartyScreenState();
}

class _WatchPartyScreenState extends State<WatchPartyScreen> {
  final _stage = GlobalKey<WatchStageState>();

  @override
  void initState() {
    super.initState();
    unawaited(_postParty(widget.w, 'join').then((_) {}, onError: (_) {}));
    if (widget.pickFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final ok = await showWatchPicker(context, widget.w);
        if (!ok && mounted && _stage.currentState?.party == null) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    unawaited(_postParty(widget.w, 'leave').then((_) {}, onError: (_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final party = _stage.currentState?.party;
    final viewers = (party?['viewers'] as List? ?? const []).cast<Map>();
    return Scaffold(
      backgroundColor: const Color(0xFF05070C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Watching together', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (widget.w.title.isNotEmpty) Text(widget.w.title, style: const TextStyle(fontSize: 12.5, color: Colors.white60)),
        ]),
        actions: [
          IconButton(
            tooltip: 'End for everyone',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () async {
              await _stage.currentState?.end();
              if (context.mounted) Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: WatchStage(key: _stage, w: widget.w, onParty: (_) => setState(() {})),
          ),
          const Spacer(),
          // Everyone watching, as tiles (Instagram's co-watching layout).
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: viewers.isEmpty ? 1 : viewers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final v = viewers.isEmpty ? null : viewers[i];
                return Container(
                  width: 110,
                  decoration: BoxDecoration(color: const Color(0xFF1A1D24), borderRadius: BorderRadius.circular(20)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    PhlioAvatar(
                        name: '${v?['display_name'] ?? v?['username'] ?? 'You'}',
                        imageUrl: v?['avatar_url'] as String?,
                        size: 60,
                        showMomentRing: false),
                    const SizedBox(height: 8),
                    Text('${v?['display_name'] ?? v?['username'] ?? 'Waiting…'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          WatchReactions(onReact: (e) => _stage.currentState?.react(e)),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

/// Opens the party for a chat (starting one when nothing is playing).
Future<void> openWatchTogether(BuildContext context, WatchCtx w) async {
  Map<String, dynamic>? current;
  try {
    current = await _fetchParty(w);
  } catch (_) {}
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    builder: (_) => WatchPartyScreen(w: w, pickFirst: current == null),
  ));
}

// -- chat card ----------------------------------------------------------------------------------------------

/// "phlio-watch:<ctx>" marker in a chat message.
bool isWatchMessage(String? text) => (text ?? '').contains('phlio-watch:');

class WatchChatCard extends StatelessWidget {
  const WatchChatCard({required this.text, required this.w, this.compact = false, super.key});
  final String text;
  final WatchCtx w;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final title = text.split('\n').first;
    return Material(
      color: const Color(0xFF151A24),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openWatchTogether(context, w),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFF4D5E).withValues(alpha: .35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF4D5E), Color(0xFF8D78FF)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.smart_display_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title.replaceFirst('🍿 ', ''),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const Text('Tap to join', style: TextStyle(color: Color(0xFF3DD6A0), fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
