import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../content/content_surface.dart';

final newsFeedProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, filter) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final parts = filter.split('\n');
  return (await getIt<ApiClient>().dio.get('/news/feed', queryParameters: {
    'category': parts.first,
    'q': parts.length > 1 ? parts.sublist(1).join('\n') : '',
  }))
      .data as Map;
});

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key, this.explore = false});
  final bool explore;
  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  String category = 'Top International', query = '';
  @override
  Widget build(BuildContext context) {
    final filter = '$category\n$query';
    final feed = ref.watch(newsFeedProvider(filter));
    return SafeArea(
        child: RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(newsFeedProvider(filter));
        await ref.read(newsFeedProvider(filter).future);
      },
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Text(
                MaterialLocalizations.of(context)
                    .formatMediumDate(DateTime.now()),
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(widget.explore ? 'Discover' : 'Phlio News',
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1)),
            const SizedBox(height: 24),
            if (widget.explore) ...[
              TextField(
                  onSubmitted: (v) => setState(() => query = v.trim()),
                  decoration: InputDecoration(
                      hintText: 'Search news, topics or article URLs',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)))),
              const SizedBox(height: 16),
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                          'Explore reporting from publishers around the world. Search headlines, topics, keywords and article links.'))),
            ],
            feed.when(
                loading: () => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator())),
                error: (e, st) => Column(children: [
                      const Text('News could not be loaded.'),
                      TextButton(
                          onPressed: () =>
                              ref.invalidate(newsFeedProvider(filter)),
                          child: const Text('Try again'))
                    ]),
                data: (data) {
                  final items = data['items'] as List;
                  final headlines = data['headlines'] as List;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.explore) ...[
                          const SizedBox(height: 20),
                          const Text('Suggested topics',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                          Wrap(spacing: 8, children: [
                            for (final topic in data['topics'] as List)
                              ActionChip(
                                  label: Text(
                                      '${topic['name']} · ${topic['count']}'),
                                  onPressed: () => setState(() {
                                        category = topic['name'] as String;
                                        query = '';
                                      }))
                          ]),
                          const SizedBox(height: 20),
                          Text(query.isEmpty ? category : 'Search results',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                        ] else ...[
                          SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                for (final name in data['categories'] as List)
                                  Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                          label: Text(name as String),
                                          selected: category == name,
                                          onSelected: (_) =>
                                              setState(() => category = name))),
                              ])),
                          const SizedBox(height: 20),
                          const Text('Headlines',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          if (headlines.isNotEmpty)
                            SizedBox(
                                height: 170,
                                child: PageView(children: [
                                  for (final article in headlines)
                                    Card(
                                        color: const Color(0xFF202A3A),
                                        child: InkWell(
                                            onTap: () => openArticle(article),
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(16),
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                          article['publisher']
                                                              as String,
                                                          style: const TextStyle(
                                                              color: Color(
                                                                  0xFFFFB58F))),
                                                      const SizedBox(height: 8),
                                                      Expanded(
                                                          child: Text(
                                                              article['title']
                                                                  as String,
                                                              maxLines: 4,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                  fontSize: 20,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700))),
                                                    ])))),
                                ])),
                        ],
                        if (data['notice'] != null)
                          Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(data['notice'] as String)),
                        if (items.isEmpty && data['notice'] == null)
                          const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                  'No matching stories yet. Pull to refresh.')),
                        for (final article in items)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: ContentSurface(
                                          platform: 'news',
                                          contentId: article['ref'] as String,
                                          child: InkWell(
                                              onTap: () => openArticle(article),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                        '${article['category']} · ${article['publisher']}',
                                                        style: const TextStyle(
                                                            color: Color(
                                                                0xFFC4C8D2))),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Expanded(
                                                              child: Text(
                                                                  article['title']
                                                                      as String,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          20,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold))),
                                                          if (article['image_url'] !=
                                                              null)
                                                            Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        left:
                                                                            12),
                                                                child: ClipRRect(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            12),
                                                                    child: Image.network(
                                                                        article['image_url']
                                                                            as String,
                                                                        width:
                                                                            76,
                                                                        height:
                                                                            76,
                                                                        fit: BoxFit
                                                                            .cover,
                                                                        errorBuilder: (_,
                                                                                __,
                                                                                ___) =>
                                                                            const SizedBox.shrink()))),
                                                        ]),
                                                    const SizedBox(height: 12),
                                                    Text(
                                                        '${article['published_at'].toString().split('T').first} · Read at source ↗',
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            color: Color(
                                                                0xFF858D9E))),
                                                    const SizedBox(height: 8),
                                                  ]))))))
                      ]);
                }),
          ]),
    ));
  }

  Future<void> openArticle(Map article) async {
    try {
      await getIt<ApiClient>()
          .dio
          .put('/content/news/${article['ref']}/actions/viewed');
      ref.invalidate(engagementProvider('news/${article['ref']}'));
      await launchUrl(Uri.parse(article['source_url'] as String),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open this story. Please try again.')));
    }
  }
}
