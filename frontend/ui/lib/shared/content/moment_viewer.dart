import 'memory_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../app/config/app_config.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';
import 'content_surface.dart';

class MomentViewer extends ConsumerStatefulWidget {
  const MomentViewer({super.key, required this.authorId});
  final String authorId;
  @override
  ConsumerState<MomentViewer> createState() => _MomentViewerState();
}

class _MomentViewerState extends ConsumerState<MomentViewer> {
  int selected = 0;
  final pages = PageController();
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
            child: ref.watch(sharedStoriesProvider).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => Center(
                      child: TextButton(
                          onPressed: () =>
                              ref.invalidate(sharedStoriesProvider),
                          child: const Text('Retry moments'))),
                  data: (all) {
                    final stories = all
                        .where((s) =>
                            s['author']['id'] == widget.authorId &&
                            DateTime.parse(s['expires_at'] as String)
                                .isAfter(DateTime.now()))
                        .toList();
                    if (stories.isEmpty)
                      return Center(
                          child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                  'This moment has expired. Go back')));
                    final author = stories.first['author'] as Map;
                    return Column(children: [
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(children: [
                            for (var i = 0; i < stories.length; i++)
                              Expanded(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: LinearProgressIndicator(
                                          value: i <= selected ? 1 : 0,
                                          minHeight: 3)))
                          ])),
                      ListTile(
                          leading: ContentAuthorAvatar(
                              author: widget.authorId,
                              name: author['display_name'] as String,
                              imageUrl: author['avatar_url'] as String?,
                              size: 40),
                          title: Text(author['display_name'] as String,
                              style: const TextStyle(color: Colors.white)),
                          trailing: IconButton(
                              tooltip: 'Close moments',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close,
                                  color: Colors.white))),
                      Expanded(
                          child: PageView.builder(
                              controller: pages,
                              itemCount: stories.length,
                              onPageChanged: (i) =>
                                  setState(() => selected = i),
                              itemBuilder: (_, i) => _MomentMedia(
                                  key: ValueKey(stories[i]['id']),
                                  item: stories[i]['content'] as Map,
                                  active: i == selected))),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                                onPressed: selected > 0
                                    ? () => pages.previousPage(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        curve: Curves.easeOut)
                                    : null,
                                child: const Text('Previous')),
                            Text('${selected + 1} / ${stories.length}',
                                style: const TextStyle(color: Colors.white70)),
                            TextButton(
                                onPressed: () => selected + 1 < stories.length
                                    ? pages.nextPage(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        curve: Curves.easeOut)
                                    : Navigator.pop(context),
                                child: Text(selected + 1 < stories.length
                                    ? 'Next'
                                    : 'Done')),
                          ]),
                    ]);
                  },
                )),
      );
}

class _MomentMedia extends StatefulWidget {
  const _MomentMedia({super.key, required this.item, required this.active});
  final Map item;
  final bool active;
  @override
  State<_MomentMedia> createState() => _MomentMediaState();
}

class _MomentMediaState extends State<_MomentMedia>
    with WidgetsBindingObserver {
  VideoPlayerController? player;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    final url = widget.item['media_url'] as String?;
    if (url == null || url.isEmpty) return;
    final p =
        VideoPlayerController.networkUrl(Uri.parse(AppConfig.mediaUrl(url)));
    player = p;
    try {
      await p.initialize();
      if (!mounted) return;
      setState(() {});
      await p.setLooping(true);
      if (widget.active) await p.play();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _MomentMedia old) {
    super.didUpdateWidget(old);
    if (widget.active) {
      player?.play();
    } else {
      player?.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      player?.pause();
    } else if (widget.active) {
      player?.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: Center(
                child: failed
                    ? const Text('Could not play this moment',
                        style: TextStyle(color: Colors.white))
                    : player != null
                        ? player!.value.isInitialized
                            ? GestureDetector(
                                onTap: () => player!.value.isPlaying
                                    ? player!.pause()
                                    : player!.play(),
                                child: AspectRatio(
                                    aspectRatio: player!.value.aspectRatio,
                                    child: VideoPlayer(player!)))
                            : const CircularProgressIndicator()
                        : widget.item['image_url'] != null
                            ? MemoryPhoto(widget.item['image_url'] as String, fit: BoxFit.contain, isVideo: widget.item['media_kind']=='video')
                            : const SizedBox.shrink())),
        Padding(
            padding: const EdgeInsets.all(20),
            child: Text(widget.item['title'] as String? ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 17))),
      ]);
}
