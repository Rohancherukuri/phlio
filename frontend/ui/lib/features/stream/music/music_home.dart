// Phlio Stream · Music — the Retro-style library home: your profile banner,
// For you (smart auto playlists), Songs, Albums, Artists, Playlists, Genres
// and Folders, search, album / artist / genre / folder pages, playlists
// (create, rename, drag to sort, import / export M3U) and settings, with the
// mini player docked at the bottom.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../authentication/presentation/controllers/auth_controller.dart';
import '../../profile/presentation/controllers/avatar_controller.dart' show MeAvatar;
import 'music_library.dart';
import 'music_models.dart';
import 'music_player.dart';
import 'music_ui.dart';
import 'now_playing.dart';
import 'open_music_api.dart';
import 'phlio_code_sheet.dart';

/// Music Home (Stream → headphones): profile line, search bar with the code
/// scanner, and the library tabs. The mini player is docked at the bottom.
class RetroMusicHome extends ConsumerStatefulWidget {
  const RetroMusicHome({this.onSwitchToVideo, super.key});
  final VoidCallback? onSwitchToVideo;
  @override
  ConsumerState<RetroMusicHome> createState() => _RetroMusicHomeState();
}

/// Owns the tab controller and Songs sort; scans phone music on first open
/// and restores the last queue once the library has loaded.
class _RetroMusicHomeState extends ConsumerState<RetroMusicHome> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this);

  /// Library tabs. Audius charts live on the Explore page ([MusicExploreScreen]).
  static const _tabNames = ['For you', 'Songs', 'Albums', 'Artists', 'Playlists', 'Genres', 'Folders'];

  /// Sort order of the Songs tab: title, artist, album, duration, added or plays.
  String _sort = 'title';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(musicStoreProvider);
      final device = ref.read(deviceMusicProvider.notifier);
      if (store.settings.includeDevice && (ref.read(deviceMusicProvider).valueOrNull?.isEmpty ?? true)) {
        device.scan();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _play(List<Track> list, {int start = 0, bool shuffle = false}) async {
    HapticFeedback.selectionClick();
    await ref.read(musicPlayerProvider).playTracks(list, start: start, shuffled: shuffle);
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(retroPaletteProvider);
    final library = ref.watch(musicLibraryProvider);
    // Restore last session's queue once everything is loaded.
    final byId = ref.watch(trackByIdProvider);
    if (byId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(musicPlayerProvider).restore(byId);
      });
    }
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          body: SafeArea(
            bottom: false,
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [
                SliverToBoxAdapter(child: _header(pal)),
                SliverToBoxAdapter(child: _searchBar(pal)),
                SliverPersistentHeader(pinned: true, delegate: _TabsHeader(_tabs, _tabNames, pal)),
              ],
              body: library.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(musicLibraryProvider),
                    child: const Text('Could not load music. Retry'),
                  ),
                ),
                data: (all) => TabBarView(controller: _tabs, children: [
                  _forYou(all, pal),
                  _songs(all, pal),
                  _albums(pal),
                  _artists(pal),
                  _playlists(pal),
                  _genres(pal),
                  _folders(pal),
                ]),
              ),
            ),
          ),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }

  // -- header with the user's profile ---------------------------------------------------

  Widget _header(RetroPalette pal) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final hour = DateTime.now().hour;
    final greet = hour < 5 ? 'Late night vibes' : hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [pal.accent, pal.accent2])),
          child: MeAvatar(name: me?.fullName ?? 'You', size: 46),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greet, style: TextStyle(color: pal.muted, fontSize: 13)),
            Text(me?.fullName ?? 'Phlio Stream',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: pal.text, fontSize: 20, fontWeight: FontWeight.w900)),
          ]),
        ),
        if (widget.onSwitchToVideo != null)
          IconButton(
            tooltip: 'Switch to movies and shows',
            icon: Icon(Icons.movie_outlined, color: pal.text),
            onPressed: widget.onSwitchToVideo,
          ),
        IconButton(
          tooltip: 'Music settings',
          icon: Icon(Icons.tune_rounded, color: pal.text),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MusicSettingsScreen())),
        ),
      ]),
    );
  }

  /// Search bar under the profile line, with the Phlio Code scanner.
  Widget _searchBar(RetroPalette pal) => const MusicSearchBar();

  // -- For you -----------------------------------------------------------------------------

  Widget _forYou(List<Track> all, RetroPalette pal) {
    final smart = ref.watch(smartListsProvider);
    final artists = ref.watch(artistsProvider);
    final albums = ref.watch(albumsProvider);
    final cards = <(String, IconData, List<Track>, Color)>[
      ('Shuffle all', Icons.shuffle_rounded, all, pal.accent),
      ('Recently added', Icons.new_releases_outlined, smart.recentlyAdded, const Color(0xFF68D7CD)),
      ('Recently played', Icons.history_rounded, smart.recentlyPlayed, pal.accent2),
      ('Most played', Icons.trending_up_rounded, smart.mostPlayed, const Color(0xFFE795D7)),
      ('Favourites', Icons.favorite_rounded, smart.favorites, const Color(0xFFF5636B)),
      ('History', Icons.timelapse_rounded, smart.history, const Color(0xFF72A7FF)),
    ];
    // Today's local picks (stable for the day) mixed with this week's
    // Audius chart, so For you always has something new even in a small
    // library, and something familiar even when you're offline.
    final suggestions = [...all]..shuffle(math.Random(DateTime.now().day));
    final online = ref.watch(audiusTrendingProvider(forYouChart)).valueOrNull ?? const <Track>[];
    final fresh = [...online]..shuffle(math.Random(DateTime.now().day + 7));
    final mix = mixTracks(suggestions.take(12).toList(), fresh.take(12).toList());
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: _smartAspect(context),
        children: [
          for (final (name, icon, list, color) in cards)
            _SmartCard(
              name: name,
              icon: icon,
              color: color,
              count: list.length,
              onTap: () {
                if (name == 'Shuffle all') {
                  _play(all, start: all.isEmpty ? 0 : math.Random().nextInt(all.length), shuffle: true);
                } else {
                  _openList(name, list, smartName: name);
                }
              },
            ),
        ],
      ),
      if (smart.recentlyPlayed.isNotEmpty) ...[
        const SectionLabel('Jump back in'),
        _coverShelf(smart.recentlyPlayed.take(12).toList(), (i) => _play(smart.recentlyPlayed, start: i)),
      ],
      if (artists.isNotEmpty) ...[
        SectionLabel('Top artists', action: 'See all', onAction: () => _tabs.animateTo(3)),
        SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: math.min(12, artists.length),
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final a = ([...artists]..sort((x, y) => y.tracks.length.compareTo(x.tracks.length)))[i];
              return GestureDetector(
                onTap: () => _openGroup(a, 'Artist'),
                child: SizedBox(
                  width: 86,
                  child: Column(children: [
                    ClipOval(child: Artwork(track: a.cover, size: 86, radius: 0, label: a.name)),
                    const SizedBox(height: 6),
                    Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
      if (albums.isNotEmpty) ...[
        SectionLabel('Albums', action: 'See all', onAction: () => _tabs.animateTo(2)),
        SizedBox(
          height: 204,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: math.min(12, albums.length),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _AlbumCard(group: albums[i], onTap: () => _openGroup(albums[i], 'Album'), width: 140),
          ),
        ),
      ],
      if (online.isNotEmpty) ...[
        SectionLabel('Fresh on Audius', action: 'Play', onAction: () => _play(online)),
        _coverShelf(online.take(12).toList(), (i) => _play(online, start: i)),
      ],
      if (mix.isNotEmpty) ...[
        SectionLabel('Your mix', action: 'Play', onAction: () => _play(mix)),
        for (final (i, t) in mix.take(10).indexed)
          SongTile(
            track: t,
            // Where the song comes from: the open web (Audius) or your library.
            trailing: Icon(t.isAudius ? Icons.public_rounded : Icons.library_music_outlined, size: 18, color: pal.muted),
            onTap: () => _play(mix, start: i),
          ),
      ],
      if (all.isEmpty && online.isEmpty)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Text('No music yet. Phlio Stream tracks and your phone\'s music will show up here.',
              textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
        ),
    ]);
  }

  /// Smart cards are 64 px tall at any screen width (aspect ratios
  /// overflowed on narrow phones).
  double _smartAspect(BuildContext context) {
    final w = (MediaQuery.sizeOf(context).width - 28 - 10) / 2;
    return w / (64 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3));
  }

  Widget _coverShelf(List<Track> list, void Function(int) onTap) => SizedBox(
        height: 186,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final pal = RetroPaletteScope.of(context);
            return GestureDetector(
              onTap: () => onTap(i),
              onLongPress: () => showSongMenu(context, ref, list[i]),
              child: SizedBox(
                width: 130,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Artwork(track: list[i], size: 130, radius: 16),
                  const SizedBox(height: 6),
                  Text(list[i].title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
                  Text(list[i].artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12)),
                ]),
              ),
            );
          },
        ),
      );

  // -- Songs ---------------------------------------------------------------------------------

  Widget _songs(List<Track> all, RetroPalette pal) {
    final store = ref.read(musicStoreProvider);
    final list = [...all];
    switch (_sort) {
      case 'artist':
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case 'album':
        list.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase()));
      case 'duration':
        list.sort((a, b) => b.durationMs.compareTo(a.durationMs));
      case 'added':
        list.sort((a, b) => (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
      case 'plays':
        list.sort((a, b) => (store.playCounts[b.id] ?? 0).compareTo(store.playCounts[a.id] ?? 0));
      default:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: list.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _PlayBar(
            count: list.length,
            onPlay: () => _play(list),
            onShuffle: () => _play(list, start: list.isEmpty ? 0 : math.Random().nextInt(list.length), shuffle: true),
            trailing: PopupMenuButton<String>(
              tooltip: 'Sort',
              icon: Icon(Icons.sort_rounded, color: pal.text),
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'title', child: Text('Title')),
                PopupMenuItem(value: 'artist', child: Text('Artist')),
                PopupMenuItem(value: 'album', child: Text('Album')),
                PopupMenuItem(value: 'duration', child: Text('Duration')),
                PopupMenuItem(value: 'added', child: Text('Recently added')),
                PopupMenuItem(value: 'plays', child: Text('Most played')),
              ],
            ),
          );
        }
        return SongTile(track: list[i - 1], onTap: () => _play(list, start: i - 1));
      },
    );
  }

  // -- Albums / Artists / Genres / Folders --------------------------------------------------------

  Widget _albums(RetroPalette pal) {
    final albums = ref.watch(albumsProvider);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .74),
      itemCount: albums.length,
      itemBuilder: (_, i) => _AlbumCard(group: albums[i], onTap: () => _openGroup(albums[i], 'Album')),
    );
  }

  Widget _artists(RetroPalette pal) {
    final artists = ref.watch(artistsProvider);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .72),
      itemCount: artists.length,
      itemBuilder: (_, i) {
        final a = artists[i];
        return GestureDetector(
          onTap: () => _openGroup(a, 'Artist'),
          child: Column(children: [
            Expanded(
              child: Center(
                child: AspectRatio(aspectRatio: 1, child: ClipOval(child: Artwork(track: a.cover, radius: 0, label: a.name))),
              ),
            ),
            const SizedBox(height: 6),
            Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: pal.text, fontWeight: FontWeight.w800, fontSize: 13)),
            Text('${a.tracks.length} songs', maxLines: 1, style: TextStyle(color: pal.muted, fontSize: 11.5)),
          ]),
        );
      },
    );
  }

  Widget _genres(RetroPalette pal) {
    final genres = ref.watch(genresProvider);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      gridDelegate:
          const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2),
      itemCount: genres.length,
      itemBuilder: (_, i) {
        final g = genres[i];
        final hue = (g.name.hashCode % 360).abs().toDouble();
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openGroup(g, 'Genre'),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [
                HSLColor.fromAHSL(1, hue, .55, .5).toColor(),
                HSLColor.fromAHSL(1, (hue + 40) % 360, .6, .38).toColor(),
              ]),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
              const Spacer(),
              Text(g.subtitle, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }

  Widget _folders(RetroPalette pal) {
    final folders = ref.watch(foldersProvider);
    final store = ref.read(musicStoreProvider);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      for (final f in folders)
        ListTile(
          leading: Icon(Icons.folder_rounded, color: pal.accent),
          title: Text(f.name.split('/').last.isEmpty ? f.name : f.name.split('/').last,
              style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
          subtitle: Text('${f.name} · ${f.subtitle}', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _openGroup(f, 'Folder'),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'hide') {
                store.settings.blacklist = [...store.settings.blacklist, f.name];
                store.save();
              } else if (v == 'play') {
                _play(f.tracks);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'play', child: Text('Play folder')),
              PopupMenuItem(value: 'hide', child: Text('Hide folder (blacklist)')),
            ],
          ),
        ),
      if (ref.read(deviceMusicProvider.notifier).permissionDenied)
        ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: const Text('Allow access to music on this phone'),
          onTap: () => ref.read(deviceMusicProvider.notifier).scan(),
        ),
    ]);
  }

  // -- Playlists ---------------------------------------------------------------------------------

  Widget _playlists(RetroPalette pal) {
    final store = ref.watch(musicStoreProvider);
    final smart = ref.watch(smartListsProvider);
    final byId = ref.watch(trackByIdProvider);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                final name = await askText(context, 'New playlist', 'Name');
                if (name != null && name.trim().isNotEmpty) store.createPlaylist(name);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('New playlist'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _importM3u(context),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import'),
            ),
          ),
        ]),
      ),
      const SectionLabel('Smart playlists'),
      for (final (name, icon, list) in [
        ('Favourites', Icons.favorite_rounded, smart.favorites),
        ('Recently played', Icons.history_rounded, smart.recentlyPlayed),
        ('Most played', Icons.trending_up_rounded, smart.mostPlayed),
        ('Recently added', Icons.new_releases_outlined, smart.recentlyAdded),
        ('History', Icons.timelapse_rounded, smart.history),
      ])
        ListTile(
          leading: CircleAvatar(backgroundColor: pal.card, child: Icon(icon, color: pal.accent)),
          title: Text(name, style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
          subtitle: Text('${list.length} songs'),
          onTap: () => _openList(name, list, smartName: name),
        ),
      const SectionLabel('Your playlists'),
      if (store.playlists.isEmpty)
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text('Create a playlist, or long-press any song → Add to playlist.', style: TextStyle(color: pal.muted)),
        ),
      for (final p in store.playlists)
        ListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: p.trackIds.isEmpty || byId[p.trackIds.first] == null
                ? CircleAvatar(backgroundColor: pal.card, child: Icon(Icons.queue_music_rounded, color: pal.accent))
                : Artwork(track: byId[p.trackIds.first]!, radius: 10),
          ),
          title: Text(p.name, style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
          subtitle: Text('${p.trackIds.length} songs'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: p.id))),
        ),
    ]);
  }

  Future<void> _importM3u(BuildContext context) async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['m3u', 'm3u8']);
    final path = result?.files.single.path;
    if (path == null) return;
    final lines = await File(path).readAsLines();
    final all = ref.read(musicLibraryProvider).valueOrNull ?? const <Track>[];
    final ids = <String>[];
    String? title;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        title = line.contains(',') ? line.substring(line.indexOf(',') + 1).trim() : null;
        continue;
      }
      if (line.startsWith('#')) continue;
      final base = line.replaceAll('\\', '/').split('/').last.toLowerCase();
      final match = all.where((t) =>
          (t.isDevice && t.uri.replaceAll('\\', '/').toLowerCase().endsWith(base)) ||
          (title != null && '${t.artist} - ${t.title}'.toLowerCase() == title.toLowerCase()) ||
          (title != null && t.title.toLowerCase() == title.toLowerCase()));
      if (match.isNotEmpty) ids.add(match.first.id);
      title = null;
    }
    if (!context.mounted) return;
    final name = File(path).uri.pathSegments.last.replaceAll(RegExp(r'\.m3u8?$'), '');
    ref.read(musicStoreProvider).createPlaylist(name, ids);
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('Imported "$name" · ${ids.length} of ${lines.where((l) => !l.startsWith('#') && l.trim().isNotEmpty).length} songs found')));
  }

  // -- detail pages ---------------------------------------------------------------------------

  void _openGroup(TrackGroup g, String kind) => _openList(g.name, g.tracks, kind: kind, subtitle: g.subtitle);

  void _openList(String title, List<Track> tracks, {String? kind, String? subtitle, String? smartName}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TrackListScreen(title: title, tracks: tracks, kind: kind ?? 'Playlist', subtitle: subtitle)));
}

