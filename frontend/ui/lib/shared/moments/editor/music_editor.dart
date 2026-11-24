// Moment music — after picking a song: choose how it looks on the moment
// (vinyl, card, cover, big title, mini pill), how long the clip is
// (15 / 20 / 30 s) and which part plays, by sliding the waveform under the
// gradient window. Preview plays the clip; Done returns the song with
// `look`, `clip_start` and `clip_length`.
//
// [MusicLookSticker] draws the chosen look (composer, viewer, snaps).

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/config/app_config.dart';
import '../../../core/network/media_cache.dart';

const musicLooks = ['vinyl', 'card', 'cover', 'title', 'mini'];
const _lookIcons = {
  'vinyl': Icons.album_rounded,
  'card': Icons.view_agenda_outlined,
  'cover': Icons.crop_square_rounded,
  'title': Icons.title_rounded,
  'mini': Icons.short_text_rounded,
};
const _windowGradient = [Color(0xFFF6B93B), Color(0xFFFF8C5A), Color(0xFFE795D7), Color(0xFF8D78FF)];

Future<Map<String, dynamic>?> openMusicEditor(BuildContext context, Map<String, dynamic> song) =>
    Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MusicEditor(song: song),
    ));

class _MusicEditor extends StatefulWidget {
  const _MusicEditor({required this.song});
  final Map<String, dynamic> song;

  @override
  State<_MusicEditor> createState() => _MusicEditorState();
}

class _MusicEditorState extends State<_MusicEditor> {
  late String _look = '${widget.song['look'] ?? 'vinyl'}';
  late double _len = ((widget.song['clip_length'] as num?) ?? 20).toDouble().clamp(5.0, 30.0);
  late double _start = ((widget.song['clip_start'] as num?) ?? 20).toDouble();
  final _player = AudioPlayer();
  StreamSubscription<Duration>? _pos;
  bool _playing = false, _looping = false;
  double _progress = 0;
  static const _pxPerSec = 9.0;

  double get _duration {
    final ms = (widget.song['duration_ms'] as num?)?.toDouble();
    final s = (widget.song['duration'] as num?)?.toDouble();
    return math.max(_len + 1, ms != null ? ms / 1000 : (s ?? 180));
  }

  @override
  void initState() {
    super.initState();
    _start = _start.clamp(0.0, math.max(0.0, _duration - _len));
    _pos = _player.onPositionChanged.listen((p) {
      final t = p.inMilliseconds / 1000 - _start;
      if (t >= _len) {
        if (!_looping) {
          _looping = true;
          _play().whenComplete(() => _looping = false); // loop the clip
        }
      } else if (mounted) {
        setState(() => _progress = (t / _len).clamp(0.0, 1.0));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _pos?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final url = '${widget.song['url'] ?? ''}';
    if (url.isEmpty) return;
    try {
      await _player.play(UrlSource(AppConfig.mediaUrl(url)), position: Duration(milliseconds: (_start * 1000).round()));
      if (mounted) setState(() => _playing = true);
    } catch (_) {}
  }

  Future<void> _stop() async {
    await _player.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _progress = 0;
      });
    }
  }

  void _done() => Navigator.pop(context, {
        ...widget.song,
        'look': _look,
        'clip_start': (_start * 10).round() / 10,
        'clip_length': _len,
      });

  @override
  Widget build(BuildContext context) {
    final s = widget.song;
    final cover = s['cover_url'] as String? ?? s['image_url'] as String?;
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 17)),
              ),
              const Spacer(),
              if (cover != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 36, height: 36, child: _coverImage(cover)),
                ),
              const Spacer(),
              TextButton(
                onPressed: _done,
                child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(a), child: c)),
                child: FittedBox(
                  key: ValueKey(_look),
                  child: MusicLookSticker({...s, 'look': _look}, big: true, spinning: _playing),
                ),
              ),
            ),
          ),
          if (_look != 'card' && _look != 'mini' && _look != 'title') ...[
            Text('${s['title'] ?? 'Song'}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${s['artist'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 15)),
          ],
          const SizedBox(height: 22),
          // Looks.
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final l in musicLooks)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _look = l);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _look == l ? Colors.white : Colors.transparent),
                  child: Icon(_lookIcons[l], color: _look == l ? Colors.black : Colors.white),
                ),
              ),
          ]),
          const SizedBox(height: 18),
          // Length · progress · play/stop.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _len = _len >= 30 ? 15 : (_len >= 20 ? 30 : 20);
                    _start = _start.clamp(0.0, math.max(0.0, _duration - _len));
                  });
                  if (_playing) _play();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: Text('${_len.round()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, box) => Stack(alignment: Alignment.centerLeft, children: [
                    Container(height: 2, color: Colors.white24),
                    Container(height: 3, width: box.maxWidth * _progress, color: const Color(0xFFF6B93B)),
                  ]),
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: _playing ? _stop : _play,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  child: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.black),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          // Waveform with the clip window in the middle.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(() {
              _start = (_start - d.delta.dx / _pxPerSec).clamp(0.0, math.max(0.0, _duration - _len));
            }),
            onHorizontalDragEnd: (_) => _play(),
            child: SizedBox(
              height: 74,
              width: width,
              child: CustomPaint(
                painter: _WavePainter(
                  seed: '${s['title']}${s['artist']}'.hashCode,
                  start: _start,
                  length: _len,
                  pxPerSec: _pxPerSec,
                  duration: _duration,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text(
              '${_clock(_start)} – ${_clock(_start + _len)} · drag to choose the part',
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ),
        ]),
      ),
    );
  }

  static String _clock(double s) => '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';
}

