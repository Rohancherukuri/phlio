// Phlio Stream · Anime — browsing and detail screens (data: anime_api.dart).
//
//  * [AnimeBrowser]: the "Anime" category of Phlio Stream. Genre chips, then
//    shelves (Trending now, Popular this season, Top rated, Upcoming), or a
//    grid for a genre / search query.
//  * [AnimeShelf]: a horizontal row of posters for one chart; also shown on
//    the Stream home page.
//  * [AnimeDetailScreen]: banner, synopsis, next episode countdown, official
//    trailer, "Where to watch" (official services), episode links and
//    recommendations. Trailers and episodes open in the official app/site.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'anime_api.dart';

/// Opens [url] in the official app if installed, else the browser.
Future<void> _openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok = uri != null && uri.scheme == 'https' && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that link.')));
  }
}

Color? _hex(String? value) {
  if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return null;
  return Color(int.parse('ff${value.substring(1)}', radix: 16));
}

/// Opens the detail page for [anime].
void openAnime(BuildContext context, Anime anime) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AnimeDetailScreen(id: anime.id, preview: anime)),
    );

/// Poster with a score badge. Decodes at display size to keep memory low.
class AnimePoster extends StatelessWidget {
  const AnimePoster({super.key, required this.anime, this.width = 120});

  /// The title shown.
  final Anime anime;

  /// Poster width; height follows the 2:3 poster ratio.
  final double width;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = Container(color: _hex(anime.color) ?? const Color(0xff1c2230));
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: width * 1.5,
          child: anime.cover == null
              ? placeholder
              : CachedNetworkImage(
                  imageUrl: anime.cover!,
                  fit: BoxFit.cover,
                  memCacheWidth: (width * dpr).round(),
                  placeholder: (_, __) => placeholder,
                  errorWidget: (_, __, ___) => placeholder,
                ),
        ),
      ),
      if (anime.score != null)
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .7), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, size: 13, color: Color(0xffffc857)),
              const SizedBox(width: 2),
              Text('${anime.score}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
    ]);
  }
}

/// Poster plus title; taps open the detail page.
class AnimeCard extends StatelessWidget {
  const AnimeCard({super.key, required this.anime, this.width = 120});

  /// The title shown.
  final Anime anime;

  /// Card width.
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openAnime(context, anime),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimePoster(anime: anime, width: width),
            const SizedBox(height: 6),
            Text(anime.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(anime.meta, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: .6))),
          ]),
        ),
      );
}

/// A horizontal row of posters for one AniList chart.
class AnimeShelf extends ConsumerWidget {
  const AnimeShelf({super.key, required this.title, required this.list, this.genre});

  /// Shelf heading.
  final String title;

  /// Chart name: trending, season, popular, top or upcoming.
  final String list;

  /// Optional genre filter.
  final String? genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(animeListProvider((list, genre)));
    final heading = list == 'season' && page.valueOrNull?.season != null ? '$title · ${page.value!.season}' : title;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Text(heading, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: 250,
        child: page.when(
          loading: () => ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => Container(
              width: 120,
              height: 180,
              margin: const EdgeInsets.only(bottom: 56),
              decoration: BoxDecoration(color: const Color(0xff1c2230), borderRadius: BorderRadius.circular(12)),
            ),
          ),
          error: (_, __) => Center(
            child: TextButton.icon(
              onPressed: () => ref.invalidate(animeListProvider((list, genre))),
              icon: const Icon(Icons.refresh),
              label: const Text('Could not load anime. Retry'),
            ),
          ),
          data: (p) => ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: p.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => AnimeCard(anime: p.items[i]),
          ),
        ),
      ),
    ]);
  }
}

/// The Anime category of Phlio Stream: genres, charts and search.
class AnimeBrowser extends ConsumerStatefulWidget {
  const AnimeBrowser({super.key, this.query = ''});

  /// Text from Stream's search box; 2+ characters searches AniList.
  final String query;

  @override
  ConsumerState<AnimeBrowser> createState() => _AnimeBrowserState();
}