/// Interleaves two lists (a, b, a, b…) and appends whatever is left of the
/// longer one, skipping duplicate track ids. Used for For you → Your mix.
List<Track> mixTracks(List<Track> a, List<Track> b) {
  final out = <Track>[];
  final seen = <String>{};
  for (var i = 0; i < math.max(a.length, b.length); i++) {
    for (final list in [a, b]) {
      if (i < list.length && seen.add(list[i].id)) out.add(list[i]);
    }
  }
  return out;
}

/// The music search bar: tap to open [MusicSearchScreen] (library + Audius),
/// or the camera button to scan a Phlio Code ([openPhlioCodeScanner]).
/// Shown under the profile line on Home and at the top of Explore.
class MusicSearchBar extends StatelessWidget {
  const MusicSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = RetroPaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: pal.card,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MusicSearchScreen())),
          child: SizedBox(
            height: 48,
            child: Row(children: [
              const SizedBox(width: 16),
              Icon(Icons.search_rounded, color: pal.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Songs, artists, albums, Audius',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 15)),
              ),
              // Divider between the search field and the scanner button.
              Container(width: 1, height: 22, color: pal.muted.withValues(alpha: .25)),
              IconButton(
                tooltip: 'Scan a Phlio Code',
                icon: Icon(Icons.photo_camera_outlined, color: pal.text),
                onPressed: () => openPhlioCodeScanner(context),
              ),
              const SizedBox(width: 4),
            ]),
          ),
        ),
      ),
    );
  }
}

