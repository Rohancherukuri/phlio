// Phlio Stream · Music — the library: Phlio Stream tracks + device audio,
// with tag edits, the duration filter and folder blacklist applied, and the
// derived views Retro offers (albums, artists, genres, folders, smart
// playlists).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../shared/content/content_surface.dart' show catalogProvider;
import '../../../shared/content/stream_screen.dart' show streamCategory;
import 'music_models.dart';

/// Phone audio files (photo_manager's audio index; Android).
class DeviceMusic extends StateNotifier<AsyncValue<List<Track>>> {
  DeviceMusic() : super(const AsyncData([]));

  bool permissionDenied = false;

  /// Reads every audio file Android has indexed. With [ask], asks for the
  /// music permission first; sets [permissionDenied] when it's refused.
  Future<void> scan({bool ask = true}) async {
    if (!Platform.isAndroid) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    try {
      final permission = ask
          ? await PhotoManager.requestPermissionExtend(
              requestOption: const PermissionRequestOption(
                androidPermission: AndroidPermission(type: RequestType.audio, mediaLocation: false),
              ),
            )
          : PermissionState.authorized;
      if (!permission.hasAccess) {
        permissionDenied = true;
        state = const AsyncData([]);
        return;
      }
      permissionDenied = false;
      final paths = await PhotoManager.getAssetPathList(type: RequestType.audio, onlyAll: true);
      if (paths.isEmpty) {
        state = const AsyncData([]);
        return;
      }
      final all = paths.first;
      final count = await all.assetCountAsync;
      final assets = await all.getAssetListRange(start: 0, end: count.clamp(0, 5000));
      final tracks = <Track>[];
      for (final a in assets) {
        final file = await a.originFile;
        if (file == null) continue;
        final name = a.title ?? file.uri.pathSegments.last;
        final base = name.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '');
        // "Artist - Title" file names are common for side-loaded music.
        final parts = base.split(' - ');
        final folder = (a.relativePath ?? file.parent.path).replaceAll(RegExp(r'/$'), '');
        final folderName = folder.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Music';
        tracks.add(Track(
          id: 'dev_${a.id}',
          title: parts.length > 1 ? parts.sublist(1).join(' - ') : base,
          artist: parts.length > 1 ? parts.first : 'Unknown artist',
          album: folderName,
          uri: file.path,
          durationMs: a.duration * 1000,
          source: 'device',
          folder: folder,
          addedAt: a.createDateTime,
        ));
      }
      state = AsyncData(tracks);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

/// Audio files on this phone (empty until [DeviceMusic.scan] runs).
final deviceMusicProvider =
    StateNotifierProvider<DeviceMusic, AsyncValue<List<Track>>>((ref) => DeviceMusic());

/// A Phlio Stream catalog row as a library track.
Track trackFromStreamItem(Map item) {
  final category = streamCategory(item);
  final genres = (item['genres'] as List?)?.whereType<String>().toList() ?? const [];
  final ref = '${item['ref']}';
  return Track(
    id: 'phl_$ref',
    ref: ref,
    title: '${item['title'] ?? 'Untitled'}',
    artist: '${item['publisher'] ?? item['artist'] ?? 'Phlio Stream'}',
    album: '${item['album'] ?? (category == 'Podcasts' ? item['title'] : '${item['publisher'] ?? 'Phlio'} · Singles')}',
    genre: genres.isNotEmpty ? genres.first : (category == 'Podcasts' ? 'Podcast' : 'Music'),
    year: int.tryParse('${item['year'] ?? ''}'),
    durationMs: ((item['duration_seconds'] ?? item['duration'] ?? 0) as num).toInt() * 1000,
    uri: '${item['media_url']}',
    artUrl: item['image_url'] as String?,
    podcast: category == 'Podcasts',
    folder: category == 'Podcasts' ? 'Phlio Stream/Podcasts' : 'Phlio Stream/Music',
    addedAt: DateTime.tryParse('${item['created_at'] ?? ''}'),
  );
}

/// The whole library, filtered and tag-edited.
final musicLibraryProvider = Provider.autoDispose<AsyncValue<List<Track>>>((ref) {
  final store = ref.watch(musicStoreProvider);
  final s = store.settings;
  final phlio = ref.watch(catalogProvider('stream'));
  final device = ref.watch(deviceMusicProvider);
  if (phlio.isLoading && !phlio.hasValue) return const AsyncLoading();
  final rows = phlio.valueOrNull ?? const [];
  final tracks = <Track>[
    for (final item in rows.cast<Map>())
      if (['Music', 'Podcasts'].contains(streamCategory(item)) &&
          (item['media_url'] as String?)?.isNotEmpty == true &&
          (s.includePodcasts || streamCategory(item) != 'Podcasts'))
        trackFromStreamItem(item),
    if (s.includeDevice) ...?device.valueOrNull,
  ];
  final out = [
    for (final t in tracks)
      if (!s.blacklist.any((b) => t.folder.startsWith(b)) &&
          (s.minDurationSec == 0 || t.durationMs == 0 || t.durationMs >= s.minDurationSec * 1000))
        t.withTags(store.tags[t.id])
  ];
  if (phlio.hasError && out.isEmpty) return AsyncError(phlio.error!, phlio.stackTrace!);
  return AsyncData(out);
});

/// Library tracks plus the Audius tracks you've played or saved.
final trackByIdProvider = Provider.autoDispose<Map<String, Track>>((ref) {
  final store = ref.watch(musicStoreProvider);
  final all = ref.watch(musicLibraryProvider).valueOrNull ?? const [];
  return {
    for (final t in store.remote.values) t.id: t.withTags(store.tags[t.id]),
    for (final t in all) t.id: t,
  };
});

// -- derived groupings ----------------------------------------------------------------

/// A named group of tracks: an album, artist, genre or folder.
class TrackGroup {
  TrackGroup(this.name, this.tracks, {this.subtitle = ''});
  final String name, subtitle;
  final List<Track> tracks;
  /// The track whose artwork represents the group.
  Track get cover => tracks.first;
}

List<TrackGroup> _group(List<Track> tracks, String Function(Track) key, {String Function(List<Track>)? sub}) {
  final map = <String, List<Track>>{};
  for (final t in tracks) {
    map.putIfAbsent(key(t), () => []).add(t);
  }
  final groups = [
    for (final e in map.entries) TrackGroup(e.key, e.value, subtitle: sub?.call(e.value) ?? '${e.value.length} songs')
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}

/// Library grouped by album, tracks in track-number order.
final albumsProvider = Provider.autoDispose<List<TrackGroup>>((ref) {
  final all = ref.watch(musicLibraryProvider).valueOrNull ?? const [];
  return _group(all, (t) => t.album, sub: (ts) => '${ts.first.artist} · ${ts.length} songs')
    ..forEach((g) => g.tracks.sort((a, b) => (a.trackNo ?? 999).compareTo(b.trackNo ?? 999)));
});

/// Library grouped by artist, with album and song counts.
final artistsProvider = Provider.autoDispose<List<TrackGroup>>((ref) {
  final all = ref.watch(musicLibraryProvider).valueOrNull ?? const [];
  return _group(all, (t) => t.artist, sub: (ts) {
    final albums = ts.map((t) => t.album).toSet().length;
    return '$albums album${albums == 1 ? '' : 's'} · ${ts.length} songs';
  });
});

/// Library grouped by genre.
final genresProvider = Provider.autoDispose<List<TrackGroup>>((ref) {
  final all = ref.watch(musicLibraryProvider).valueOrNull ?? const [];
  return _group(all, (t) => t.genre);
});

/// Library grouped by folder (Phlio Stream sections and phone folders).
final foldersProvider = Provider.autoDispose<List<TrackGroup>>((ref) {
  final all = ref.watch(musicLibraryProvider).valueOrNull ?? const [];
  return _group(all, (t) => t.folder, sub: (ts) => '${ts.length} songs');
});

/// Smart auto playlists: Recently added, Recently played, Most played,
/// History, Favourites.
class SmartLists {
  SmartLists(this.recentlyAdded, this.recentlyPlayed, this.mostPlayed, this.history, this.favorites);
  final List<Track> recentlyAdded, recentlyPlayed, mostPlayed, history, favorites;
}

/// The smart playlists, recomputed whenever the library or history changes.
final smartListsProvider = Provider.autoDispose<SmartLists>((ref) {
  final store = ref.watch(musicStoreProvider);
  final all = ref.watch(musicLibraryProvider).valueOrNull ?? const <Track>[];
  final byId = ref.watch(trackByIdProvider);
  final added = [...all.where((t) => t.addedAt != null)]..sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
  final seen = <String>{};
  final recent = <Track>[
    for (final (id, _) in store.history)
      if (byId[id] != null && seen.add(id)) byId[id]!
  ];
  final most = [...byId.values.where((t) => (store.playCounts[t.id] ?? 0) > 0)]
    ..sort((a, b) => (store.playCounts[b.id] ?? 0).compareTo(store.playCounts[a.id] ?? 0));
  final history = <Track>[for (final (id, _) in store.history) if (byId[id] != null) byId[id]!];
  return SmartLists(
    (added.isEmpty ? all.reversed.toList() : added).take(50).toList(),
    recent.take(50).toList(),
    most.take(50).toList(),
    history.take(200).toList(),
    [for (final id in store.favorites) if (byId[id] != null) byId[id]!],
  );
});

/// `m:ss`, or `h:mm:ss` for an hour or more.
String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
