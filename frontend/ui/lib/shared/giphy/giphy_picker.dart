import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

const giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');
Future<String> resolveGiphyKey() async {
  if (giphyApiKey.isNotEmpty) return giphyApiKey;
  if (!getIt.isRegistered<ApiClient>()) return '';
  final data =
      (await getIt<ApiClient>().dio.get('/messaging/giphy/config')).data as Map;
  return data['api_key'] as String? ?? '';
}

final _giphy = Dio(BaseOptions(
    baseUrl: 'https://api.giphy.com/v1',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15)));

class GiphyItem {
  const GiphyItem(this.id, this.kind, this.title, this.url);
  final String id, kind, title, url;
  String get reference => 'giphy:$kind:$id';
  factory GiphyItem.from(Map m, String kind) => GiphyItem(
      m['id'] as String,
      kind,
      m['title'] as String? ?? 'GIPHY',
      ((m['images'] as Map)['fixed_width'] as Map)['url'] as String);
}

Future<GiphyItem?> showGiphyPicker(BuildContext context,
        {String kind = 'gif'}) =>
    showModalBottomSheet<GiphyItem>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (_) => GiphyPicker(initialKind: kind));

class GiphyPicker extends StatefulWidget {
  const GiphyPicker({super.key, this.initialKind = 'gif', this.onSelected});
  final ValueChanged<GiphyItem>? onSelected;
  final String initialKind;
  @override
  State<GiphyPicker> createState() => _PickerState();
}