// -- pieces --------------------------------------------------------------------------------------

/// Pinned tab bar under the header.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader(this.tabs, this.names, this.pal);
  final TabController tabs;
  final List<String> names;
  final RetroPalette pal;
  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(
        color: pal.bg,
        child: TabBar(
          controller: tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: pal.text,
          unselectedLabelColor: pal.muted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900),
          dividerColor: Colors.transparent,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: pal.accent, width: 3),
            borderRadius: BorderRadius.circular(3),
            insets: const EdgeInsets.symmetric(horizontal: 10),
          ),
          tabs: [for (final n in names) Tab(text: n)],
        ),
      );
  @override
  bool shouldRebuild(_TabsHeader old) => old.pal != pal;
}

/// A smart playlist shortcut on For you (icon, name, song count).
class _SmartCard extends StatelessWidget {
  const _SmartCard({required this.name, required this.icon, required this.color, required this.count, required this.onTap});
  final String name;
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final pal = RetroPaletteScope.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w800)),
              Text('$count songs', style: TextStyle(color: pal.muted, fontSize: 11.5)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Album cover with name and artist; used in shelves and the Albums grid.
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.group, required this.onTap, this.width});
  final TrackGroup group;
  final VoidCallback onTap;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final pal = RetroPaletteScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Flexible(child: AspectRatio(aspectRatio: 1, child: Artwork(track: group.cover, radius: 16, label: group.name))),
          const SizedBox(height: 6),
          Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w800)),
          Text(group.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Play / Shuffle buttons with a song count, above song lists.
class _PlayBar extends StatelessWidget {
  const _PlayBar({required this.count, required this.onPlay, required this.onShuffle, this.trailing});
  final int count;
  final VoidCallback onPlay, onShuffle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final pal = RetroPaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      child: Row(children: [
        FilledButton.icon(
          onPressed: count == 0 ? null : onPlay,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play'),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: count == 0 ? null : onShuffle,
          icon: const Icon(Icons.shuffle_rounded),
          label: const Text('Shuffle'),
          style: OutlinedButton.styleFrom(
              foregroundColor: pal.text, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$count songs',
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: TextStyle(color: pal.muted)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Album / artist / genre / folder / smart playlist page.
class TrackListScreen extends ConsumerWidget {
  const TrackListScreen({required this.title, required this.tracks, required this.kind, this.subtitle, super.key});
  final String title, kind;
  final String? subtitle;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    final player = ref.read(musicPlayerProvider);
    final colors = tracks.isEmpty ? ArtColors.phlio : (ref.watch(artColorsProvider(artKey(tracks.first))).valueOrNull ?? ArtColors.phlio);
    final total = tracks.fold<int>(0, (s, t) => s + t.durationMs);
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          body: CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              backgroundColor: pal.bg,
              foregroundColor: pal.text,
              actions: [
                IconButton(
                  tooltip: 'Add all to playlist',
                  onPressed: tracks.isEmpty ? null : () => addToPlaylistSheet(context, ref, tracks),
                  icon: const Icon(Icons.library_add_rounded),
                ),
                IconButton(
                  tooltip: 'Add all to queue',
                  onPressed: tracks.isEmpty ? null : () => player.addToQueue(tracks),
                  icon: const Icon(Icons.playlist_add_rounded),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  RetroGlow(colors: colors, energy: .4, light: !pal.dark),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (tracks.isNotEmpty)
                          Artwork(
                              track: tracks.first,
                              size: 150,
                              radius: kind == 'Artist' ? 75 : 18,
                              label: kind == 'Album' || kind == 'Artist' ? title : null),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(kind.toUpperCase(),
                                style: TextStyle(color: pal.accent, letterSpacing: 1.6, fontWeight: FontWeight.w900, fontSize: 12)),
                            Text(title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: pal.text, fontSize: 24, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text('${tracks.length} songs · ${formatDuration(Duration(milliseconds: total))}',
                                style: TextStyle(color: pal.muted)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: _PlayBar(
                count: tracks.length,
                onPlay: () => player.playTracks(tracks),
                onShuffle: () => player.playTracks(tracks, start: math.Random().nextInt(math.max(1, tracks.length)), shuffled: true),
              ),
            ),
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) => SongTile(
                track: tracks[i],
                index: i + 1,
                showArt: kind != 'Album',
                onTap: () => player.playTracks(tracks, start: i),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ]),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }
}

/// A user playlist: drag to sort, swipe to remove, rename, delete, export.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.playlistId, super.key});
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    final store = ref.watch(musicStoreProvider);
    final byId = ref.watch(trackByIdProvider);
    final p = store.playlists.where((x) => x.id == playlistId).firstOrNull;
    if (p == null) return const Scaffold(body: Center(child: Text('Playlist deleted')));
    final tracks = [for (final id in p.trackIds) if (byId[id] != null) byId[id]!];
    final player = ref.read(musicPlayerProvider);
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(
            backgroundColor: pal.bg,
            foregroundColor: pal.text,
            title: Text(p.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'rename':
                      final name = await askText(context, 'Rename playlist', 'Name', initial: p.name);
                      if (name != null && name.trim().isNotEmpty) {
                        p.name = name.trim();
                        store.save();
                      }
                    case 'export':
                      final dir = await getTemporaryDirectory();
                      final file = File('${dir.path}/${p.name.replaceAll(RegExp(r'[^\w\- ]'), '_')}.m3u');
                      await file.writeAsString([
                        '#EXTM3U',
                        for (final t in tracks) ...[
                          '#EXTINF:${t.durationMs ~/ 1000},${t.artist} - ${t.title}',
                          t.isDevice ? t.uri : t.uri,
                        ],
                      ].join('\n'));
                      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: p.name));
                    case 'queue':
                      await player.addToQueue(tracks);
                    case 'delete':
                      store.deletePlaylist(p);
                      if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'queue', child: Text('Add to queue')),
                  PopupMenuItem(value: 'export', child: Text('Export / share (M3U)')),
                  PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                ],
              ),
            ],
          ),
          body: Column(children: [
            _PlayBar(
              count: tracks.length,
              onPlay: () => player.playTracks(tracks),
              onShuffle: () => player.playTracks(tracks, start: math.Random().nextInt(math.max(1, tracks.length)), shuffled: true),
            ),
            Expanded(
              child: tracks.isEmpty
                  ? Center(child: Text('Long-press any song → Add to playlist', style: TextStyle(color: pal.muted)))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: tracks.length,
                      onReorder: (from, to) {
                        final order = [for (final t in tracks) t.id];
                        final id = order.removeAt(from);
                        order.insert(to > from ? to - 1 : to, id);
                        // Songs no longer in the library keep their place at the end.
                        final missing = p.trackIds.where((x) => !order.contains(x)).toList();
                        p.trackIds
                          ..clear()
                          ..addAll([...order, ...missing]);
                        store.save();
                      },
                      itemBuilder: (_, i) => Dismissible(
                        key: ValueKey('${p.id}-${tracks[i].id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: const Color(0xFFF5636B),
                          child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          p.trackIds.remove(tracks[i].id);
                          store.save();
                        },
                        child: SongTile(
                          track: tracks[i],
                          onTap: () => player.playTracks(tracks, start: i),
                          trailing: ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle_rounded, color: pal.muted)),
                        ),
                      ),
                    ),
            ),
          ]),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }
}

