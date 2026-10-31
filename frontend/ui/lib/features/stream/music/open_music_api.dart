// Phlio Stream · Music — open music catalogue from Audius.
//
// Audius (audius.co) is a decentralised, open-source music platform with a
// free public REST API: trending charts, search, artists, playlists and
// full-length streams of tracks artists have made streamable. No API key is
// needed, but every call says which app it comes from (app_name=Phlio).
//
// Audius tracks behave like any other track in the player: they queue,
// shuffle, favourite, go into playlists, get Phlio Codes and lyrics (LRCLIB).
// Tracks you play or save are cached in the music store so playlists,
// favourites, history and the restored queue keep working offline-ish.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_library.dart' show formatDuration;
import 'music_models.dart';
import 'music_player.dart';
import 'music_ui.dart';
import 'now_playing.dart';

const _appName = 'Phlio';
const _hosts = ['https://api.audius.co/v1', 'https://discoveryprovider.audius.co/v1'];

/// Audius genres as the API spells them (shown as chips in Discover).
const audiusGenres = [
  'All', 'Electronic', 'Hip-Hop/Rap', 'Pop', 'Alternative', 'R&B/Soul', 'Lo-Fi', 'House', 'Ambient',
  'Rock', 'Dance & EDM', 'Jazz', 'Acoustic', 'Classical', 'World', 'Latin', 'Funk', 'Soundtrack',
];

/// An Audius user who uploads music, read straight from the API JSON.
class AudiusArtist {
  AudiusArtist(this.raw);
  final Map raw;
  /// Audius user id (short hash id).
  String get id => '${raw['id']}';
  /// Display name.
  String get name => '${raw['name'] ?? raw['handle'] ?? 'Artist'}';
  /// @handle on Audius.
  String get handle => '${raw['handle'] ?? ''}';
  /// Profile bio, or null when empty.
  String? get bio => (raw['bio'] as String?)?.trim().isEmpty == true ? null : raw['bio'] as String?;
  /// Location from the profile, or null when empty.
  String? get location => (raw['location'] as String?)?.trim().isEmpty == true ? null : raw['location'] as String?;
  /// Follower count.
  int get followers => (raw['follower_count'] as num?)?.toInt() ?? 0;
  /// How many people they follow.
  int get following => (raw['followee_count'] as num?)?.toInt() ?? 0;
  /// Number of tracks they've uploaded.
  int get tracks => (raw['track_count'] as num?)?.toInt() ?? 0;
  /// Whether Audius verified the account.
  bool get verified => raw['is_verified'] == true;
  /// Profile picture URL (480 px when available).
  String? get photo => _pic(raw['profile_picture']);
  /// Banner image URL (largest available).
  String? get cover => _pic(raw['cover_photo'], big: true);
  /// Website from the profile.
  String? get website => raw['website'] as String?;
}

/// An Audius playlist or album, read straight from the API JSON.
class AudiusPlaylist {
  AudiusPlaylist(this.raw);
  final Map raw;
  /// Audius playlist id.
  String get id => '${raw['id']}';
  /// Playlist title.
  String get name => '${raw['playlist_name'] ?? 'Playlist'}';
  /// Name of the person who made it.
  String get owner => '${(raw['user'] as Map?)?['name'] ?? ''}';
  /// Cover art URL.
  String? get art => _pic(raw['artwork']);
  /// Number of tracks.
  int get count => (raw['track_count'] as num?)?.toInt() ?? (raw['tracks'] as List?)?.length ?? 0;
}

String? _pic(Object? sizes, {bool big = false}) {
  if (sizes is! Map) return null;
  for (final k in big ? const ['2000x', '640x', '1000x1000', '480x480'] : const ['480x480', '1000x1000', '150x150', '640x']) {
    final v = sizes[k];
    if (v is String && v.startsWith('http')) return v;
  }
  return null;
}

