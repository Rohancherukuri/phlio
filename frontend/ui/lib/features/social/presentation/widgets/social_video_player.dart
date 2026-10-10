import '../../../../app/router/app_router.dart';
import '../../../../shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import '../../../../design_system/colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../controllers/video_playback_controller.dart';
import 'creator_follow_button.dart';

class SocialVideoPlayer extends ConsumerStatefulWidget {
  const SocialVideoPlayer({super.key});
  @override
  ConsumerState<SocialVideoPlayer> createState() => _SocialVideoPlayerState();
}

class _SocialVideoPlayerState extends ConsumerState<SocialVideoPlayer>
    with WidgetsBindingObserver {
  Offset offset = Offset.zero;
  bool settings = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(videoPlaybackProvider).player?.pause();
    }
  }

  String time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(videoPlaybackProvider);
    if (c.mode == SocialPlayerMode.hidden || c.video == null) {
      return const SizedBox.shrink();
    }
    final mini = c.mode == SocialPlayerMode.floating;
    final full = c.mode == SocialPlayerMode.fullscreen;
    final p = c.player;
    final ready = p?.value.isInitialized == true && c.error == null;
    Widget button(IconData icon, String label, VoidCallback action) =>
        IconButton(tooltip: label, onPressed: action, icon: Icon(icon));
    Future<void> shareVideo() async {
      final source = c.video!;
      final navigatorContext =
          ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
      if (navigatorContext == null || source.localPath != null) return;
      final wasPlaying = p?.value.isPlaying == true;
      await p?.pause();
      c.setMode(SocialPlayerMode.hidden);
      if (navigatorContext.mounted)
        await showContentShare(navigatorContext,
            '${source.platform}/${source.contentId ?? source.id}');
      if (mounted && c.video == source) {
        c.setMode(SocialPlayerMode.floating);
        if (wasPlaying) await p?.play();
      }
    }

    final picture = ColoredBox(
      color: Colors.black,
      child: Center(
        child: c.error != null
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => c.open(c.video!),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : !ready
                ? const CircularProgressIndicator()
                : ClipRect(
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: c.fill ? BoxFit.cover : BoxFit.contain,
                        child: SizedBox(
                          width: p!.value.size.width,
                          height: p.value.size.height,
                          child: VideoPlayer(p),
                        ),
                      ),
                    ),
                  ),
      ),
    );
    final controls = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!mini)
          button(
            Icons.replay_10,
            'Back 10 seconds',
            () => c.seek(
              (p?.value.position ?? Duration.zero) -
                  const Duration(seconds: 10),
            ),
          ),
        button(
          p?.value.isPlaying == true ? Icons.pause : Icons.play_arrow,
          'Play or pause',
          c.toggle,
        ),
        if (!mini)
          button(
            Icons.forward_10,
            'Forward 10 seconds',
            () => c.seek(
              (p?.value.position ?? Duration.zero) +
                  const Duration(seconds: 10),
            ),
          ),
        if (!mini)
          button(
            c.volume == 0 ? Icons.volume_off : Icons.volume_up,
            'Mute or unmute',
            () => c.setVolume(c.volume == 0 ? 1 : 0),
          ),
        if (!mini && c.video!.localPath == null)
          button(Icons.ios_share, 'Share video', shareVideo),
        if (!mini)
          button(
            Icons.settings,
            'Playback settings',
            () => setState(() => settings = !settings),
          ),
        button(
          full ? Icons.fullscreen_exit : Icons.fullscreen,
          full ? 'Exit fullscreen' : 'Fullscreen',
          () => c.setMode(
            full ? SocialPlayerMode.expanded : SocialPlayerMode.fullscreen,
          ),
        ),
        button(mini ? Icons.open_in_full : Icons.picture_in_picture_alt,
            mini ? 'Expand player' : 'Floating player', () {
          settings = false;
          c.setMode(
            mini ? SocialPlayerMode.expanded : SocialPlayerMode.floating,
          );
        }),
        if (mini) button(Icons.close, 'Close player', c.close),
      ],
    );
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final width =
              mini ? (bounds.maxWidth - 24).clamp(0.0, 360.0) : bounds.maxWidth;
          final height = mini ? width * 9 / 16 + 96 : bounds.maxHeight;
          final content = Material(
            color: PhlioColors.surface,
            borderRadius: BorderRadius.circular(mini ? 16 : 0),
            clipBehavior: Clip.antiAlias,
            elevation: 16,
            child: SafeArea(
              top: !mini,
              bottom: !mini,
              child: Column(
                children: [
                  if (!full)
                    GestureDetector(
                      onPanUpdate: mini
                          ? (d) => setState(() => offset += d.delta)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.video!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!mini)
                              button(
                                Icons.keyboard_arrow_down,
                                'Minimize player',
                                () => c.setMode(SocialPlayerMode.floating),
                              ),
                            if (!mini)
                              button(Icons.close, 'Close player', c.close),
                            if (mini)
                              const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.drag_handle),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                            onLongPress: shareVideo, child: picture),
                        if (ready && p!.value.isBuffering)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    ),
                  ),
                  if (!mini && ready)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          VideoProgressIndicator(
                            p!,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            colors: const VideoProgressColors(
                              playedColor: PhlioColors.brandPurple,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(time(p.value.position)),
                              Text(time(p.value.duration)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  controls,
                  if (!mini && !full && c.video!.creator.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '@${c.video!.creator}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          CreatorFollowButton(creator: c.video!.creator),
                        ],
                      ),
                    ),
                  if (settings && !mini)
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Playback speed'),
                              Wrap(
                                spacing: 8,
                                children: [
                                  .25,
                                  .5,
                                  .75,
                                  1.0,
                                  1.25,
                                  1.5,
                                  1.75,
                                  2.0,
                                ]
                                    .map(
                                      (s) => ChoiceChip(
                                        label: Text('${s}x'),
                                        selected: c.speed == s,
                                        onSelected: (_) => c.setSpeed(s),
                                      ),
                                    )
                                    .toList(),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.volume_up),
                                  Expanded(
                                    child: Slider(
                                      value: c.volume,
                                      onChanged: c.setVolume,
                                    ),
                                  ),
                                ],
                              ),
                              SwitchListTile(
                                title: const Text('Loop video'),
                                value: c.loop,
                                onChanged: c.setLoop,
                              ),
                              SwitchListTile(
                                title: const Text('Fill screen'),
                                value: c.fill,
                                onChanged: c.setFill,
                              ),
                              const Text('Original source quality'),
                              if (c.notice != null) Text(c.notice!),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
          if (!mini) return content;
          return Stack(
            children: [
              Positioned(
                left: (bounds.maxWidth - width - 12 + offset.dx)
                    .clamp(0.0, bounds.maxWidth - width),
                top: (bounds.maxHeight - height - 100 + offset.dy).clamp(
                  0.0,
                  (bounds.maxHeight - height).clamp(0.0, double.infinity),
                ),
                width: width,
                height: height,
                child: content,
              ),
            ],
          );
        },
      ),
    );
  }
}
