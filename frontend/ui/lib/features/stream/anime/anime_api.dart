// Phlio Stream · Anime — catalogue data from AniList (anilist.co).
//
// The app talks to the Phlio backend (`/api/v1/stream/anime/...`, see
// backend/app/api/v1/anime.py), which queries AniList's GraphQL API, caches
// the results for every user and returns a small, stable JSON shape.
//
// AniList is a catalogue: titles, artwork, synopses, scores, airing times,
// official trailers and links to the official services that stream each
// show. Phlio plays trailers and opens those official services to watch;
// it never hosts or scrapes episodes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';

/// One anime title as returned by the backend (list card or full details).
class Anime {
  Anime(this.raw);

  /// The backend JSON, kept so new fields need no model change.
  final Map<String, dynamic> raw;

  /// AniList id.
  int get id => (raw['id'] as num).toInt();

  /// English title when there is one, otherwise romaji.
  String get title => '${raw['title'] ?? 'Untitled'}';

  /// Japanese title, if known.
  String? get native => raw['native'] as String?;

  /// Romaji title, if known.
  String? get romaji => raw['romaji'] as String?;

  /// Poster image URL.
  String? get cover => raw['cover'] as String?;

  /// Wide banner image URL.
  String? get banner => raw['banner'] as String?;

  /// AniList's dominant poster colour (`#rrggbb`), if any.
  String? get color => raw['color'] as String?;

  /// TV, MOVIE, OVA, ONA, SPECIAL, TV_SHORT, MUSIC.
  String? get format => raw['format'] as String?;

  /// RELEASING, FINISHED, NOT_YET_RELEASED, CANCELLED, HIATUS.
  String? get status => raw['status'] as String?;

  /// Episode count (null while airing with no fixed count).
  int? get episodes => (raw['episodes'] as num?)?.toInt();

  /// Minutes per episode.
  int? get duration => (raw['duration'] as num?)?.toInt();

  /// Average score out of 100.
  int? get score => (raw['score'] as num?)?.toInt();

  /// Season year.
  int? get year => (raw['year'] as num?)?.toInt();

  /// FALL / WINTER / SPRING / SUMMER.
  String? get season => raw['season'] as String?;

  /// Genre names.
  List<String> get genres => [for (final g in (raw['genres'] as List? ?? const [])) '$g'];

  /// Next episode number and its air time, while airing.
  (int, DateTime)? get nextEpisode {
    final n = raw['next_episode'];
    if (n is! Map) return null;
    return (
      (n['episode'] as num).toInt(),
      DateTime.fromMillisecondsSinceEpoch((n['airing_at'] as num).toInt() * 1000),
    );
  }

  /// Plain-text synopsis (details only).
  String get description => '${raw['description'] ?? ''}';

  /// Main studios (details only).
  List<String> get studios => [for (final s in (raw['studios'] as List? ?? const [])) '$s'];

  /// Official trailer `{site, id, url, thumbnail}` (details only).
  Map<String, dynamic>? get trailer => raw['trailer'] as Map<String, dynamic>?;

  /// Official streaming services `{site, url, language, color, icon}` (details only).
  List<Map<String, dynamic>> get whereToWatch =>
      [for (final l in (raw['where_to_watch'] as List? ?? const [])) Map<String, dynamic>.from(l as Map)];

  /// Per-episode links on official services `{title, thumbnail, url, site}` (details only).
  List<Map<String, dynamic>> get episodeLinks =>
      [for (final e in (raw['episodes_list'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];

  /// Similar titles (details only).
  List<Anime> get recommendations =>
      [for (final r in (raw['recommendations'] as List? ?? const [])) Anime(Map<String, dynamic>.from(r as Map))];

  /// The title's AniList page.
  String get anilistUrl => '${raw['anilist_url'] ?? 'https://anilist.co/anime/$id'}';

  /// "TV · 2024 · 12 eps" style summary line.
  String get meta => [
        if (format != null) _format(format!),
        if (year != null) '$year',
        if (episodes != null) '$episodes ep${episodes == 1 ? '' : 's'}',
        if (status == 'NOT_YET_RELEASED') 'Upcoming' else if (status == 'RELEASING') 'Airing',
      ].join(' · ');

  static String _format(String f) => switch (f) {
        'TV' => 'TV',
        'TV_SHORT' => 'TV short',
        'MOVIE' => 'Movie',
        'SPECIAL' => 'Special',
        'MUSIC' => 'Music video',
        _ => f,
      };
}

/// One page of a chart.
class AnimePage {
  const AnimePage(this.items, {this.hasMore = false, this.season});

  /// Titles on this page.
  final List<Anime> items;

  /// Whether AniList has another page.
  final bool hasMore;

  /// "Fall 2026" for the season chart.
  final String? season;
}

Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async {
  final res = await getIt<ApiClient>().dio.get<dynamic>('/stream/anime$path', queryParameters: query);
  return Map<String, dynamic>.from(res.data as Map);
}

AnimePage _page(Map<String, dynamic> body) => AnimePage(
      [for (final m in (body['items'] as List? ?? const [])) Anime(Map<String, dynamic>.from(m as Map))],
      hasMore: body['has_more'] == true,
      season: body['season'] as String?,
    );

/// A chart (`trending`, `season`, `popular`, `top`, `upcoming`), optionally
/// for one genre. Kept alive for the session once loaded.
final animeListProvider = FutureProvider.family<AnimePage, (String, String?)>((ref, key) async {
  final (list, genre) = key;
  return _page(await _get('/lists/$list', {if (genre != null) 'genre': genre}));
});

/// Title search (2+ characters).
final animeSearchProvider = FutureProvider.autoDispose.family<List<Anime>, String>((ref, q) async {
  ref.keepAlive();
  return _page(await _get('/search', {'q': q})).items;
});

/// AniList's genre list (adult genres excluded by the backend).
final animeGenresProvider = FutureProvider<List<String>>((ref) async {
  final body = await _get('/genres');
  return [for (final g in (body['genres'] as List? ?? const [])) '$g'];
});

/// Full details for one title.
final animeDetailProvider = FutureProvider.autoDispose.family<Anime, int>((ref, id) async {
  ref.keepAlive();
  return Anime(await _get('/$id'));
});
