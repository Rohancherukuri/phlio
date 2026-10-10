import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/config/app_config.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import 'creator_follow_button.dart';

class SocialClipsView extends ConsumerWidget {
  const SocialClipsView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(socialVideoCatalogProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: TextButton(
                onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                child: const Text('Could not load clips. Retry'))),
        data: (videos) {
          final clips = videos.where((v) => v.kind == 'clip').toList();
          if (clips.isEmpty) return const Center(child: Text('No clips yet.'));
          return PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: clips.length,
              itemBuilder: (context, index) {
                final clip = clips[index];
                return GestureDetector(
                    onLongPress: () =>
                        showContentShare(context, 'social/${clip.id}'),
                    child: Stack(fit: StackFit.expand, children: [
                      if (clip.thumbnailUrl != null)
                        Image.network(AppConfig.mediaUrl(clip.thumbnailUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink()),
                      const DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                            Colors.transparent,
                            Colors.black87
                          ]))),
                      Center(
                          child: IconButton.filled(
                              iconSize: 52,
                              tooltip: 'Play clip',
                              onPressed: () =>
                                  ref.read(videoPlaybackProvider).open(clip),
                              icon: const Icon(Icons.play_arrow_rounded))),
                      Positioned(
                          left: 20,
                          right: 20,
                          bottom: 28,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: TextButton(
                                          onPressed: () => context
                                              .push('/creator/${clip.creator}'),
                                          child: Text('@${clip.creator}'))),
                                  CreatorFollowButton(creator: clip.creator)
                                ]),
                                EngagementRow(path: 'social/${clip.id}'),
                                Text(clip.title,
                                    style: const TextStyle(
                                        fontSize: 20, color: Colors.white)),
                              ])),
                    ]));
              });
        },
      );
}