class _PickerState extends State<GiphyPicker> {
  late String kind;
  String query = '', mode = 'Trending', error = '';
  List<GiphyItem> items = [];
  bool loading = false, more = true, saving = false;
  int generation = 0, offset = 0;
  Timer? debounce;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    kind = widget.initialKind;
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    generation++;
    super.dispose();
  }

  Future<void> load({bool append = false}) async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = '';
      if (!append) {
        items = [];
        offset = 0;
      }
    });
    try {
      final apiKey = await resolveGiphyKey();
      if (!mounted || ticket != generation) return;
      if (apiKey.isEmpty) {
        setState(() => error = 'GIPHY is not configured yet.');
        return;
      }
      List data;
      if (mode == 'Recents') {
        final saved = (await getIt<ApiClient>().dio.get(
                '/messaging/giphy/recents',
                queryParameters: {'kind': kind}))
            .data as List;
        if (saved.isEmpty) {
          data = [];
        } else {
          data = ((await _giphy.get('/gifs', queryParameters: {
            'api_key': apiKey,
            'ids': saved.map((e) => e['giphy_id']).join(',')
          }))
              .data as Map)['data'] as List;
        }
      } else {
        final term =
            query.isNotEmpty ? query : (mode == 'Trending' ? '' : mode);
        data = ((await _giphy.get(
                '/${kind == 'gif' ? 'gifs' : 'stickers'}/${term.isEmpty ? 'trending' : 'search'}',
                queryParameters: {
              'api_key': apiKey,
              'limit': 24,
              'offset': offset,
              'rating': 'pg-13',
              if (term.isNotEmpty) 'q': term
            }))
            .data as Map)['data'] as List;
      }
      if (!mounted || ticket != generation) return;
      setState(() {
        items.addAll(data.map((e) => GiphyItem.from(e as Map, kind)));
        offset += data.length;
        more = mode != 'Recents' && data.length == 24;
      });
    } catch (_) {
      if (mounted && ticket == generation)
        setState(() => error = 'Could not load GIPHY. Try again.');
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> select(GiphyItem item) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await getIt<ApiClient>().dio.post('/messaging/giphy/recents',
          data: {'giphy_id': item.id, 'kind': item.kind});
      if (mounted) {
        if (widget.onSelected != null) {
          widget.onSelected!(item);
        } else {
          Navigator.pop(context, item);
        }
      }
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not save selection. Try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SizedBox(
          height: widget.onSelected != null
              ? double.infinity
              : MediaQuery.sizeOf(context).height *
                  (MediaQuery.viewInsetsOf(context).bottom > 0 ? .95 : .7),
          child: Padding(
              padding: EdgeInsets.only(
                  bottom: widget.onSelected != null
                      ? 0
                      : MediaQuery.viewInsetsOf(context).bottom),
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                        controller: search,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: kind == 'gif'
                                ? 'Search GIPHY'
                                : 'Search GIPHY stickers'),
                        onChanged: (value) {
                          debounce?.cancel();
                          query = value.trim();
                          mode = 'Trending';
                          debounce = Timer(
                              const Duration(milliseconds: 400), () => load());
                        })),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      for (final category in <(String, IconData)>[
                        ('Recents', Icons.history),
                        ('Trending', Icons.trending_up),
                        ('Happy', Icons.sentiment_satisfied_alt),
                        ('Love', Icons.favorite_border),
                        ('Sad', Icons.sentiment_dissatisfied),
                        ('Celebrate', Icons.celebration_outlined),
                      ])
                        Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: mode == category.$1
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                            : Colors.transparent,
                                        width: 2))),
                            child: IconButton(
                                tooltip: category.$1,
                                isSelected: mode == category.$1,
                                icon: Icon(category.$2, size: 22),
                                onPressed: () {
                                  debounce?.cancel();
                                  setState(() {
                                    mode = category.$1;
                                    query = '';
                                    search.clear();
                                  });
                                  load();
                                })),
                    ])),
                if (loading || saving) const LinearProgressIndicator(),
                if (error.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextButton(
                          onPressed: () => load(), child: Text(error))),
                Expanded(
                    child: items.isEmpty && !loading && error.isEmpty
                        ? const Center(child: Text('No results yet'))
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: items.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: kind == 'gif' ? 2 : 3,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8),
                            itemBuilder: (_, i) => InkWell(
                                onTap: saving ? null : () => select(items[i]),
                                child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(items[i].url,
                                        fit: kind == 'gif'
                                            ? BoxFit.cover
                                            : BoxFit.contain,
                                        semanticLabel: items[i].title,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons
                                                .broken_image_outlined)))))),
                if (more && items.isNotEmpty)
                  TextButton(
                      onPressed: loading ? null : () => load(append: true),
                      child: const Text('Load more')),
                const Text('Powered by GIPHY',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final value in ['sticker', 'gif'])
                        TextButton.icon(
                            onPressed: () {
                              debounce?.cancel();
                              setState(() {
                                kind = value;
                              });
                              load();
                            },
                            icon: Icon(value == 'gif'
                                ? Icons.gif_box_outlined
                                : Icons.sticky_note_2_outlined),
                            label: Text(value == 'gif' ? 'GIFs' : 'Stickers',
                                style: TextStyle(
                                    fontWeight: kind == value
                                        ? FontWeight.bold
                                        : FontWeight.normal))),
                    ]),
              ]))));
}

class GiphyReferenceView extends StatefulWidget {
  const GiphyReferenceView({required this.reference, super.key});
  final String reference;
  @override
  State<GiphyReferenceView> createState() => _ReferenceState();
}

class _ReferenceState extends State<GiphyReferenceView> {
  late Future<String> url;
  @override
  void initState() {
    super.initState();
    url = resolve();
  }

  @override
  void didUpdateWidget(covariant GiphyReferenceView old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) url = resolve();
  }

  Future<String> resolve() async {
    final apiKey = await resolveGiphyKey();
    if (apiKey.isEmpty) throw StateError('Not configured');
    final id = widget.reference.split(':').last;
    final data =
        (await _giphy.get('/gifs/$id', queryParameters: {'api_key': apiKey}))
            .data as Map;
    return GiphyItem.from(data['data'] as Map, 'gif').url;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
      future: url,
      builder: (_, state) => state.hasError
          ? const Center(child: Text('GIPHY unavailable'))
          : state.hasData
              ? Image.network(state.data!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined))
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)));
}
