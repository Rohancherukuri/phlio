// Voice notes and song snippets in comments (every comment thread: Social,
// Phlio Move activities, Stream, Book, Shop, News).
//
//   [CommentVoiceRecorder]  inline recorder above the comment box (≤ 60 s)
//   [CommentVoicePlayer]    a voice note in a comment
//   [CommentSongPlayer]     a 30-second song clip in a comment

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app/config/app_config.dart';
import '../../core/network/media_cache.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';

const kCommentVoiceSeconds = 60;
const kCommentSongSeconds = 30;

String _clock(num seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Records straight away; [onDone] gets the file and its length, [onCancel]
/// throws the take away.
class CommentVoiceRecorder extends StatefulWidget {
  const CommentVoiceRecorder({required this.onDone, required this.onCancel, super.key});
  final void Function(String path, double seconds) onDone;
  final VoidCallback onCancel;

  @override
  State<CommentVoiceRecorder> createState() => _CommentVoiceRecorderState();
}

class _CommentVoiceRecorderState extends State<CommentVoiceRecorder> {
  final _rec = AudioRecorder();
  final _watch = Stopwatch();
  Timer? _tick;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = 'Allow the microphone to record a voice note.');
        return;
      }
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/comment_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, noiseSuppress: true, echoCancel: true), path: _path!);
      _watch.start();
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        if (_watch.elapsed.inSeconds >= kCommentVoiceSeconds) {
          _stop();
        } else {
          setState(() {});
        }
      });
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = 'Recording isn’t available on this device.');
    }
  }

  Future<void> _stop() async {
    _tick?.cancel();
    _watch.stop();
    final path = await _rec.stop() ?? _path;
    final secs = _watch.elapsedMilliseconds / 1000;
    if (path == null || secs < 0.8) {
      widget.onCancel();
      return;
    }
    widget.onDone(path, secs);
  }

  Future<void> _cancel() async {
    _tick?.cancel();
    try {
      await _rec.cancel();
    } catch (_) {}
    widget.onCancel();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = _watch.elapsed.inMilliseconds / 1000;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: PhlioColors.surfaceInput, borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        IconButton(tooltip: 'Discard', onPressed: _cancel, icon: const Icon(Icons.delete_outline_rounded)),
        if (_error != null)
          Expanded(child: Text(_error!, style: PhlioTypography.caption))
        else ...[
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: PhlioColors.danger, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_clock(secs), style: PhlioTypography.bodyStrong),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: secs / kCommentVoiceSeconds, minHeight: 4),
            ),
          ),
          IconButton(
            tooltip: 'Stop',
            onPressed: _stop,
            icon: const Icon(Icons.stop_circle_rounded, size: 30, color: PhlioColors.brandPeach),
          ),
        ],
      ]),
    );
  }
}

/// Plays a recorded voice note (local file before sending, url after).
class CommentVoicePlayer extends StatefulWidget {
  const CommentVoicePlayer({this.url, this.path, this.seconds, super.key});
  final String? url, path;
  final double? seconds;

  @override
  State<CommentVoicePlayer> createState() => _CommentVoicePlayerState();
}

class _CommentVoicePlayerState extends State<CommentVoicePlayer> {
  final _player = AudioPlayer();
  Duration _pos = Duration.zero, _len = Duration.zero;
  bool _playing = false;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _pos = p);
      }))
      ..add(_player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _len = d);
      }))
      ..add(_player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playing = false;
            _pos = Duration.zero;
          });
        }
      }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    if (_pos > Duration.zero) {
      await _player.resume();
    } else if (widget.path != null) {
      await _player.play(DeviceFileSource(widget.path!));
    } else {
      // Voice notes are cached like clips, so replays don't re-download.
      final file = await PhlioMediaCache.videos.getSingleFile(AppConfig.mediaUrl(widget.url!));
      await _player.play(DeviceFileSource(file.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _len > Duration.zero ? _len.inMilliseconds / 1000 : (widget.seconds ?? 0);
    final frac = total > 0 ? (_pos.inMilliseconds / 1000 / total).clamp(0.0, 1.0) : 0.0;
    return Container(
      width: 230,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
      decoration: BoxDecoration(color: PhlioColors.surfaceInput, borderRadius: BorderRadius.circular(24)),
      child: Row(children: [
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play voice note',
          onPressed: _toggle,
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: PhlioColors.brandPeach),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: frac, minHeight: 4),
          ),
        ),
        const SizedBox(width: 10),
        Text(_clock(_playing || _pos > Duration.zero ? _pos.inMilliseconds / 1000 : total), style: PhlioTypography.caption),
      ]),
    );
  }
}

/// A song clip: artwork, title, artist, and a play button that plays the
/// chosen 30 seconds.
class CommentSongPlayer extends StatefulWidget {
  const CommentSongPlayer({required this.music, this.onRemove, super.key});
  final Map music;
  final VoidCallback? onRemove;

  @override
  State<CommentSongPlayer> createState() => _CommentSongPlayerState();
}

class _CommentSongPlayerState extends State<CommentSongPlayer> {
  final _player = AudioPlayer();
  StreamSubscription? _sub;
  bool _playing = false;
  double _progress = 0;

  double get _start => ((widget.music['clip_start'] as num?) ?? 0).toDouble();
  double get _length {
    final v = ((widget.music['clip_length'] as num?) ?? kCommentSongSeconds).toDouble();
    return v < 1 ? 1 : (v > kCommentSongSeconds ? kCommentSongSeconds.toDouble() : v);
  }

  @override
  void initState() {
    super.initState();
    _sub = _player.onPositionChanged.listen((p) {
      final t = p.inMilliseconds / 1000 - _start;
      if (t >= _length) {
        _stop();
      } else if (mounted) {
        setState(() => _progress = (t / _length).clamp(0.0, 1.0));
      }
    });
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

  Future<void> _toggle() async {
    if (_playing) return _stop();
    final url = '${widget.music['url'] ?? ''}';
    if (url.isEmpty) return;
    setState(() => _playing = true);
    try {
      await _player.play(UrlSource(AppConfig.mediaUrl(url)), position: Duration(milliseconds: (_start * 1000).round()));
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.music;
    final image = m['image_url'] as String?;
    return Container(
      width: 260,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: PhlioColors.surfaceInput, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 46,
            height: 46,
            child: image == null || image.isEmpty
                ? const ColoredBox(color: PhlioColors.surfaceElevated, child: Icon(Icons.music_note_rounded))
                : phlioNetworkImage(AppConfig.mediaUrl(image),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: PhlioColors.surfaceElevated, child: Icon(Icons.music_note_rounded))),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${m['title'] ?? 'Song'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.bodyStrong),
            Text('${m['artist'] ?? ''} · ${_length.round()}s', maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.caption),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: _progress, minHeight: 3),
            ),
          ]),
        ),
        IconButton(
          tooltip: _playing ? 'Stop' : 'Play clip',
          onPressed: _toggle,
          icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: PhlioColors.brandPeach),
        ),
        if (widget.onRemove != null)
          IconButton(tooltip: 'Remove song', onPressed: widget.onRemove, icon: const Icon(Icons.close_rounded, size: 18)),
      ]),
    );
  }
}

/// Deletes a local recording once it's sent or discarded.
void deleteVoiceFile(String? path) {
  if (path == null) return;
  try {
    File(path).deleteSync();
  } catch (_) {}
}