/// Search across your library (artists, albums, songs) and Audius.
class MusicSearchScreen extends ConsumerStatefulWidget {
  const MusicSearchScreen({super.key});
  @override
  ConsumerState<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

/// Filters the library on every keystroke; queries Audius 450 ms after
/// typing stops.
class _MusicSearchScreenState extends ConsumerState<MusicSearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _online = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _online = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(retroPaletteProvider);
    final all = ref.watch(musicLibraryProvider).valueOrNull ?? const <Track>[];
    final q = _q.text.trim().toLowerCase();
    final songs = q.isEmpty ? const <Track>[] : all.where((t) => '${t.title} ${t.artist} ${t.album} ${t.genre}'.toLowerCase().contains(q)).toList();
    final albums = q.isEmpty ? const <TrackGroup>[] : ref.watch(albumsProvider).where((a) => a.name.toLowerCase().contains(q)).toList();
    final artists = q.isEmpty ? const <TrackGroup>[] : ref.watch(artistsProvider).where((a) => a.name.toLowerCase().contains(q)).toList();
    final player = ref.read(musicPlayerProvider);
    void open(TrackGroup g, String kind) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TrackListScreen(title: g.name, tracks: g.tracks, kind: kind, subtitle: g.subtitle)));
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(
            backgroundColor: pal.bg,
            foregroundColor: pal.text,
            title: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _changed,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: pal.text),
              decoration: InputDecoration(hintText: 'Songs, albums, artists', border: InputBorder.none, hintStyle: TextStyle(color: pal.muted)),
            ),
            actions: [
              if (_q.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: () {
                    _q.clear();
                    _changed('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              IconButton(
                tooltip: 'Scan a Phlio Code',
                onPressed: () => openPhlioCodeScanner(context),
                icon: const Icon(Icons.photo_camera_outlined),
              ),
            ],
          ),
          body: ListView(children: [
            if (artists.isNotEmpty) const SectionLabel('Artists'),
            for (final a in artists.take(5))
              ListTile(
                leading: ClipOval(child: Artwork(track: a.cover, size: 44, radius: 0, label: a.name)),
                title: Text(a.name),
                subtitle: Text(a.subtitle),
                onTap: () => open(a, 'Artist'),
              ),
            if (albums.isNotEmpty) const SectionLabel('Albums'),
            for (final a in albums.take(5))
              ListTile(
                leading: Artwork(track: a.cover, size: 44, radius: 8, label: a.name),
                title: Text(a.name),
                subtitle: Text(a.subtitle),
                onTap: () => open(a, 'Album'),
              ),
            if (songs.isNotEmpty) const SectionLabel('Songs'),
            for (final (i, t) in songs.take(30).indexed) SongTile(track: t, onTap: () => player.playTracks(songs, start: i)),
            if (_online.length >= 2) ..._audius(pal, player),
            if (q.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  Icon(Icons.travel_explore_rounded, size: 44, color: pal.muted),
                  const SizedBox(height: 10),
                  Text('Search your library and millions of open tracks on Audius.',
                      textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
                ]),
              ),
          ]),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }
}

