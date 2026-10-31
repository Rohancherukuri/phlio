// Phlio Stream · Music — models and on-device persistence.
//
// A Retro-Music-Player-style library for Phlio: tracks come from Phlio
// Stream (music + podcasts on the server) and from the phone's own audio
// files. Everything personal — playlists, favourites, history, play counts,
// tag edits, lyrics, settings and the last queue — is kept in one JSON file
// in the app documents folder, so it survives restarts without a backend.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// One playable song or episode, wherever it comes from: Phlio Stream
/// (`phlio`), a file on this phone (`device`) or the Audius catalogue (`audius`).
/// Immutable; tag edits produce a new copy via [withTags].
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.uri,
    this.genre = 'Unknown',
    this.year,
    this.trackNo,
    this.durationMs = 0,
    this.artUrl,
    this.source = 'phlio',
    this.folder = 'Phlio Stream',
    this.podcast = false,
    this.addedAt,
    this.ref,
    this.artistId,
    this.plays,
  });

  final String id, title, artist, album, genre, uri, source, folder;
  final int? year, trackNo;
  final int durationMs;
  final String? artUrl; // network (Phlio) or null (device: generated art)
  final bool podcast;
  final DateTime? addedAt;
  final String? ref; // Phlio content ref / Audius track id
  final String? artistId; // Audius artist id (artist info page)
  final int? plays; // Audius play count

  /// True for audio files on this phone (played from [uri] as a file path).
  bool get isDevice => source == 'device';
  /// True for tracks streamed from Audius ([ref] is the Audius track id).
  bool get isAudius => source == 'audius';
  /// [durationMs] as a [Duration] (zero when unknown).
  Duration get duration => Duration(milliseconds: durationMs);

  /// A copy with the given tags (and artwork) replaced; ids and source stay.
  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? year,
    int? trackNo,
    int? durationMs,
    String? artUrl,
  }) =>
      Track(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        uri: uri,
        genre: genre ?? this.genre,
        year: year ?? this.year,
        trackNo: trackNo ?? this.trackNo,
        durationMs: durationMs ?? this.durationMs,
        artUrl: artUrl ?? this.artUrl,
        source: source,
        folder: folder,
        podcast: podcast,
        addedAt: addedAt,
        ref: ref,
        artistId: artistId,
        plays: plays,
      );

  /// For tracks that live outside the library (Audius), so playlists,
  /// favourites, history and the restored queue can find them again.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'uri': uri,
        'source': source,
        'folder': folder,
        if (year != null) 'year': year,
        'durationMs': durationMs,
        if (artUrl != null) 'artUrl': artUrl,
        if (ref != null) 'ref': ref,
        if (artistId != null) 'artistId': artistId,
        if (plays != null) 'plays': plays,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
      };

  static Track fromJson(Map j) => Track(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        artist: '${j['artist'] ?? ''}',
        album: '${j['album'] ?? ''}',
        genre: '${j['genre'] ?? 'Music'}',
        uri: '${j['uri'] ?? ''}',
        source: '${j['source'] ?? 'audius'}',
        folder: '${j['folder'] ?? 'Audius'}',
        year: (j['year'] as num?)?.toInt(),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        artUrl: j['artUrl'] as String?,
        ref: j['ref'] as String?,
        artistId: j['artistId'] as String?,
        plays: (j['plays'] as num?)?.toInt(),
        addedAt: DateTime.tryParse('${j['addedAt'] ?? ''}'),
      );

  /// Applies the user's tag edits (Tag editor).
  Track withTags(Map? tags) {
    if (tags == null || tags.isEmpty) return this;
    String? s(String k) => (tags[k] as String?)?.trim().isEmpty == true ? null : tags[k] as String?;
    return copyWith(
      title: s('title'),
      artist: s('artist'),
      album: s('album'),
      genre: s('genre'),
      year: int.tryParse('${tags['year'] ?? ''}'),
      trackNo: int.tryParse('${tags['trackNo'] ?? ''}'),
    );
  }
}

/// A user playlist: an ordered list of track ids (works across sources).
class Playlist {
  Playlist({required this.id, required this.name, List<String>? trackIds, DateTime? created})
      : trackIds = trackIds ?? [],
        created = created ?? DateTime.now();
  final String id;
  String name;
  final List<String> trackIds;
  final DateTime created;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'tracks': trackIds, 'created': created.toIso8601String()};

  static Playlist fromJson(Map j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String,
        trackIds: [for (final t in (j['tracks'] as List? ?? const [])) '$t'],
        created: DateTime.tryParse('${j['created']}'),
      );
}

/// Base themes, like Retro's Clearly White / Kinda Dark / Just Black.
enum MusicTheme { white, dark, black }

