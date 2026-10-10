import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import 'social_videos_view.dart';

class SocialExploreVideosView extends ConsumerWidget {
  const SocialExploreVideosView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(socialVideoCatalogProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: TextButton(
                onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                child: const Text('Could not load videos. Retry'))),
        data: (videos) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(socialVideoCatalogProvider);
            await ref.read(socialVideoCatalogProvider.future);
          },
          child:
              ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Discover creators',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
            if (videos.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('New videos will appear here.')),
            for (final video in videos)
              SocialVideoCard(
                  video: socialVideoPresentation(video),
                  fallbackGradient: true,
                  showFollowPill: true,
                  onTap: () => ref.read(videoPlaybackProvider).open(video)),
          ]),
        ),
      );
}