/// Thin client with host fallback.
class AudiusApi {
  AudiusApi() : _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15)));
  final Dio _dio;
  String? _host;

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final params = {...?query, 'app_name': _appName};
    Object? last;
    for (final host in [if (_host != null) _host!, ..._hosts.where((h) => h != _host)]) {
      try {
        final res = await _dio.get(host + path, queryParameters: params);
        _host = host;
        final body = res.data;
        return body is Map ? body['data'] : body;
      } catch (e) {
        last = e;
      }
    }
    throw last ?? StateError('Audius unavailable');
  }

  /// Full-length stream URL for a track (redirects to an Audius content node).
  String streamUrl(String trackId) => '${_host ?? _hosts.first}/tracks/$trackId/stream?app_name=$_appName';

  /// Maps an Audius track JSON object to a [Track] (`aud_<id>`, source `audius`).
  Track toTrack(Map j) {
    final user = (j['user'] as Map?) ?? const {};
    final id = '${j['id']}';
    final released = DateTime.tryParse('${j['release_date'] ?? ''}');
    return Track(
      id: 'aud_$id',
      ref: id,
      title: '${j['title'] ?? 'Untitled'}',
      artist: '${user['name'] ?? user['handle'] ?? 'Audius artist'}',
      album: '${user['name'] ?? 'Audius'} · Audius',
      genre: '${(j['genre'] as String?)?.isNotEmpty == true ? j['genre'] : 'Music'}',
      year: released?.year,
      durationMs: ((j['duration'] as num?)?.toInt() ?? 0) * 1000,
      uri: streamUrl(id),
      artUrl: _pic(j['artwork']),
      source: 'audius',
      folder: 'Audius',
      artistId: '${user['id'] ?? ''}',
      plays: (j['play_count'] as num?)?.toInt(),
      addedAt: released,
    );
  }

  List<Track> _tracks(dynamic data) => [
        for (final j in (data as List? ?? const []))
          if (j is Map && j['is_streamable'] != false && j['is_delete'] != true) toTrack(j)
      ];

  Future<List<Track>> trending({String genre = 'All', String time = 'week', bool underground = false}) async => _tracks(await _get(
      underground ? '/tracks/trending/underground' : '/tracks/trending',
      {'time': time, if (genre != 'All') 'genre': genre, 'limit': 50}));

  Future<List<Track>> searchTracks(String q) async => _tracks(await _get('/tracks/search', {'query': q, 'limit': 30}));

  Future<List<AudiusArtist>> searchArtists(String q) async =>
      [for (final u in (await _get('/users/search', {'query': q, 'limit': 10}) as List? ?? const [])) AudiusArtist(u as Map)];

  /// One track by id, or null.
  Future<Track?> track(String id) async {
    final d = await _get('/tracks/$id');
    return d is Map ? toTrack(d) : null;
  }

  /// An artist's profile.
  Future<AudiusArtist> artist(String id) async => AudiusArtist(await _get('/users/$id') as Map);

  Future<List<Track>> artistTracks(String id) async => _tracks(await _get('/users/$id/tracks', {'sort': 'plays', 'limit': 50}));

  Future<List<AudiusArtist>> relatedArtists(String id) async =>
      [for (final u in (await _get('/users/$id/related', {'limit': 10}) as List? ?? const [])) AudiusArtist(u as Map)];

  Future<List<AudiusPlaylist>> trendingPlaylists() async =>
      [for (final p in (await _get('/playlists/trending', {'time': 'week', 'limit': 20}) as List? ?? const [])) AudiusPlaylist(p as Map)];

  Future<List<Track>> playlistTracks(String id) async => _tracks(await _get('/playlists/$id/tracks'));
}

/// The shared Audius client.
final audiusProvider = Provider<AudiusApi>((ref) => AudiusApi());

/// Chart key used by For you: all genres, this week, not underground.
const forYouChart = ('All', 'week', false);

/// Audius trending tracks for a `(genre, time, underground)` chart key.
/// Kept alive once loaded so switching tabs doesn't refetch.
final audiusTrendingProvider = FutureProvider.autoDispose.family<List<Track>, (String, String, bool)>((ref, k) {
  ref.keepAlive();
  return ref.read(audiusProvider).trending(genre: k.$1, time: k.$2, underground: k.$3);
});

/// This week's trending Audius playlists (kept once loaded).
final audiusPlaylistsProvider = FutureProvider.autoDispose<List<AudiusPlaylist>>((ref) {
  ref.keepAlive();
  return ref.read(audiusProvider).trendingPlaylists();
});

/// Audius search for a query: matching tracks and artists.
final audiusSearchProvider = FutureProvider.autoDispose.family<(List<Track>, List<AudiusArtist>), String>((ref, q) async {
  final api = ref.read(audiusProvider);
  final r = await Future.wait([api.searchTracks(q), api.searchArtists(q)]);
  return (r[0] as List<Track>, r[1] as List<AudiusArtist>);
});

/// An artist page's data: profile, popular tracks and related artists.
final audiusArtistProvider = FutureProvider.autoDispose
    .family<(AudiusArtist, List<Track>, List<AudiusArtist>), String>((ref, id) async {
  final api = ref.read(audiusProvider);
  final r = await Future.wait([
    api.artist(id),
    api.artistTracks(id),
    api.relatedArtists(id).catchError((_) => <AudiusArtist>[]),
  ]);
  return (r[0] as AudiusArtist, r[1] as List<Track>, r[2] as List<AudiusArtist>);
});

