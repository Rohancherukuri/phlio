// Instagram-style music picker for notes: a search box, tabs (For you,
// Trending, Saved, Spotify, Your music), rows with artwork, title, explicit
// badge, artist · length and a bookmark. Tapping a row plays it and shows
// the mini player at the bottom; tapping it again (or the arrow) opens the
// "New song" clip picker. Returns the song with clip_start / clip_length.

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';
import '../../../../shared/content/content_surface.dart' show catalogProvider;
import '../../../../shared/content/stream_screen.dart' show streamCategory;
import '../../../../shared/music/song_picker.dart';
import 'note_music_picker.dart' show pickSongFile, kSpotifyGreen;
import 'note_song_trimmer.dart';
import 'package:phlio/core/network/media_cache.dart';

/// Songs you bookmarked in the picker (this session).
final savedNoteSongsProvider = StateProvider<Map<String, Map<String, dynamic>>>((ref) => const {});

Future<Map<String, dynamic>?> showNoteSongPicker(BuildContext context) => showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _NoteSongPicker(),
    );

Map<String, dynamic> _fromCatalog(Map item) => {
      'title': '${item['title'] ?? 'Untitled'}',
      'artist': '${item['publisher'] ?? item['artist'] ?? 'Phlio Stream'}',
      'url': '${item['media_url']}',
      if (item['image_url'] != null) 'image_url': item['image_url'],
      'ref': '${item['ref']}',
      if (item['explicit'] == true) 'explicit': true,
      if (item['duration'] is num) 'duration': item['duration'],
      if (item['duration_ms'] is num) 'duration_ms': item['duration_ms'],
      'source': 'stream',
    };

