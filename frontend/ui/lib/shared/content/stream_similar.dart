// Phlio Stream · "More like this" for movies, series and anime, and search by
// story ("robots in a future city").
//
// Backed by `/api/v1/stream/similar/titles*` (backend/app/api/v1/similar.py):
// a TF-IDF similarity search over each title's synopsis, genres, studio /
// director and category. Items come back in the same shape as the Stream
// catalogue, so they open in ContentDetailScreen like any other title.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import 'content_surface.dart' show ContentDetailScreen;

Future<List<Map<String, dynamic>>> _items(String path, [Map<String, dynamic>? query]) async {
  final res = await getIt<ApiClient>().dio.get<dynamic>(path, queryParameters: query);
  return [for (final i in ((res.data as Map)['items'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
}

/// Titles similar to one catalogue title (by its ref).
final similarTitlesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
    (ref, titleRef) => _items('/stream/similar/titles/${Uri.encodeComponent(titleRef)}'));

/// Titles whose story matches a description.
final storySearchProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
    (ref, q) => _items('/stream/similar/titles', {'q': q}));

void _openTitle(BuildContext context, Map item) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ContentDetailScreen(path: 'stream/${item['ref']}')));

/// A poster card with the reason it matched.
class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final image = item['image_url'] as String?;
    final because = [for (final w in (item['because'] as List? ?? const [])) '$w'];
    final placeholder = Container(color: const Color(0xff1c2230), child: const Icon(Icons.movie_outlined));
    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTitle(context, item),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 130,
              height: 180,
              child: image == null
                  ? placeholder
                  : CachedNetworkImage(
                      imageUrl: AppConfig.mediaUrl(image),
                      fit: BoxFit.cover,
                      memCacheWidth: (130 * MediaQuery.devicePixelRatioOf(context)).round(),
                      errorWidget: (_, __, ___) => placeholder,
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text('${item['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (because.isNotEmpty)
            Text(because.take(3).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: .6))),
        ]),
      ),
    );
  }
}

/// "More like this" shelf for a title's detail page. Hidden when empty.
class MoreLikeThis extends ConsumerWidget {
  const MoreLikeThis({required this.titleRef, super.key});

  /// The catalogue ref of the title being viewed.
  final String titleRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(similarTitlesProvider(titleRef)).valueOrNull ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      Text('More like this', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      SizedBox(
        height: 250,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => _SimilarCard(item: items[i]),
        ),
      ),
    ]);
  }
}

/// "Matching stories" for the Stream search box: titles whose synopsis fits
/// the words typed, not just the title. Searches after typing pauses.
class StorySearchResults extends ConsumerStatefulWidget {
  const StorySearchResults({required this.query, super.key});

  /// Text in Stream's search box.
  final String query;

  @override
  ConsumerState<StorySearchResults> createState() => _StorySearchResultsState();
}

class _StorySearchResultsState extends ConsumerState<StorySearchResults> {
  late String _query = widget.query;
  Timer? _debounce;

  @override
  void didUpdateWidget(StorySearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _query = widget.query);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(storySearchProvider(_query)).valueOrNull ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        child: Text('Matching stories', style: Theme.of(context).textTheme.titleMedium),
      ),
      SizedBox(
        height: 250,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => _SimilarCard(item: items[i]),
        ),
      ),
    ]);
  }
}