class _AnimeBrowserState extends ConsumerState<AnimeBrowser> {
  String? genre;
  String query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    query = widget.query.trim();
  }

  @override
  void didUpdateWidget(AnimeBrowser old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      // Search after typing pauses, not on every keystroke.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => query = widget.query.trim());
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Widget _grid(AsyncValue<List<Anime>> results, VoidCallback retry) => results.when(
        loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
        error: (_, __) => Center(child: TextButton(onPressed: retry, child: const Text('Could not load anime. Retry'))),
        data: (items) => items.isEmpty
            ? const Padding(padding: EdgeInsets.all(32), child: Text('No anime found.'))
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140, childAspectRatio: 0.5, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: items.length,
                itemBuilder: (context, i) => LayoutBuilder(
                  builder: (_, box) => AnimeCard(anime: items[i], width: box.maxWidth),
                ),
              ),
      );

  Future<void> _refresh() async {
    for (final list in const ['trending', 'season', 'top', 'upcoming']) {
      ref.invalidate(animeListProvider((list, null)));
    }
    if (genre != null) ref.invalidate(animeListProvider(('popular', genre)));
    await ref.read(animeListProvider(('trending', null)).future).catchError((_) => const AnimePage([]));
  }

  @override
  Widget build(BuildContext context) {
    final genres = ref.watch(animeGenresProvider).valueOrNull ?? const <String>[];
    final searching = query.length >= 2;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (!searching && genres.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: genres.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final name = i == 0 ? null : genres[i - 1];
                  return FilterChip(
                    label: Text(name ?? 'All genres'),
                    selected: genre == name,
                    onSelected: (_) => setState(() => genre = name),
                  );
                },
              ),
            ),
          if (searching)
            _grid(ref.watch(animeSearchProvider(query)), () => ref.invalidate(animeSearchProvider(query)))
          else if (genre != null)
            _grid(ref.watch(animeListProvider(('popular', genre))).whenData((p) => p.items),
                () => ref.invalidate(animeListProvider(('popular', genre))))
          else ...const [
            AnimeShelf(title: 'Trending now', list: 'trending'),
            AnimeShelf(title: 'Popular this season', list: 'season'),
            AnimeShelf(title: 'Top rated', list: 'top'),
            AnimeShelf(title: 'Upcoming', list: 'upcoming'),
          ],
          const _AniListCredit(),
        ],
      ),
    );
  }
}

class _AniListCredit extends StatelessWidget {
  const _AniListCredit();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(
          'Anime listings from AniList. Trailers and episodes open on the official streaming services.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .5)),
        ),
      );
}

/// Detail page for one anime.
class AnimeDetailScreen extends ConsumerWidget {
  const AnimeDetailScreen({super.key, required this.id, this.preview});

  /// AniList id.
  final int id;

