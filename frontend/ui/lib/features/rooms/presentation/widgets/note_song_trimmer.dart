// "New song" sheet (Instagram's clip picker): artwork, title and artists,
// where your clip sits in the whole song, the clip length (15 or 30 s), a
// play / stop button, and a waveform you drag under a fixed gradient window
// to choose which part plays. The clip loops while you choose. Done returns
// the song with `clip_start` and `clip_length` (seconds).

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';

const _done = Color(0xFF6C72FF);
const _windowGradient = [Color(0xFFFFD600), Color(0xFFFF7A00), Color(0xFFFF0069), Color(0xFFD300C5), Color(0xFF7638FA)];

/// The playable source for a picked song, or null (Spotify: no audio here).
Source? songSource(Map music) {
  if (music['source'] == 'spotify') return null;
  if (music['path'] != null) return DeviceFileSource('${music['path']}');
  if (music['bytes'] is Uint8List) return BytesSource(music['bytes'] as Uint8List);
  final url = '${music['url'] ?? ''}';
  return url.isEmpty ? null : UrlSource(AppConfig.mediaUrl(url));
}

Future<Map<String, dynamic>?> showSongTrimmer(BuildContext context, Map<String, dynamic> music) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1F26),
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _SongTrimmer(music: music),
    );

class _SongTrimmer extends StatefulWidget {
  const _SongTrimmer({required this.music});
  final Map<String, dynamic> music;

  @override
  State<_SongTrimmer> createState() => _SongTrimmerState();
}