/// 1234 → 1.2K, 2500000 → 2.5M.
String compactCount(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M'
    : n >= 1000
        ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K'
        : '$n';

// -- Discover tab ------------------------------------------------------------------------------

/// The Audius feed on Explore: genre chips, time range and underground
/// filters, trending playlists and the trending chart.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});
  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

/// Holds the chosen genre, time range and underground filter.
class _DiscoverTabState extends ConsumerState<DiscoverTab> with AutomaticKeepAliveClientMixin {
  String genre = 'All';
  String time = 'week';
  bool underground = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pal = RetroPaletteScope.of(context);
    final key = (genre, time, underground);
    final trending = ref.watch(audiusTrendingProvider(key));
    final playlists = ref.watch(audiusPlaylistsProvider);
    final player = ref.read(musicPlayerProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(audiusTrendingProvider(key));
        ref.invalidate(audiusPlaylistsProvider);
        await ref.read(audiusTrendingProvider(key).future).catchError((_) => <Track>[]);
      },
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            itemCount: audiusGenres.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(audiusGenres[i]),
              selected: genre == audiusGenres[i],
              onSelected: (_) => setState(() => genre = audiusGenres[i]),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (t, label) in const [('week', 'This week'), ('month', 'This month'), ('allTime', 'All time')])
              FilterChip(
                label: Text(label),
                selected: time == t,
                onSelected: (_) => setState(() => time = t),
                visualDensity: VisualDensity.compact,
              ),
            FilterChip(
              avatar: const Icon(Icons.diamond_outlined, size: 16),
              label: const Text('Underground'),
              selected: underground,
              onSelected: (v) => setState(() => underground = v),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
        if (!underground && genre == 'All')
          playlists.maybeWhen(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionLabel('Trending playlists'),
                    SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => _PlaylistCard(list[i]),
                      ),
                    ),
                  ]),
            orElse: () => const SizedBox.shrink(),
          ),
        SectionLabel(
          underground ? 'Underground trending' : genre == 'All' ? 'Trending on Audius' : 'Trending · $genre',
          action: 'Play all',
          onAction: () {
            final list = trending.valueOrNull ?? const <Track>[];
            if (list.isNotEmpty) player.playTracks(list);
          },
        ),
        ...trending.when<List<Widget>>(
          loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (_, __) => [
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(children: [
                Icon(Icons.cloud_off_rounded, color: pal.muted, size: 40),
                const SizedBox(height: 10),
                Text('Could not reach Audius. Check your connection.', textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
                TextButton(onPressed: () => ref.invalidate(audiusTrendingProvider(key)), child: const Text('Retry')),
              ]),
            ),
          ],
          data: (list) => [
            for (final (i, t) in list.indexed)
              SongTile(
                track: t,
                index: i + 1,
                onTap: () {
                  player.playTracks(list, start: i);
                },
              ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(child: Text('Nothing trending here yet.', style: TextStyle(color: pal.muted))),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Text('Music from Audius, the open-source music platform. Streams go straight to the artists\' Audius pages.',
              style: TextStyle(color: pal.muted, fontSize: 11.5)),
        ),
      ]),
    );
  }
}

/// Cover + name card for a trending playlist; opens [AudiusPlaylistScreen].
class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard(this.p);
  final AudiusPlaylist p;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = RetroPaletteScope.of(context);
    final cover = Track(id: 'audpl_${p.id}', title: p.name, artist: p.owner, album: p.name, uri: '', artUrl: p.art, source: 'audius');
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AudiusPlaylistScreen(playlist: p))),
      child: SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Artwork(track: cover, size: 140, radius: 16, label: p.name),
          const SizedBox(height: 6),
          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w800)),
          Text(p.owner, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Tracks of one Audius playlist.
final _audiusPlaylistTracksProvider =
    FutureProvider.autoDispose.family<List<Track>, String>((ref, id) => ref.read(audiusProvider).playlistTracks(id));

/// An Audius playlist: play, shuffle, or save it as a Phlio playlist.
class AudiusPlaylistScreen extends ConsumerWidget {
  const AudiusPlaylistScreen({required this.playlist, super.key});
  final AudiusPlaylist playlist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    final tracks = ref.watch(_audiusPlaylistTracksProvider(playlist.id));
    final player = ref.read(musicPlayerProvider);
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(backgroundColor: pal.bg, foregroundColor: pal.text, title: Text(playlist.name)),
          body: tracks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(_audiusPlaylistTracksProvider(playlist.id)), child: const Text('Could not load. Retry')),
            ),
            data: (list) => ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(children: [
                  FilledButton.icon(
                    onPressed: list.isEmpty ? null : () => player.playTracks(list),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: list.isEmpty ? null : () => player.playTracks(list, shuffled: true),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Shuffle'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Save as a Phlio playlist',
                    onPressed: list.isEmpty
                        ? null
                        : () {
                            final store = ref.read(musicStoreProvider);
                            for (final t in list) {
                              store.rememberRemote(t);
                            }
                            store.createPlaylist(playlist.name, [for (final t in list) t.id]);
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Saved to your playlists')));
                          },
                    icon: Icon(Icons.library_add_rounded, color: pal.text),
                  ),
                ]),
              ),
              for (final (i, t) in list.indexed) SongTile(track: t, onTap: () => player.playTracks(list, start: i)),
            ]),
          ),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }
}