/// Now-playing themes (Retro's 10 + Card, Gradient, Circle).
enum NowPlayingStyle { normal, fit, flat, color, material, classic, adaptive, blur, tiny, peek, card, gradient, circle }

/// Display names for the now-playing themes, in menu order.
const nowPlayingStyleNames = {
  NowPlayingStyle.normal: 'Normal',
  NowPlayingStyle.fit: 'Fit',
  NowPlayingStyle.flat: 'Flat',
  NowPlayingStyle.color: 'Color',
  NowPlayingStyle.material: 'Material',
  NowPlayingStyle.classic: 'Classic',
  NowPlayingStyle.adaptive: 'Adaptive',
  NowPlayingStyle.blur: 'Blur',
  NowPlayingStyle.tiny: 'Tiny',
  NowPlayingStyle.peek: 'Peek',
  NowPlayingStyle.card: 'Card',
  NowPlayingStyle.gradient: 'Gradient',
  NowPlayingStyle.circle: 'Circle',
};

/// Every music preference (theme, now-playing style, filters, volume…),
/// saved inside [MusicStore]'s JSON file.
class MusicSettings {
  MusicSettings({
    this.theme = MusicTheme.dark,
    this.style = NowPlayingStyle.normal,
    this.minDurationSec = 0,
    this.carousel = true,
    this.lyricsOverCover = true,
    this.includeDevice = true,
    this.includePodcasts = true,
    this.blacklist = const [],
    this.volume = 1,
    this.speed = 1,
    this.pauseOnZeroVolume = true,
    this.keepScreenOnDriving = true,
  });

  MusicTheme theme;
  NowPlayingStyle style;
  int minDurationSec; // Music duration filter
  bool carousel; // Carousel effect for album covers
  bool lyricsOverCover; // synced lyrics layout: over cover / replace cover
  bool includeDevice, includePodcasts;
  List<String> blacklist; // folders hidden from the library
  double volume, speed;
  bool pauseOnZeroVolume, keepScreenOnDriving;

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'style': style.name,
        'minDurationSec': minDurationSec,
        'carousel': carousel,
        'lyricsOverCover': lyricsOverCover,
        'includeDevice': includeDevice,
        'includePodcasts': includePodcasts,
        'blacklist': blacklist,
        'volume': volume,
        'speed': speed,
        'pauseOnZeroVolume': pauseOnZeroVolume,
        'keepScreenOnDriving': keepScreenOnDriving,
      };

  static MusicSettings fromJson(Map j) => MusicSettings(
        theme: MusicTheme.values.where((e) => e.name == j['theme']).firstOrNull ?? MusicTheme.dark,
        style: NowPlayingStyle.values.where((e) => e.name == j['style']).firstOrNull ?? NowPlayingStyle.normal,
        minDurationSec: (j['minDurationSec'] as num?)?.toInt() ?? 0,
        carousel: j['carousel'] != false,
        lyricsOverCover: j['lyricsOverCover'] != false,
        includeDevice: j['includeDevice'] != false,
        includePodcasts: j['includePodcasts'] != false,
        blacklist: [for (final b in (j['blacklist'] as List? ?? const [])) '$b'],
        volume: (j['volume'] as num?)?.toDouble() ?? 1,
        speed: (j['speed'] as num?)?.toDouble() ?? 1,
        pauseOnZeroVolume: j['pauseOnZeroVolume'] != false,
        keepScreenOnDriving: j['keepScreenOnDriving'] != false,
      );
}

/// Everything the music player remembers between launches.
class MusicStore extends ChangeNotifier {
  MusicStore() {
    unawaited(_load());
  }

  MusicSettings settings = MusicSettings();
  final playlists = <Playlist>[];
  final favorites = <String>{};
  final history = <(String, DateTime)>[]; // newest first
  final playCounts = <String, int>{};
  final tags = <String, Map<String, dynamic>>{}; // tag editor overrides
  final lyrics = <String, String>{}; // track id -> LRC / plain text
  final remote = <String, Track>{}; // Audius tracks you've played or saved
  List<String> lastQueue = [];
  int lastIndex = 0;
  int lastPositionMs = 0;
  bool loaded = false;
  Timer? _saveTimer;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/phlio_music.json');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        settings = MusicSettings.fromJson((j['settings'] as Map?) ?? const {});
        playlists.addAll([for (final p in (j['playlists'] as List? ?? const [])) Playlist.fromJson(p as Map)]);
        favorites.addAll([for (final f in (j['favorites'] as List? ?? const [])) '$f']);
        for (final h in (j['history'] as List? ?? const [])) {
          final at = DateTime.tryParse('${(h as Map)['at']}');
          if (at != null) history.add(('${h['id']}', at));
        }
        for (final e in ((j['playCounts'] as Map?) ?? const {}).entries) {
          playCounts['${e.key}'] = (e.value as num).toInt();
        }
        for (final e in ((j['tags'] as Map?) ?? const {}).entries) {
          tags['${e.key}'] = Map<String, dynamic>.from(e.value as Map);
        }
        for (final e in ((j['lyrics'] as Map?) ?? const {}).entries) {
          lyrics['${e.key}'] = '${e.value}';
        }
        for (final r in (j['remote'] as List? ?? const [])) {
          final t = Track.fromJson(r as Map);
          remote[t.id] = t;
        }
        lastQueue = [for (final q in (j['queue'] as List? ?? const [])) '$q'];
        lastIndex = (j['queueIndex'] as num?)?.toInt() ?? 0;
        lastPositionMs = (j['positionMs'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('Music store could not load: $e');
    }
    loaded = true;
    notifyListeners();
  }