/// Audius results for the search screen.
extension on _MusicSearchScreenState {
  List<Widget> _audius(RetroPalette pal, MusicPlayer player) {
    final res = ref.watch(audiusSearchProvider(_online));
    return res.when<List<Widget>>(
      loading: () => [
        const SectionLabel('On Audius'),
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      ],
      error: (_, __) => [
        const SectionLabel('On Audius'),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text('Audius is unreachable right now.', style: TextStyle(color: pal.muted)),
        ),
      ],
      data: (r) {
        final (tracks, artists) = r;
        return [
          if (artists.isNotEmpty) ...[
            const SectionLabel('Artists on Audius'),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => ArtistBubble(artist: artists[i]),
              ),
            ),
          ],
          if (tracks.isNotEmpty) const SectionLabel('Songs on Audius'),
          for (final (i, t) in tracks.indexed) SongTile(track: t, onTap: () => player.playTracks(tracks, start: i)),
          if (tracks.isEmpty && artists.isEmpty)
            Padding(padding: const EdgeInsets.all(30), child: Center(child: Text('No results on Audius', style: TextStyle(color: pal.muted)))),
        ];
      },
    );
  }
}

/// Music settings: theme, now-playing style, library sources and filters,
/// hidden folders, playback and history.
class MusicSettingsScreen extends ConsumerWidget {
  const MusicSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    final store = ref.watch(musicStoreProvider);
    final s = store.settings;
    final player = ref.watch(musicPlayerProvider);
    void set(VoidCallback f) {
      f();
      store.save();
    }

    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(backgroundColor: pal.bg, foregroundColor: pal.text, title: const Text('Music settings')),
          body: ListView(children: [
            const SectionLabel('Theme'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                for (final (t, name) in const [
                  (MusicTheme.white, 'Clearly White'),
                  (MusicTheme.dark, 'Kinda Dark'),
                  (MusicTheme.black, 'Just Black'),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => set(() => s.theme = t),
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        height: 92,
                        decoration: BoxDecoration(
                          color: RetroPalette.of(t).bg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: s.theme == t ? pal.accent : pal.muted.withValues(alpha: .3), width: s.theme == t ? 3 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [RetroPalette.of(t).accent, RetroPalette.of(t).accent2]))),
                          const SizedBox(height: 8),
                          Text(name,
                              style: TextStyle(color: RetroPalette.of(t).text, fontWeight: FontWeight.w800, fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            const SectionLabel('Now playing theme'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in nowPlayingStyleNames.entries)
                  ChoiceChip(label: Text(e.value), selected: s.style == e.key, onSelected: (_) => set(() => s.style = e.key)),
              ]),
            ),
            SwitchListTile(
              title: const Text('Carousel effect for album covers'),
              value: s.carousel,
              onChanged: (v) => set(() => s.carousel = v),
            ),
            SwitchListTile(
              title: const Text('Lyrics over the cover'),
              subtitle: const Text('Off: lyrics replace the cover'),
              value: s.lyricsOverCover,
              onChanged: (v) => set(() => s.lyricsOverCover = v),
            ),
            const SectionLabel('Library'),
            ListTile(
              title: const Text('Music duration filter'),
              subtitle: Text(s.minDurationSec == 0 ? 'Show all songs' : 'Hide songs shorter than ${s.minDurationSec}s'),
            ),
            Slider(
              value: s.minDurationSec.toDouble(),
              max: 120,
              divisions: 24,
              label: '${s.minDurationSec}s',
              onChanged: (v) => set(() => s.minDurationSec = v.round()),
            ),
            SwitchListTile(
              title: const Text('Music on this phone'),
              subtitle: const Text('Include audio files from your device'),
              value: s.includeDevice,
              onChanged: (v) {
                set(() => s.includeDevice = v);
                if (v) ref.read(deviceMusicProvider.notifier).scan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Rescan device music'),
              onTap: () => ref.read(deviceMusicProvider.notifier).scan(),
            ),
            SwitchListTile(
              title: const Text('Include podcasts'),
              value: s.includePodcasts,
              onChanged: (v) => set(() => s.includePodcasts = v),
            ),
            ListTile(
              title: const Text('Hidden folders'),
              subtitle: Text(s.blacklist.isEmpty ? 'None — long-press a folder to hide it' : s.blacklist.join('\n')),
              trailing: s.blacklist.isEmpty
                  ? null
                  : TextButton(onPressed: () => set(() => s.blacklist = []), child: const Text('Show all')),
            ),
            const SectionLabel('Playback'),
            ListTile(
              title: const Text('Sleep timer'),
              subtitle: Text(player.sleepAt == null ? 'Off' : 'Stops at ${TimeOfDay.fromDateTime(player.sleepAt!).format(context)}'),
              onTap: () => showSleepTimer(context, ref),
            ),
            SwitchListTile(
              title: const Text('Pause when volume is set to zero'),
              value: s.pauseOnZeroVolume,
              onChanged: (v) => set(() => s.pauseOnZeroVolume = v),
            ),
            ListTile(
              leading: const Icon(Icons.directions_car_rounded),
              title: const Text('Driving mode'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrivingModeScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Clear listening history'),
              onTap: store.clearHistory,
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                  'Gapless playback, lock-screen and notification controls and headset / Bluetooth buttons are always on.',
                  style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}
