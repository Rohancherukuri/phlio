import 'video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../../shared/content/social_comments_sheet.dart';
import '../controllers/video_library.dart';
import 'creator_follow_button.dart';

class SocialClipsView extends ConsumerStatefulWidget {
  const SocialClipsView({super.key});
  @override
  ConsumerState<SocialClipsView> createState() => _SocialClipsViewState();
}

class _SocialClipsViewState extends ConsumerState<SocialClipsView> {
  int selected = 0;
  final _prefetched = <String>{};
  @override
  Widget build(BuildContext context) =>
      ref.watch(socialVideoCatalogProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                  child: const Text('Could not load clips. Retry'))),
          data: (videos) {
            final clips = videos.where((v) => v.kind == 'clip').toList();
            for (final clip in clips.skip(selected).take(3)) {
              final url = clip.thumbnailUrl;
              if (url != null && _prefetched.add(url)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted)
                    precacheImage(
                        NetworkImage(AppConfig.mediaUrl(url)), context,
                        onError: (_, __) {});
                });
              }
            }
            if (clips.isEmpty)
              return const Center(child: Text('No clips yet.'));
            return PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: clips.length,
                onPageChanged: (i) => setState(() => selected = i),
                itemBuilder: (_, i) => _Reel(
                    key: ValueKey(clips[i].id),
                    clip: clips[i],
                    active: i == selected));
          });
}

class _Reel extends ConsumerStatefulWidget {
  const _Reel({super.key, required this.clip, required this.active});
  final PlayableVideo clip;
  final bool active;
  @override
  ConsumerState<_Reel> createState() => _ReelState();
}

class _ReelState extends ConsumerState<_Reel> with WidgetsBindingObserver {
  VideoPlayerController? player;
  bool ready = false,
      failed = false,
      muted = true,
      paused = false,
      busy = false,
      foreground = true;
  String get path => 'social/${widget.clip.id}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(covariant _Reel old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  Future<void> sync() async {
    final play = widget.active && TickerMode.of(context) && foreground;
    if (!play) {
      await player?.pause();
      return;
    }
    if (player != null) {
      if (ready && !paused) await player!.play();
      return;
    }
    final p = VideoPlayerController.networkUrl(
        Uri.parse(AppConfig.mediaUrl(widget.clip.url)));
    player = p;
    try {
      await p.initialize();
      if (!mounted || player != p) return;
      await p.setLooping(true);
      await p.setVolume(muted ? 0 : 1);
      setState(() => ready = true);
      if (widget.active && TickerMode.of(context) && foreground && !paused)
        await p.play();
      if (getIt.isRegistered<ApiClient>()) {
        try {
          await getIt<ApiClient>().dio.put('/content/$path/actions/viewed');
          ref.invalidate(engagementProvider(path));
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    super.dispose();
  }

  Future<void> sheet(bool comments) async {
    await player?.pause();
    if (!mounted) return;
    if (comments)
      await showSocialComments(context, widget.clip.id);
    else
      await showContentShare(context, path);
    if (mounted) sync();
  }

  Future<void> action(String verb) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await getIt<ApiClient>()
          .dio
          .put('/content/$path/${verb == 'like' ? 'like' : 'actions/$verb'}');
      ref.invalidate(engagementProvider(path));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update. Try again.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(engagementProvider(path)).valueOrNull;
    Widget rail(IconData icon, String label, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(children: [
          IconButton(
              tooltip: label,
              onPressed: tap,
              icon: Icon(icon, color: Colors.white, size: 28)),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white))
        ]));
    return GestureDetector(
        onLongPress: () => sheet(false),
        onTap: () async {
          setState(() => paused = !paused);
          if (paused)
            await player?.pause();
          else
            sync();
        },
        child: ColoredBox(
            color: Colors.black,
            child: Stack(fit: StackFit.expand, children: [
              if (ready)
                FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                        width: player!.value.size.width,
                        height: player!.value.size.height,
                        child: VideoPlayer(player!)))
              else if (widget.clip.thumbnailUrl != null)
                VideoThumbnail(url: widget.clip.thumbnailUrl),
              const IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87])))),
              if (paused)
                const Center(
                    child: Icon(Icons.play_arrow_rounded,
                        size: 64, color: Colors.white70)),
              if (failed)
                Center(
                    child: TextButton(
                        onPressed: () async {
                          await player?.dispose();
                          player = null;
                          setState(() => failed = false);
                          sync();
                        },
                        child: const Text('Retry playback'))),
              Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                      tooltip: muted ? 'Unmute' : 'Mute',
                      onPressed: () {
                        setState(() => muted = !muted);
                        player?.setVolume(muted ? 0 : 1);
                      },
                      icon: Icon(
                          muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white))),
              Positioned(
                  right: 8,
                  bottom: 120,
                  child: Column(children: [
                    rail(
                        data?['liked_by_me'] == true
                            ? Icons.favorite
                            : Icons.favorite_border,
                        formatEngagementCount(data?['count'] as num? ?? 0),
                        () => action('like')),
                    rail(Icons.chat_bubble_outline_rounded, 'Comments',
                        () => sheet(true)),
                    rail(Icons.send_outlined, 'Share', () => sheet(false)),
                    rail(
                        data?['saved_by_me'] == true
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        'Save',
                        () => action('saved')),
                  ])),
              Positioned(
                  left: 16,
                  right: 80,
                  bottom: 22,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Expanded(
                              child: InkWell(
                                  onTap: () => context
                                      .push('/creator/${widget.clip.creator}'),
                                  child: Text('@${widget.clip.creator}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)))),
                          CreatorFollowButton(creator: widget.clip.creator)
                        ]),
                        const SizedBox(height: 8),
                        Text(widget.clip.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.4)),
                        const SizedBox(height: 6),
                        Text(
                            '${formatEngagementCount(data?['views_count'] as num? ?? 0)} views',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        if (widget.clip.attribution != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(widget.clip.attribution!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white60))),
                      ])),
            ])));
  }
}