  /// Debounced write.
  void save() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final f = await _file();
        await f.writeAsString(jsonEncode({
          'settings': settings.toJson(),
          'playlists': [for (final p in playlists) p.toJson()],
          'favorites': favorites.toList(),
          'history': [
            for (final (id, at) in history.take(500)) {'id': id, 'at': at.toIso8601String()}
          ],
          'playCounts': playCounts,
          'tags': tags,
          'lyrics': lyrics,
          'remote': [for (final t in remote.values) t.toJson()],
          'queue': lastQueue,
          'queueIndex': lastIndex,
          'positionMs': lastPositionMs,
        }));
      } catch (e) {
        debugPrint('Music store could not save: $e');
      }
    });
  }

  // -- library state -----------------------------------------------------------------

  /// Whether the track with [id] is in Favourites.
  bool isFavorite(String id) => favorites.contains(id);

  /// Keeps an Audius track findable by id (newest last, capped).
  void rememberRemote(Track t, {bool save = false}) {
    if (!t.isAudius) return;
    remote.remove(t.id);
    remote[t.id] = t;
    if (remote.length > 800) {
      final keep = {...favorites, for (final p in playlists) ...p.trackIds, ...lastQueue};
      for (final id in remote.keys.toList()) {
        if (remote.length <= 600) break;
        if (!keep.contains(id)) remote.remove(id);
      }
    }
    if (save) this.save();
  }

  /// Adds the track to Favourites, or removes it if it's already there.
  void toggleFavorite(String id) {
    if (!favorites.remove(id)) favorites.add(id);
    save();
  }

  /// Counts a play: moves the track to the top of History (merging repeats
  /// within two minutes) and bumps its play count.
  void recordPlay(String id) {
    history.removeWhere((h) => h.$1 == id && DateTime.now().difference(h.$2).inMinutes < 2);
    history.insert(0, (id, DateTime.now()));
    if (history.length > 500) history.removeRange(500, history.length);
    playCounts[id] = (playCounts[id] ?? 0) + 1;
    save();
  }

  /// Empties History (play counts are kept for Most played).
  void clearHistory() {
    history.clear();
    save();
  }

  Playlist createPlaylist(String name, [List<String> ids = const []]) {
    final p = Playlist(id: 'pl_${DateTime.now().microsecondsSinceEpoch}', name: name.trim(), trackIds: [...ids]);
    playlists.add(p);
    save();
    return p;
  }

  /// Appends tracks to [p], skipping ones already in it.
  void addToPlaylist(Playlist p, Iterable<String> ids) {
    for (final id in ids) {
      if (!p.trackIds.contains(id)) p.trackIds.add(id);
    }
    save();
  }

  /// Removes the playlist (its songs stay in the library).
  void deletePlaylist(Playlist p) {
    playlists.remove(p);
    save();
  }

  /// Stores tag-editor values for a track (title, artist, album, genre,
  /// year, track number). They override the source's tags in the app.
  void setTags(String id, Map<String, dynamic> values) {
    tags[id] = values;
    save();
  }

  /// Saves LRC or plain lyrics for a track; empty text removes them.
  void setLyrics(String id, String text) {
    if (text.trim().isEmpty) {
      lyrics.remove(id);
    } else {
      lyrics[id] = text;
    }
    save();
  }

  /// Remembers the playing queue, position in it and position in the song,
  /// so the next launch can restore it.
  void rememberQueue(List<String> ids, int index, int positionMs) {
    lastQueue = ids;
    lastIndex = index;
    lastPositionMs = positionMs;
    save();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// The app-wide music store (loaded once from disk, saved on change).
final musicStoreProvider = ChangeNotifierProvider<MusicStore>((ref) => MusicStore());
