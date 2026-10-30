import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Rich provider metadata, separate from playback rights and Phlio engagement.
class StreamTitleDetails extends StatelessWidget {
  const StreamTitleDetails({super.key, required this.item});
  final Map item;

  Future<void> _open(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open this link. Please try again.')));
  }

  @override
  Widget build(BuildContext context) {
    final genres = (item['genres'] as List?) ?? const [];
    final cast = (item['cast'] as List?) ?? const [];
    final episodes = (item['episodes'] as List?) ?? const [];
    final links = (item['watch_links'] as List?) ?? const [];
    final info = <String, dynamic>{
      'Released': item['released']?.toString().split('T').first,
      'Status': item['status'],
      'Language': item['language'],
      'Duration':
          item['runtime'] != null ? '${item['runtime']} min' : item['duration'],
      'Rating': item['rating'] != null
          ? '${item['rating']} / 10 · ${item['publisher']}'
          : null,
      'Content rating': item['age_rating'],
      'Episodes': item['episode_count'],
      'Director': item['director'],
      'Studio': item['studio'],
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      if (genres.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final genre in genres) Chip(label: Text('$genre')),
        ]),
      for (final entry in info.entries)
        if (entry.value != null && entry.value.toString().isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${entry.key}: ${entry.value}')),
      if (item['details_unavailable'] == true)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
                'Showing saved details. More information is temporarily unavailable.')),
      if (cast.isNotEmpty)
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Cast'),
            children: [
              for (final person in cast)
                ListTile(
                    dense: true,
                    title: Text('${person['name']}'),
                    subtitle: Text('${person['role'] ?? ''}')),
            ]),
      if (episodes.isNotEmpty) _EpisodeList(episodes: episodes),
      if ((item['media_url'] as String?)?.isNotEmpty != true &&
          item['provider'] != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(links.isEmpty
                ? 'Full episodes are not hosted in Phlio. Check the source page for viewing information.'
                : 'Watch through the official links below when available. Provider subscriptions and regional availability may apply.')),
      for (final source in links)
        if (source['url'] is String)
          OutlinedButton.icon(
              onPressed: () => _open(context, source['url'] as String),
              icon: const Icon(Icons.open_in_new),
              label: Text('${source['name']}')),
      if (item['trailer_url'] is String)
        TextButton.icon(
            onPressed: () => _open(context, item['trailer_url'] as String),
            icon: const Icon(Icons.movie_outlined),
            label: const Text('Watch trailer')),
      if (item['attribution'] != null)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('${item['attribution']}',
                style: Theme.of(context).textTheme.bodySmall)),
      if (item['license_url'] is String)
        TextButton(
            onPressed: () => _open(context, item['license_url'] as String),
            child: const Text('Content license')),
    ]);
  }
}

class _EpisodeList extends StatefulWidget {
  const _EpisodeList({required this.episodes});
  final List episodes;
  @override
  State<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<_EpisodeList> {
  int count = 20;
  @override
  Widget build(BuildContext context) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Episodes (${widget.episodes.length})'),
          children: [
            for (final episode in widget.episodes.take(count))
              ListTile(
                title: Text(
                    'S${episode['season']} · E${episode['number']}  ${episode['title']}'),
                subtitle: Text(
                    '${episode['released'] ?? ''}\n${episode['description'] ?? ''}'),
              ),
            if (count < widget.episodes.length)
              TextButton(
                  onPressed: () => setState(() => count += 20),
                  child: const Text('Show more episodes')),
          ]);
}