Widget _coverImage(String url) => CachedNetworkImage(
      cacheManager: PhlioMediaCache.images,
      imageUrl: AppConfig.mediaUrl(url),
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF2A2F3A), child: Icon(Icons.music_note_rounded, color: Colors.white)),
    );

class _WavePainter extends CustomPainter {
  _WavePainter({required this.seed, required this.start, required this.length, required this.pxPerSec, required this.duration});
  final int seed;
  final double start, length, pxPerSec, duration;

  @override
  void paint(Canvas canvas, Size size) {
    final windowW = length * pxPerSec;
    final left = (size.width - windowW) / 2;
    final window = RRect.fromRectAndRadius(Rect.fromLTWH(left, 4, windowW, size.height - 8), const Radius.circular(10));
    // Bars: one every half second, positioned so `start` sits at the window's left edge.
    final rng = math.Random(seed);
    final bars = (duration * 2).ceil();
    final heights = List.generate(bars, (_) => .25 + rng.nextDouble() * .75);
    final bar = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars; i++) {
      final x = left + (i / 2 - start) * pxPerSec;
      if (x < -4 || x > size.width + 4) continue;
      final inside = x >= left && x <= left + windowW;
      final h = (size.height - 26) * heights[i];
      bar
        ..color = inside ? const Color(0xFF9AA1AE) : Colors.white
        ..strokeWidth = 3.4;
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), bar);
    }
    // Gradient frame and a white window.
    canvas.drawRRect(
        window.inflate(5),
        Paint()
          ..shader = const LinearGradient(colors: _windowGradient).createShader(window.outerRect.inflate(5)));
    canvas.drawRRect(window, Paint()..color = Colors.white);
    for (var i = 0; i < bars; i++) {
      final x = left + (i / 2 - start) * pxPerSec;
      if (x < left + 4 || x > left + windowW - 4) continue;
      final h = (size.height - 26) * heights[i];
      canvas.drawLine(
          Offset(x, size.height / 2 - h / 2),
          Offset(x, size.height / 2 + h / 2),
          bar
            ..color = const Color(0xFFD9DCE3)
            ..strokeWidth = 3.4);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.start != start || old.length != length;
}

// -- Looks ------------------------------------------------------------------------

/// The music sticker in its chosen look. [big] is the editor preview.
class MusicLookSticker extends StatelessWidget {
  const MusicLookSticker(this.d, {this.big = false, this.spinning = true, this.fallback, super.key});
  final Map d;
  final bool big, spinning;

  /// Drawn for the `card` look (the existing card sticker).
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final cover = d['cover_url'] as String? ?? d['image_url'] as String?;
    final title = '${d['title'] ?? 'Song'}';
    final artist = '${d['artist'] ?? ''}';
    switch ('${d['look'] ?? 'card'}') {
      case 'vinyl':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _Vinyl(cover: cover, size: big ? 300 : 170, spinning: spinning),
          if (!big) ...[
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, shadows: [Shadow(blurRadius: 6)])),
            Text(artist, style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: [Shadow(blurRadius: 6)])),
          ],
        ]);
      case 'cover':
        return Container(
          width: big ? 260 : 170,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: cover == null ? const ColoredBox(color: Color(0xFF8D78FF), child: Icon(Icons.music_note_rounded, color: Colors.white, size: 48)) : _coverImage(cover),
              ),
            ),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 15)),
            Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ]),
        );
      case 'title':
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: big ? 320 : 260),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 26),
            Text(title.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1, shadows: [Shadow(blurRadius: 10)])),
            const SizedBox(height: 4),
            Text(artist, style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8)])),
          ]),
        );
      case 'mini':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.music_note_rounded, color: Color(0xFFE795D7), size: 20),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text('$title · $artist',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ]),
        );
      default:
        return fallback ??
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Text('$title · $artist', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
            );
    }
  }
}

/// A turning record with the cover art as its label.
class _Vinyl extends StatefulWidget {
  const _Vinyl({required this.cover, required this.size, required this.spinning});
  final String? cover;
  final double size;
  final bool spinning;

  @override
  State<_Vinyl> createState() => _VinylState();
}

class _VinylState extends State<_Vinyl> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _c.repeat();
  }

  @override
  void didUpdateWidget(_Vinyl old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_c.isAnimating) _c.repeat();
    if (!widget.spinning && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return RotationTransition(
      turns: _c,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size.square(s), painter: _Grooves()),
          ClipOval(
            child: SizedBox(
              width: s * .5,
              height: s * .5,
              child: widget.cover == null
                  ? const DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F)])),
                      child: Icon(Icons.music_note_rounded, color: Colors.white),
                    )
                  : _coverImage(widget.cover!),
            ),
          ),
          Container(width: s * .04, height: s * .04, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle)),
        ]),
      ),
    );
  }
}

class _Grooves extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF141414));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var rr = r * .28; rr < r * .97; rr += r * .03) {
      groove.color = Colors.white.withValues(alpha: .05 + .06 * ((rr / r * 10).floor() % 2));
      canvas.drawCircle(c, rr, groove);
    }
    // Sheen.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = SweepGradient(colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .14),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .10),
            Colors.white.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)));
  }

  @override
  bool shouldRepaint(_Grooves old) => false;
}