String _length(Map song) {
  final ms = (song['duration_ms'] as num?)?.toInt() ?? (((song['duration'] as num?)?.toDouble() ?? 0) * 1000).round();
  if (ms <= 0) return '';
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _NoteSongPicker extends ConsumerStatefulWidget {
  const _NoteSongPicker();

  @override
  ConsumerState<_NoteSongPicker> createState() => _NoteSongPickerState();
}

class _NoteSongPickerState extends ConsumerState<_NoteSongPicker> {
  final _player = AudioPlayer();
  String query = '', tab = 'for_you';
  Map<String, dynamic>? current; // the song playing in the mini player
  bool playing = false;

  static const _tabs = [
    ('for_you', 'For you'),
    ('trending', 'Trending'),
    ('saved', 'Saved'),
    ('spotify', 'Spotify'),
    ('phone', 'Your music'),
  ];

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => playing = s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _key(Map s) => '${s['source']}:${s['ref'] ?? s['url'] ?? s['path']}';

  Future<void> _tap(Map<String, dynamic> song) async {
    HapticFeedback.selectionClick();
    if (current != null && _key(current!) == _key(song)) return _next();
    setState(() => current = song);
    final src = songSource(song);
    if (src == null) return;
    try {
      await _player.stop();
      await _player.play(src);
    } catch (_) {}
  }

  Future<void> _togglePlay() async {
    if (current == null) return;
    if (playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  /// On to "New song" with the current song.
  Future<void> _next() async {
    final song = current;
    if (song == null) return;
    await _player.pause();
    if (!mounted) return;
    final clip = await showSongTrimmer(context, song);
    if (clip != null && mounted) Navigator.pop(context, clip);
  }

  Future<void> _spotify() async {
    final song = await showSongPicker(context);
    if (song == null || !mounted) return;
    final url = '${song['url'] ?? ''}';
    if (song['source'] != 'spotify' || !url.startsWith('https://open.spotify.com/track/')) return;
    await _tap({
      'title': song['title'],
      'artist': song['artist'] ?? '',
      'url': url,
      if (song['image_url'] != null) 'image_url': song['image_url'],
      'ref': 'spotify:${song['id']}',
      if (song['explicit'] == true) 'explicit': true,
      if (song['duration_ms'] is num) 'duration_ms': song['duration_ms'],
      'source': 'spotify',
    });
  }

  Future<void> _phone() async {
    final song = await pickSongFile(context);
    if (song != null && mounted) await _tap(song);
  }

  Widget _row(Map<String, dynamic> song) {
    final saved = ref.watch(savedNoteSongsProvider);
    final isCurrent = current != null && _key(current!) == _key(song);
    final art = song['image_url'] as String?;
    final len = _length(song);
    return InkWell(
      onTap: () => _tap(song),
      child: Container(
        color: isCurrent ? const Color(0xFF2A2E37) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox.square(
              dimension: 54,
              child: art == null || art.isEmpty
                  ? const ColoredBox(color: PhlioColors.surfaceElevated, child: Icon(Icons.music_note_rounded))
                  : CachedNetworkImage(cacheManager: PhlioMediaCache.images, imageUrl: AppConfig.mediaUrl(art), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (isCurrent && playing) ...[
                  const Icon(Icons.graphic_eq_rounded, size: 18, color: Color(0xFF9EC5FF)),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text('${song['title']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? const Color(0xFF9EC5FF) : PhlioColors.textPrimary)),
                ),
                if (song['explicit'] == true) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(3)),
                    child: const Text('E', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text([song['artist'], if (len.isNotEmpty) len].where((x) => '$x'.isNotEmpty).join(' • '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 14)),
            ]),
          ),
          IconButton(
            tooltip: saved.containsKey(_key(song)) ? 'Remove from saved' : 'Save',
            icon: Icon(saved.containsKey(_key(song)) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 28),
            onPressed: () {
              final next = {...saved};
              next.containsKey(_key(song)) ? next.remove(_key(song)) : next[_key(song)] = song;
              ref.read(savedNoteSongsProvider.notifier).state = next;
            },
          ),
        ]),
      ),
    );
  }

  Widget _cta(IconData icon, Color color, String title, String sub, String button, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          CircleAvatar(radius: 30, backgroundColor: color.withValues(alpha: 0.18), child: Icon(icon, color: color, size: 30)),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: color), child: Text(button)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider('stream'));
    final all = [
      for (final item in (catalog.valueOrNull ?? const []).cast<Map>())
        if (streamCategory(item) == 'Music' && (item['media_url'] as String?)?.isNotEmpty == true) _fromCatalog(item),
    ];
    bool matches(Map s) => query.isEmpty || '${s['title']} ${s['artist']}'.toLowerCase().contains(query);
    List<Map<String, dynamic>> songs;
    switch (tab) {
      case 'trending':
        final raw = (catalog.valueOrNull ?? const []).cast<Map>().toList();
        num score(Map s) {
          final item = raw.firstWhere((r) => '${r['ref']}' == s['ref'], orElse: () => const {});
          return num.tryParse('${item['views'] ?? item['plays'] ?? item['likes'] ?? item['popularity'] ?? 0}') ?? 0;
        }

        songs = [...all]..sort((a, b) => score(b).compareTo(score(a)));
      case 'saved':
        songs = ref.watch(savedNoteSongsProvider).values.toList();
      default:
        songs = all;
    }
    songs = songs.where(matches).toList();

    Widget body;
    if (tab == 'spotify') {
      body = _cta(Icons.album_rounded, kSpotifyGreen, 'Spotify', 'Search Spotify and add a song. Friends play it in Spotify.',
          'Search Spotify', _spotify);
    } else if (tab == 'phone') {
      body = _cta(Icons.library_music_rounded, const Color(0xFF4CC9F0), 'Your music',
          'MP3, M4A, AAC, WAV, OGG, FLAC or OPUS from your phone (up to 15 MB).', 'Choose a song', _phone);
    } else if (catalog.isLoading && !catalog.hasValue) {
      body = const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    } else if (songs.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(40),
        child: Text(tab == 'saved' ? 'Tap the bookmark on a song to save it here.' : 'No songs found',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
      );
    } else {
      body = Column(children: [for (final s in songs) _row(s)]);
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: TextField(
            onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search_rounded, size: 26),
              filled: true,
              fillColor: const Color(0xFF2A2E37),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final (id, label) in _tabs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => tab = id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tab == id ? Colors.white : const Color(0xFF2A2E37),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: tab == id ? Colors.black : Colors.white)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: SingleChildScrollView(child: body)),
        if (current != null) _MiniPlayer(song: current!, playing: playing, onToggle: _togglePlay, onNext: _next),
      ]),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.song, required this.playing, required this.onToggle, required this.onNext});
  final Map<String, dynamic> song;
  final bool playing;
  final VoidCallback onToggle, onNext;

  @override
  Widget build(BuildContext context) {
    final art = song['image_url'] as String?;
    final spotify = song['source'] == 'spotify';
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF5C0B14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox.square(
              dimension: 46,
              child: art == null || art.isEmpty
                  ? const ColoredBox(color: Colors.black26, child: Icon(Icons.music_note_rounded))
                  : CachedNetworkImage(cacheManager: PhlioMediaCache.images, imageUrl: AppConfig.mediaUrl(art), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${song['title']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(spotify ? '${song['artist']} · plays in Spotify' : '${song['artist']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          if (!spotify)
            IconButton(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: onToggle,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34, color: Colors.white),
            ),
          const SizedBox(width: 4),
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onNext,
              child: const SizedBox(
                  width: 44, height: 44, child: Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 26)),
            ),
          ),
        ]),
      ),
    );
  }
}
