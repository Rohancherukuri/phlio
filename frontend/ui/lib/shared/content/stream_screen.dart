import 'package:phlio/shared/widgets/notifications_button.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/config/app_config.dart';
import '../../features/social/presentation/controllers/video_library.dart';
import '../../features/social/presentation/controllers/video_playback_controller.dart';
import 'content_surface.dart';

String streamCategory(Map item) {
  final kind = '${item['kind'] ?? ''} ${item['category'] ?? ''}'.toLowerCase();
  if (kind.contains('podcast')) return 'Podcasts';
  if (kind.contains('music') ||
      kind.contains('song') ||
      kind.trim() == 'audio') {
    return 'Music';
  }
  if (kind.contains('reality')) return 'Reality Shows';
  if (kind.contains('series') ||
      kind.contains('episode') ||
      kind.trim() == 'tv') {
    return 'TV Series';
  }
  return 'Movies';
}

// Shared by Home and Explore so the chosen experience follows navigation.
final streamAudioModeProvider = StateProvider<bool>((ref) => false);

class StreamScreen extends ConsumerStatefulWidget {
  const StreamScreen({super.key, this.explore = false, this.initialItem});
  final bool explore;
  final Map? initialItem;
  @override
  ConsumerState<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends ConsumerState<StreamScreen> {
  AudioPlayer? _player;
  AudioPlayer get player {
    if (_player == null) {
      _player = AudioPlayer();
      listenToPlayer();
    }
    return _player!;
  }

  final search = TextEditingController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  String category = 'All';
  Map? playing;
  bool paused = true, loading = false;
  Duration position = Duration.zero, duration = Duration.zero;
  int request = 0;
  bool get audioMode => ref.read(streamAudioModeProvider);
  List<String> get categories => audioMode
      ? const ['All', 'Music', 'Podcasts']
      : const ['All', 'Movies', 'TV Series', 'Reality Shows'];
  @override
  void initState() {
    super.initState();
    if (widget.initialItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(streamAudioModeProvider.notifier).state = true;
        open(widget.initialItem!);
      });
    }
  }

  void listenToPlayer() {
    subscriptions.add(
      player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => paused = state != PlayerState.playing);
      }),
    );
    subscriptions.add(
      player.onPositionChanged.listen((value) {
        if (mounted) setState(() => position = value);
      }),
    );
    subscriptions.add(
      player.onDurationChanged.listen((value) {
        if (mounted) setState(() => duration = value);
      }),
    );
  }

  @override
  void dispose() {
    request++;
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> open(Map item) async {
    trackContentView(context, 'stream/${item['ref']}');
    final url = item['media_url'] as String?;
    if (url == null || url.isEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ContentDetailScreen(path: 'stream/${item['ref']}'),
        ),
      );
      return;
    }
    final audio = ['Music', 'Podcasts'].contains(streamCategory(item));
    if (!audio) {
      await _player?.pause();
      if (!mounted) return;
      ref.read(videoPlaybackProvider).open(
            PlayableVideo(
              id: item['ref'] as String,
              title: item['title'] as String,
              creator: item['publisher'] as String? ?? '',
              url: url,
              platform: 'stream',
              thumbnailUrl: item['image_url'] as String?,
            ),
          );
      return;
    }
    if (loading) return;
    ref.read(videoPlaybackProvider).close();
    final current = ++request;
    setState(() {
      playing = item;
      loading = true;
      position = Duration.zero;
      duration = Duration.zero;
    });
    try {
      await player.play(UrlSource(AppConfig.mediaUrl(url)));
    } catch (_) {
      if (mounted && current == request) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio could not be played. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  Widget artwork(Map item, {double? width, double? height}) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          AppConfig.mediaUrl(item['image_url'] as String? ?? ''),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
            width: width,
            height: height,
            child: const ColoredBox(
              color: Color(0xff252630),
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
  Widget shelf(String title, List<Map> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final audio = ['Music', 'Podcasts'].contains(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: audio ? 335 : 400,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, index) {
              final item = items[index];
              return SizedBox(
                width: audio ? 156 : 145,
                child: InkWell(
                  onTap: () => open(item),
                  onLongPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ContentDetailScreen(
                        path: 'stream/${item['ref']}',
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      artwork(
                        item,
                        width: audio ? 156 : 145,
                        height: audio ? 156 : 215,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item['title'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      EngagementRow(
                          path: 'stream/${item['ref']}', compact: true),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioMode = ref.watch(streamAudioModeProvider);
    ref.listen<bool>(streamAudioModeProvider, (_, audio) {
      if (!audio) _player?.pause();
    });
    if (!categories.contains(category)) category = 'All';
    return Scaffold(
      backgroundColor: audioMode ? const Color(0xff121212) : Colors.black,
      appBar: AppBar(
        title: const Text('Phlio Stream'),
        actions: [
          const PhlioNotificationsButton(),
          IconButton(
            tooltip: audioMode
                ? 'Switch to movies and shows'
                : 'Switch to music and podcasts',
            icon: Icon(
                audioMode ? Icons.movie_outlined : Icons.headphones_outlined),
            onPressed: () {
              FocusScope.of(context).unfocus();
              search.clear();
              category = 'All';
              ref.read(streamAudioModeProvider.notifier).state = !audioMode;
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: audioMode
                    ? 'Songs, artists and podcasts'
                    : 'Movies, TV series and reality shows',
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) => ChoiceChip(
                label: Text(categories[index]),
                selected: category == categories[index],
                onSelected: (_) => setState(() => category = categories[index]),
              ),
            ),
          ),
          Expanded(
            child: ref.watch(catalogProvider('stream')).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.invalidate(catalogProvider('stream')),
                      child: const Text('Could not load Stream. Retry'),
                    ),
                  ),
                  data: (rows) {
                    final items = rows
                        .cast<Map>()
                        .where(
                          (item) =>
                              (['Music', 'Podcasts']
                                      .contains(streamCategory(item)) ==
                                  audioMode) &&
                              (category == 'All' ||
                                  streamCategory(item) == category) &&
                              '${item['title']} ${item['publisher'] ?? ''}'
                                  .toLowerCase()
                                  .contains(search.text.trim().toLowerCase()),
                        )
                        .toList();
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(catalogProvider('stream'));
                        await ref.read(catalogProvider('stream').future);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No titles available in this category yet.',
                              ),
                            ),
                          if (widget.explore || search.text.trim().isNotEmpty)
                            for (final item in items)
                              Column(children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                  leading: artwork(
                                    item,
                                    width: 88,
                                    height: 60,
                                  ),
                                  title: Text(item['title'] as String),
                                  subtitle: Text(streamCategory(item)),
                                  trailing: const Icon(
                                    Icons.play_circle_outline,
                                  ),
                                  onTap: () => open(item),
                                ),
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    child: EngagementRow(
                                        path: 'stream/${item['ref']}',
                                        compact: true))
                              ])
                          else ...[
                            if (items.isNotEmpty && !audioMode)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  20,
                                  20,
                                  0,
                                ),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: artwork(items.first),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(
                                          16,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              items.first['title'] as String,
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(
                                              height: 8,
                                            ),
                                            Text(
                                              items.first['description']
                                                      as String? ??
                                                  '',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(
                                              height: 12,
                                            ),
                                            FilledButton.icon(
                                              onPressed: () => open(
                                                items.first,
                                              ),
                                              icon: const Icon(
                                                Icons.play_arrow,
                                              ),
                                              label: Text(
                                                (items.first['media_url']
                                                                as String?)
                                                            ?.isNotEmpty ==
                                                        true
                                                    ? 'Play'
                                                    : 'View details',
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            EngagementRow(
                                                path:
                                                    'stream/${items.first['ref']}'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            for (final name in categories.skip(1))
                              shelf(
                                name,
                                items
                                    .where(
                                      (item) => streamCategory(item) == name,
                                    )
                                    .toList(),
                              ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
          ),
          if (playing != null && audioMode)
            Material(
              color: const Color(0xff302650),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: artwork(playing!, width: 44, height: 44),
                    title: Text(
                      playing!['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      playing!['publisher'] as String? ??
                          streamCategory(playing!),
                    ),
                    trailing: loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(),
                          )
                        : IconButton(
                            tooltip: paused ? 'Resume' : 'Pause',
                            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                            onPressed: () async {
                              if (paused) {
                                await player.resume();
                              } else {
                                await player.pause();
                              }
                            },
                          ),
                  ),
                  EngagementRow(
                      path: 'stream/${playing!['ref']}', compact: true),
                  Slider(
                    value: position.inMilliseconds
                        .toDouble()
                        .clamp(0, duration.inMilliseconds.toDouble()),
                    max: duration.inMilliseconds > 0
                        ? duration.inMilliseconds.toDouble()
                        : 1,
                    onChanged: duration == Duration.zero
                        ? null
                        : (value) =>
                            player.seek(Duration(milliseconds: value.toInt())),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