  /// The list card, shown while details load.
  final Anime? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(animeDetailProvider(id));
    final anime = details.valueOrNull ?? preview;
    final accent = _hex(anime?.color) ?? const Color(0xff8d78ff);
    return Scaffold(
      backgroundColor: Colors.black,
      body: anime == null
          ? Center(
              child: details.hasError
                  ? TextButton(onPressed: () => ref.invalidate(animeDetailProvider(id)), child: const Text('Retry'))
                  : const CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 220,
                backgroundColor: Colors.black,
                actions: [
                  IconButton(
                    tooltip: 'Open on AniList',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openExternal(context, anime.anilistUrl),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(fit: StackFit.expand, children: [
                    if ((anime.banner ?? anime.cover) != null)
                      CachedNetworkImage(imageUrl: (anime.banner ?? anime.cover)!, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.list(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    AnimePoster(anime: anime, width: 110),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(anime.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        if (anime.native != null)
                          Text(anime.native!, style: TextStyle(color: Colors.white.withValues(alpha: .6))),
                        const SizedBox(height: 6),
                        Text(
                          [anime.meta, if (anime.duration != null) '${anime.duration} min', ...anime.studios.take(1)]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: .75)),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final g in anime.genres)
                      Chip(label: Text(g), visualDensity: VisualDensity.compact, side: BorderSide(color: accent)),
                  ]),
                  if (anime.nextEpisode != null) ...[
                    const SizedBox(height: 12),
                    _NextEpisode(episode: anime.nextEpisode!.$1, at: anime.nextEpisode!.$2, color: accent),
                  ],
                  const SizedBox(height: 16),
                  if (details.isLoading)
                    const LinearProgressIndicator(minHeight: 2)
                  else if (details.hasError)
                    TextButton(
                        onPressed: () => ref.invalidate(animeDetailProvider(id)),
                        child: const Text('Could not load details. Retry'))
                  else
                    ..._details(context, anime, accent),
                  const _AniListCredit(),
                ]),
              ),
            ]),
    );
  }

  List<Widget> _details(BuildContext context, Anime anime, Color accent) {
    final trailer = anime.trailer;
    return [
      if (trailer != null) ...[
        _TrailerCard(trailer: trailer, onTap: () => _openExternal(context, '${trailer['url']}')),
        const SizedBox(height: 20),
      ],
      const Text('Where to watch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (anime.whereToWatch.isEmpty)
        Text('No official streaming service is listed for this title yet.',
            style: TextStyle(color: Colors.white.withValues(alpha: .6)))
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final link in anime.whereToWatch)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(side: BorderSide(color: _hex(link['color'] as String?) ?? accent)),
              onPressed: () => _openExternal(context, '${link['url']}'),
              icon: link['icon'] != null
                  ? CachedNetworkImage(imageUrl: '${link['icon']}', width: 18, height: 18,
                      errorWidget: (_, __, ___) => const Icon(Icons.play_circle_outline, size: 18))
                  : const Icon(Icons.play_circle_outline, size: 18),
              label: Text([link['site'], if (link['language'] != null) '(${link['language']})'].join(' ')),
            ),
        ]),
      if (anime.description.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('Synopsis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _Expandable(text: anime.description),
      ],
      if (anime.episodeLinks.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('Episodes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        for (final ep in anime.episodeLinks.take(50))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 54,
                child: ep['thumbnail'] == null
                    ? Container(color: const Color(0xff1c2230), child: const Icon(Icons.play_arrow))
                    : CachedNetworkImage(imageUrl: '${ep['thumbnail']}', fit: BoxFit.cover, memCacheWidth: 300),
              ),
            ),
            title: Text('${ep['title'] ?? 'Episode'}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('Watch on ${ep['site'] ?? 'official site'}'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openExternal(context, '${ep['url']}'),
          ),
      ],
      if (anime.recommendations.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('You might also like', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: anime.recommendations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => AnimeCard(anime: anime.recommendations[i]),
          ),
        ),
      ],
    ];
  }
}

class _TrailerCard extends StatelessWidget {
  const _TrailerCard({required this.trailer, required this.onTap});

  final Map<String, dynamic> trailer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              if (trailer['thumbnail'] != null)
                CachedNetworkImage(imageUrl: '${trailer['thumbnail']}', fit: BoxFit.cover)
              else
                Container(color: const Color(0xff1c2230)),
              Container(color: Colors.black.withValues(alpha: .35)),
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_circle_fill, size: 64),
                  Text('Watch trailer on ${trailer['site'] ?? 'YouTube'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _NextEpisode extends StatelessWidget {
  const _NextEpisode({required this.episode, required this.at, required this.color});

  final int episode;
  final DateTime at;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final left = at.difference(DateTime.now());
    final text = left.isNegative
        ? 'Episode $episode is out'
        : 'Episode $episode in ${left.inDays > 0 ? '${left.inDays}d ' : ''}${left.inHours % 24}h ${left.inMinutes % 60}m';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.schedule, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable({required this.text});

  final String text;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool open = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => open = !open),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.text,
              maxLines: open ? null : 5,
              overflow: open ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(height: 1.4, color: Colors.white.withValues(alpha: .85))),
          Text(open ? 'Show less' : 'Read more', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