class _SongTrimmerState extends State<_SongTrimmer> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<Object?>>[];
  late double start = (widget.music['clip_start'] as num?)?.toDouble() ?? 0;
  late int length = ((widget.music['clip_length'] as num?)?.toInt() ?? 30).clamp(5, 30);
  late double duration = _knownDuration();
  double position = 0; // seconds into the song
  bool playing = false, ready = false;
  Source? source;

  static const _windowWidth = 150.0;
  static const _barGap = 9.0;
  double get _pps => _windowWidth / length; // pixels per second

  double _knownDuration() {
    final ms = (widget.music['duration_ms'] as num?)?.toDouble();
    if (ms != null && ms > 0) return ms / 1000;
    final s = (widget.music['duration'] as num?)?.toDouble();
    return s != null && s > 0 ? s : 180;
  }

  @override
  void initState() {
    super.initState();
    source = songSource(widget.music);
    _subs.add(_player.onDurationChanged.listen((d) {
      if (d.inMilliseconds > 0 && mounted) {
        setState(() {
          duration = d.inMilliseconds / 1000;
          start = start.clamp(0, math.max(0, duration - length)).toDouble();
        });
      }
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      final s = p.inMilliseconds / 1000;
      if (!mounted) return;
      // Loop the chosen clip.
      if (playing && (s >= start + length || s < start - 1)) {
        _player.seek(Duration(milliseconds: (start * 1000).round()));
      }
      setState(() => position = s);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (playing) _playFromStart();
    }));
    if (source != null) _playFromStart();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _playFromStart() async {
    final src = source;
    if (src == null) return;
    try {
      if (!ready) {
        await _player.setSource(src);
        ready = true;
      }
      await _player.seek(Duration(milliseconds: (start * 1000).round()));
      await _player.resume();
      if (mounted) setState(() => playing = true);
    } catch (_) {
      if (mounted) setState(() => playing = false);
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (playing) {
      await _player.pause();
      setState(() => playing = false);
    } else {
      await _playFromStart();
    }
  }

  void _drag(double dx) {
    final maxStart = math.max(0.0, duration - length);
    setState(() => start = (start - dx / _pps).clamp(0, maxStart).toDouble());
  }

  void _toggleLength() {
    HapticFeedback.selectionClick();
    setState(() {
      length = length == 30 ? 15 : 30;
      start = start.clamp(0, math.max(0, duration - length)).toDouble();
    });
    if (playing) _playFromStart();
  }

  String _clock(double s) => '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final m = widget.music;
    final art = m['image_url'] as String?;
    final explicit = m['explicit'] == true;
    final maxStart = math.max(1.0, duration - length);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
            child: Row(children: [
              const Expanded(child: Text('New song', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500))),
              TextButton(
                onPressed: () => Navigator.pop(context, {...m, 'clip_start': (start * 10).round() / 10, 'clip_length': length}),
                child: const Text('Done', style: TextStyle(color: _done, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          // Artwork with a white frame.
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 58,
                child: art == null || art.isEmpty
                    ? const ColoredBox(color: PhlioColors.surfaceElevated, child: Icon(Icons.music_note_rounded))
                    : CachedNetworkImage(imageUrl: AppConfig.mediaUrl(art), fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: Text('${m['title']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              ),
              if (explicit) ...[const SizedBox(width: 6), const _ExplicitBadge()],
            ]),
          ),
          const SizedBox(height: 2),
          Text('${m['artist'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 14),
          // Where the clip sits in the whole song; dots jump to a quarter / half.
          SizedBox(
            width: 230,
            height: 14,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              final x = (start / maxStart).clamp(0.0, 1.0) * (w - 16);
              return Stack(alignment: Alignment.centerLeft, children: [
                Container(height: 1.5, color: Colors.white24),
                for (final f in const [0.25, 0.5])
                  Positioned(
                    left: f * (w - 16) + 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => start = (f * (duration - length)).clamp(0, maxStart).toDouble());
                        if (playing) _playFromStart();
                      },
                      child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFFF0069), shape: BoxShape.circle)),
                    ),
                  ),
                Positioned(
                  left: x,
                  child: Container(width: 16, height: 6, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3))),
                ),
              ]);
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 8, 36, 10),
            child: Row(children: [
              // Clip length: tap to switch 30 s / 15 s.
              InkWell(
                onTap: _toggleLength,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 1.5)),
                  child: Text('$length', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                ),
              ),
              Expanded(
                child: Text(
                  source == null
                      ? 'Preview plays in Spotify'
                      : '${_clock(start)} – ${_clock(math.min(duration, start + length))}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ),
              Material(
                color: source == null ? Colors.white24 : Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: source == null ? null : _toggle,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 26),
                  ),
                ),
              ),
            ]),
          ),
          // Waveform strip: drag the song under the fixed window.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _player.pause(),
            onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
            onHorizontalDragEnd: (_) {
              HapticFeedback.selectionClick();
              if (source != null) _playFromStart();
            },
            child: SizedBox(
              height: 74,
              width: double.infinity,
              child: CustomPaint(
                painter: _WavePainter(
                  seed: '${m['title']}${m['artist']}'.hashCode,
                  start: start,
                  length: length,
                  duration: duration,
                  pps: _pps,
                  windowWidth: _windowWidth,
                  gap: _barGap,
                  progress: playing ? ((position - start) / length).clamp(0.0, 1.0) : null,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ExplicitBadge extends StatelessWidget {
  const _ExplicitBadge();

  @override
  Widget build(BuildContext context) => Container(
        width: 17,
        height: 17,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
        child: const Text('E', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
      );
}

/// Bars for the whole song scrolled so the window (centre of the strip)
/// covers `start .. start+length`. Bar heights are a stable pattern per
/// song (decoding the real waveform on the phone would cost seconds).
class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.seed,
    required this.start,
    required this.length,
    required this.duration,
    required this.pps,
    required this.windowWidth,
    required this.gap,
    required this.progress,
  });

  final int seed, length;
  final double start, duration, pps, windowWidth, gap;
  final double? progress;

  double _height(int i) {
    final r = math.Random(seed ^ (i * 2654435761));
    final pattern = [0.55, 0.85, 0.45, 1.0, 0.6, 0.75];
    return pattern[i % pattern.length] * (0.75 + 0.25 * r.nextDouble());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final left = cx - windowWidth / 2, right = cx + windowWidth / 2;
    final window = RRect.fromLTRBR(left, 4, right, size.height - 4, const Radius.circular(10));
    // Window background.
    canvas.drawRRect(window.deflate(4), Paint()..color = Colors.white);
    // Song x for time t: left + (t - start) * pps.
    final first = ((start - left / pps) * pps / gap).floor() - 1;
    final last = ((start + (size.width - left) / pps) * pps / gap).ceil() + 1;
    final playX = progress == null ? null : left + progress! * windowWidth;
    for (var i = math.max(0, first); i <= last; i++) {
      final t = i * gap / pps;
      if (t > duration) break;
      final x = left + (t - start) * pps;
      if (x < -4 || x > size.width + 4) continue;
      final h = (size.height - 26) * _height(i);
      final inside = x > left + 6 && x < right - 6;
      final paint = Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = inside ? const Color(0xFFCDD0D6) : const Color(0xFF6B7079);
      if (inside && playX != null && (x - playX).abs() < gap / 2) {
        paint.shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF7A00), Color(0xFFFF0069), Color(0xFFD300C5)],
        ).createShader(Rect.fromLTWH(x - 2, size.height / 2 - h / 2, 4, h));
      }
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), paint);
    }
    // Gradient frame.
    canvas.drawRRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..shader = const LinearGradient(colors: _windowGradient).createShader(window.outerRect),
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.start != start || old.progress != progress || old.length != length || old.duration != duration;
}