// -- artist info -------------------------------------------------------------------------------

/// Opens the artist page for an Audius user id.
Future<void> openAudiusArtist(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AudiusArtistScreen(artistId: id)));

/// Artist page: banner, photo, bio, followers, location, popular tracks
/// (with play counts) and "Fans also like".
class AudiusArtistScreen extends ConsumerWidget {
  const AudiusArtistScreen({required this.artistId, super.key});
  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    final data = ref.watch(audiusArtistProvider(artistId));
    final player = ref.read(musicPlayerProvider);
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          body: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Scaffold(
              backgroundColor: pal.bg,
              appBar: AppBar(backgroundColor: pal.bg, foregroundColor: pal.text),
              body: Center(
                child: TextButton(onPressed: () => ref.invalidate(audiusArtistProvider(artistId)), child: const Text('Could not load. Retry')),
              ),
            ),
            data: (d) {
              final (a, tracks, related) = d;
              final photo = Track(id: 'audu_${a.id}', title: a.name, artist: a.name, album: a.name, uri: '', artUrl: a.photo, source: 'audius');
              return CustomScrollView(slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 280,
                  backgroundColor: pal.bg,
                  foregroundColor: pal.text,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(fit: StackFit.expand, children: [
                      if (a.cover != null)
                        Artwork(track: photo.copyWith(artUrl: a.cover), radius: 0)
                      else
                        RetroGlow(colors: ArtColors.phlio, energy: .4, light: !pal.dark),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black26, pal.bg.withValues(alpha: .2), pal.bg],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 14,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          ClipOval(child: Artwork(track: photo, size: 96, radius: 0, label: a.name)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(
                                  child: Text(a.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: pal.text, fontSize: 24, fontWeight: FontWeight.w900)),
                                ),
                                if (a.verified) ...[const SizedBox(width: 6), Icon(Icons.verified_rounded, color: pal.accent, size: 20)],
                              ]),
                              Text('@${a.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted)),
                            ]),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                    child: Wrap(spacing: 18, runSpacing: 6, children: [
                      for (final (n, label) in [(a.followers, 'followers'), (a.following, 'following'), (a.tracks, 'tracks')])
                        Text.rich(TextSpan(children: [
                          TextSpan(text: compactCount(n), style: TextStyle(color: pal.text, fontWeight: FontWeight.w900)),
                          TextSpan(text: ' $label', style: TextStyle(color: pal.muted)),
                        ])),
                      if (a.location != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.place_outlined, size: 16, color: pal.muted),
                          Text(a.location!, style: TextStyle(color: pal.muted)),
                        ]),
                    ]),
                  ),
                ),
                if (a.bio != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: Text(a.bio!, style: TextStyle(color: pal.text.withValues(alpha: .85), height: 1.4)),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Row(children: [
                      FilledButton.icon(
                        onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks, shuffled: true),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                      ),
                    ]),
                  ),
                ),
                const SliverToBoxAdapter(child: SectionLabel('Popular')),
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (_, i) => SongTile(
                    track: tracks[i],
                    index: i + 1,
                    trailing: Text(
                      tracks[i].plays == null ? formatDuration(tracks[i].duration) : '${compactCount(tracks[i].plays!)} plays',
                      style: TextStyle(color: pal.muted, fontSize: 12),
                    ),
                    onTap: () => player.playTracks(tracks, start: i),
                  ),
                ),
                if (related.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionLabel('Fans also like')),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 132,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: related.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => ArtistBubble(artist: related[i]),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ]);
            },
          ),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }
}

/// Round artist photo with name; opens the artist page.
class ArtistBubble extends StatelessWidget {
  const ArtistBubble({required this.artist, super.key});
  final AudiusArtist artist;
  @override
  Widget build(BuildContext context) {
    final pal = RetroPaletteScope.of(context);
    final photo = Track(id: 'audu_${artist.id}', title: artist.name, artist: artist.name, album: artist.name, uri: '', artUrl: artist.photo, source: 'audius');
    return GestureDetector(
      onTap: () => openAudiusArtist(context, artist.id),
      child: SizedBox(
        width: 86,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipOval(child: Artwork(track: photo, size: 86, radius: 0, label: artist.name)),
          const SizedBox(height: 6),
          Text(artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      ),
    );
  }
}
