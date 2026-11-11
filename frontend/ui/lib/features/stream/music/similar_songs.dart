// Phlio Stream · Music — "Similar songs" and "Search by lyrics".
//
// Backed by `/api/v1/stream/similar/songs*` (backend/app/api/v1/similar.py),
// a Searchly-style similarity search: songs are compared by their lyrics
// (from LRCLIB, when published) and their style (genre, mood, tags). Every
// similar song is a playable Audius track; lyric-search results that aren't
// on Audius are listed but can't be played.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import 'music_models.dart';
import 'music_player.dart';
import 'music_ui.dart';
import 'now_playing.dart' show MiniPlayer;
import 'open_music_api.dart';

/// One similar-song result: a playable track and why it matched.
class SimilarSong {
  SimilarSong({required this.track, required this.because, required this.byLyrics, this.snippet});

  /// The playable track.
  final Track track;

  /// Shared words or tags that explain the match.
  final List<String> because;

  /// True when matched on lyrics, false when on style only.
  final bool byLyrics;

  /// One lyric line from the matched song, when matched on lyrics.
  final String? snippet;
}

/// Similar songs for a seed track: `(audiusId, title, artist)`.
final similarSongsProvider =
    FutureProvider.autoDispose.family<(bool, List<SimilarSong>), (String?, String, String)>((ref, seed) async {
  ref.keepAlive();
  final (audiusId, title, artist) = seed;
  final res = await getIt<ApiClient>().dio.get<dynamic>('/stream/similar/songs', queryParameters: {
    if (audiusId != null) 'audius_id': audiusId else ...{'title': title, 'artist': artist},
    'limit': 30,
  });
  final body = res.data as Map;
  final audius = ref.read(audiusProvider);
  return (
    (body['seed'] as Map?)?['has_lyrics'] == true,
    [
      for (final item in (body['items'] as List? ?? const []))
        SimilarSong(
          track: audius.toTrack(item['track'] as Map),
          because: [for (final w in (item['because'] as List? ?? const [])) '$w'],
          byLyrics: item['match'] == 'lyrics',
          snippet: item['snippet'] as String?,
        ),
    ],
  );
});

/// Songs whose lyrics match a phrase: `(title, artist, snippet, playable track or null)`.
final lyricsSearchProvider =
    FutureProvider.autoDispose.family<List<(String, String, String?, Track?)>, String>((ref, q) async {
  final res = await getIt<ApiClient>().dio.get<dynamic>('/stream/similar/songs/by-lyrics', queryParameters: {'q': q});
  final audius = ref.read(audiusProvider);
  return [
    for (final item in ((res.data as Map)['items'] as List? ?? const []))
      (
        '${item['title'] ?? ''}',
        '${item['artist'] ?? ''}',
        item['snippet'] as String?,
        item['audius'] is Map ? audius.toTrack(item['audius'] as Map) : null,
      ),
  ];
});

/// Opens "Songs like [t]".
Future<void> openSimilarSongs(BuildContext context, Track t) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SimilarSongsScreen(seed: t)));

/// Opens the lyrics search page.
Future<void> openLyricsSearch(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LyricsSearchScreen()));

class _MusicPage extends ConsumerWidget {
  const _MusicPage({required this.title, required this.body, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(
            backgroundColor: pal.bg,
            foregroundColor: pal.text,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: pal.muted)),
            ]),
          ),
          body: body,
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }
}

/// "Songs like X": playable similar songs, lyric matches first.
class SimilarSongsScreen extends ConsumerWidget {
  const SimilarSongsScreen({required this.seed, super.key});

  /// The song to find neighbours for.
  final Track seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    final key = (seed.isAudius ? seed.ref : null, seed.title, seed.artist);
    final data = ref.watch(similarSongsProvider(key));
    return _MusicPage(
      title: 'Songs like ${seed.title}',
      subtitle: data.valueOrNull == null
          ? null
          : data.value!.$1
              ? 'Matched on lyrics and style'
              : 'No published lyrics · matched on style',
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(onPressed: () => ref.invalidate(similarSongsProvider(key)), child: const Text('Could not load. Retry')),
        ),
        data: (d) {
          final items = d.$2;
          if (items.isEmpty) {
            return Center(child: Text('No similar songs found yet.', style: TextStyle(color: pal.muted)));
          }
          final tracks = [for (final s in items) s.track];
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final s = items[i];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SongTile(
                  track: s.track,
                  onTap: () => ref.read(musicPlayerProvider).playTracks(tracks, start: i),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: s.byLyrics ? 'Lyrics · ' : 'Style · ',
                        style: TextStyle(color: pal.accent, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: s.because.join(', ')),
                      if (s.snippet != null) TextSpan(text: '\n“${s.snippet}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                    ]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.muted, fontSize: 12),
                  ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }
}

/// Search songs by what their lyrics are about (Searchly's "search by content").
class LyricsSearchScreen extends ConsumerStatefulWidget {
  const LyricsSearchScreen({super.key});

  @override
  ConsumerState<LyricsSearchScreen> createState() => _LyricsSearchScreenState();
}

class _LyricsSearchScreenState extends ConsumerState<LyricsSearchScreen> {
  final _text = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(retroPaletteProvider);
    return _MusicPage(
      title: 'Search by lyrics',
      subtitle: 'A line you remember, or what the song is about',
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _text,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'e.g. dancing alone in the rain at midnight',
              prefixIcon: const Icon(Icons.lyrics_outlined),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _query = _text.text.trim()),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
        Expanded(
          child: _query.length < 3
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Type a few words from the lyrics and press search.',
                        textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
                  ),
                )
              : ref.watch(lyricsSearchProvider(_query)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => Center(
                      child: TextButton(
                          onPressed: () => ref.invalidate(lyricsSearchProvider(_query)), child: const Text('Could not search. Retry')),
                    ),
                    data: (rows) {
                      if (rows.isEmpty) {
                        return Center(child: Text('No songs found with those lyrics.', style: TextStyle(color: pal.muted)));
                      }
                      final playable = [for (final r in rows) if (r.$4 != null) r.$4!];
                      return ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final (title, artist, snippet, track) = rows[i];
                          final line = snippet == null ? null : Text('“$snippet”',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: pal.muted, fontSize: 12, fontStyle: FontStyle.italic));
                          if (track != null) {
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SongTile(
                                track: track,
                                onTap: () => ref.read(musicPlayerProvider).playTracks(playable, start: playable.indexOf(track)),
                              ),
                              if (line != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: line),
                            ]);
                          }
                          return ListTile(
                            leading: Icon(Icons.music_off_outlined, color: pal.muted),
                            title: Text(title, style: TextStyle(color: pal.text)),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('$artist · not on Audius', style: TextStyle(color: pal.muted)),
                              if (line != null) line,
                            ]),
                          );
                        },
                      );
                    },
                  ),
        ),
      ]),
    );
  }
}
