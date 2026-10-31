// Phlio Stream · Music — lyrics: download (LRCLIB, free & keyless), parse
// synced LRC, edit / paste your own, and a synced view that follows the
// song (tap a line to jump there). Saved per track in the music store.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_models.dart';
import 'music_player.dart';

/// One lyric line and when it starts (null for unsynced lyrics).
class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration? at; // null for plain (unsynced) lyrics
  final String text;
}

final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC (`[mm:ss.xx] text`, several stamps per line allowed) or plain
/// text into lines sorted by time. Metadata tags like `[ar:…]` are skipped.
List<LyricLine> parseLyrics(String raw) {
  final lines = <LyricLine>[];
  var synced = false;
  for (final row in raw.split(RegExp(r'\r?\n'))) {
    final stamps = _stamp.allMatches(row).toList();
    final text = row.replaceAll(_stamp, '').trim();
    if (stamps.isEmpty) {
      if (row.trim().startsWith('[') && row.contains(':') && row.trim().endsWith(']')) continue; // [ar:..] tags
      lines.add(LyricLine(null, text));
      continue;
    }
    synced = true;
    for (final m in stamps) {
      final frac = m.group(3) ?? '0';
      final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
      lines.add(LyricLine(
          Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms), text));
    }
  }
  if (synced) {
    final timed = lines.where((l) => l.at != null).toList()..sort((a, b) => a.at!.compareTo(b.at!));
    return timed;
  }
  return lines;
}

final _lrclib = Dio(BaseOptions(
  baseUrl: 'https://lrclib.net/api',
  connectTimeout: const Duration(seconds: 12),
  receiveTimeout: const Duration(seconds: 15),
  headers: {'User-Agent': 'Phlio Stream (https://github.com/Rohancherukuri/phlio)'},
));

/// Downloads lyrics (synced when available). Returns null when not found.
Future<String?> downloadLyrics(Track t) async {
  try {
    final r = await _lrclib.get('/get', queryParameters: {
      'track_name': t.title,
      'artist_name': t.artist,
      if (!t.album.contains('·')) 'album_name': t.album,
      if (t.durationMs > 0) 'duration': t.durationMs ~/ 1000,
    });
    final d = r.data as Map;
    return (d['syncedLyrics'] as String?)?.trim().isNotEmpty == true
        ? d['syncedLyrics'] as String
        : d['plainLyrics'] as String?;
  } on DioException catch (e) {
    if (e.response?.statusCode != 404) rethrow;
  }
  // Fall back to a search.
  final r = await _lrclib.get('/search', queryParameters: {'q': '${t.artist} ${t.title}'});
  final list = (r.data as List).cast<Map>();
  if (list.isEmpty) return null;
  final best = list.firstWhere((m) => (m['syncedLyrics'] as String?)?.isNotEmpty == true, orElse: () => list.first);
  return (best['syncedLyrics'] as String?) ?? best['plainLyrics'] as String?;
}

/// Synced lyrics that follow playback.
class SyncedLyricsView extends ConsumerStatefulWidget {
  const SyncedLyricsView({required this.track, this.color = Colors.white, this.compact = false, super.key});
  final Track track;
  final Color color;
  final bool compact;
  @override
  ConsumerState<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

/// Fetches lyrics when the track changes and keeps the current line centred.
class _SyncedLyricsViewState extends ConsumerState<SyncedLyricsView> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _active = -1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await downloadLyrics(widget.track);
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        setState(() => _error = 'No lyrics found for this song.');
      } else {
        ref.read(musicStoreProvider).setLyrics(widget.track.id, text);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the lyrics service.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(musicStoreProvider.select((s) => s.lyrics[widget.track.id]));
    final c = widget.color;
    if (raw == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lyrics_outlined, color: c.withValues(alpha: .6), size: 40),
          const SizedBox(height: 10),
          Text(_error ?? 'No lyrics yet', style: TextStyle(color: c.withValues(alpha: .8))),
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            FilledButton.icon(
              onPressed: _busy ? null : _download,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded),
              label: const Text('Download'),
            ),
            OutlinedButton.icon(
              onPressed: () => editLyrics(context, ref, widget.track),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Add'),
              style: OutlinedButton.styleFrom(foregroundColor: c),
            ),
          ]),
        ]),
      );
    }
    final lines = parseLyrics(raw);
    final synced = lines.isNotEmpty && lines.first.at != null;
    final player = ref.read(musicPlayerProvider);
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        var active = -1;
        if (synced) {
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].at! <= pos + const Duration(milliseconds: 250)) active = i;
          }
          if (active != _active) {
            _active = active;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = _keys[active]?.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(ctx,
                    alignment: .4, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
              }
            });
          }
        }
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0, .12, .85, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.symmetric(vertical: widget.compact ? 30 : 120, horizontal: 24),
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final on = i == active;
              final key = _keys.putIfAbsent(i, GlobalKey.new);
              return GestureDetector(
                key: key,
                onTap: lines[i].at == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        player.seek(lines[i].at!);
                      },
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: !synced ? c.withValues(alpha: .9) : (on ? c : c.withValues(alpha: .38)),
                    fontSize: widget.compact ? (on ? 19 : 16) : (on ? 26 : 21),
                    height: 1.35,
                    fontWeight: on || !synced ? FontWeight.w800 : FontWeight.w600,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Dialog to paste or edit lyrics (LRC or plain) for [t].
Future<void> editLyrics(BuildContext context, WidgetRef ref, Track t) async {
  final store = ref.read(musicStoreProvider);
  final ctrl = TextEditingController(text: store.lyrics[t.id] ?? '');
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Lyrics · ${t.title}', style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Paste plain lyrics or synced LRC lines like [01:23.45] Hello',
                style: Theme.of(sheet).textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(controller: ctrl, minLines: 8, maxLines: 14, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              TextButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Save')),
              const Spacer(),
              TextButton(
                  onPressed: () {
                    ctrl.clear();
                    Navigator.pop(sheet, true);
                  },
                  child: const Text('Remove')),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (saved == true) store.setLyrics(t.id, ctrl.text);
  ctrl.dispose();
}
