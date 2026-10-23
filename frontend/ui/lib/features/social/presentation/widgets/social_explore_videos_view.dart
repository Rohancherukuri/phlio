import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../domain/entities/post_entity.dart';
import '../controllers/feed_controller.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import 'social_clips_grid.dart';
import 'social_explore_posts_view.dart';
import 'social_videos_view.dart';

// Read every cursor page so discovery can find posts beyond the home page.
final explorePostsProvider =
    FutureProvider.autoDispose<List<PostEntity>>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final repository = ref.watch(socialRepositoryProvider);
  final posts = <PostEntity>[];
  final cursors = <String>{};
  String? cursor;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  do {
    final result = await repository.getFeed(cursor: cursor);
    final page =
        result.when(success: (page) => page, failure: (error) => throw error);
    posts.addAll(page.items);
    cursor = page.nextCursor;
    if (!page.hasMore || cursor == null || !cursors.add(cursor)) break;
  } while (!disposed);
  return posts;
});

class SocialExploreVideosView extends ConsumerStatefulWidget {
  const SocialExploreVideosView({super.key});
  @override
  ConsumerState<SocialExploreVideosView> createState() => _SocialExploreState();
}

class _SocialExploreState extends ConsumerState<SocialExploreVideosView> {
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  int tab = 0;

  void updateQuery(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = value.trim().toLowerCase());
    });
    setState(() {});
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                Expanded(
                    child: TextField(
                controller: search,
                onChanged: updateQuery,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  debounce?.cancel();
                  setState(() => query = value.trim().toLowerCase());
                  FocusScope.of(context).unfocus();
                },
                decoration: InputDecoration(
                  hintText: 'Search posts, videos and clips',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            debounce?.cancel();
                            search.clear();
                            setState(() => query = '');
                          },
                        ),
                  filled: true,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                ),
              )),
                // Saved: clips, posts and collections (audio + playlists).
                IconButton(
                  tooltip: 'Saved',
                  icon: const Icon(Icons.bookmark_border_rounded, size: 26),
                  onPressed: () => openSavedClips(context),
                ),
              ]),
            ),
            TabBar(
              onTap: (value) {
                FocusScope.of(context).unfocus();
                setState(() => tab = value);
              },
              tabs: const [
                Tab(text: 'Posts'),
                Tab(text: 'Videos'),
                Tab(text: 'Clips'),
              ],
            ),
            Expanded(
              child: switch (tab) {
                0 => posts(),
                1 => videos(),
                _ => SocialClipsGrid(key: ValueKey(query), query: query),
              },
            ),
          ],
        ),
      );

  Widget failure(VoidCallback retry) => Center(
        child: TextButton(
          onPressed: retry,
          child: const Text('Could not load content. Retry'),
        ),
      );

  Widget posts() => ref.watch(explorePostsProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => failure(() => ref.invalidate(explorePostsProvider)),
        data: (all) => SocialExplorePostsView(
          posts: all,
          query: query,
          onRefresh: () async {
            ref.invalidate(explorePostsProvider);
            await ref.read(explorePostsProvider.future);
          },
        ),
      );

  Widget videos() => ref.watch(socialVideoCatalogProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            failure(() => ref.invalidate(socialVideoCatalogProvider)),
        data: (all) {
          final matches = all
              .where(
                (video) =>
                    video.kind == 'video' &&
                    video.title.toLowerCase().contains(query),
              )
              .toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(socialVideoCatalogProvider);
              await ref.read(socialVideoCatalogProvider.future);
            },
            child: ListView.builder(
              key: ValueKey('videos:$query'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: matches.isEmpty ? 1 : matches.length,
              itemBuilder: (context, index) {
                if (matches.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No videos match your search.'),
                  );
                }
                final video = matches[index];
                return SocialVideoCard(
                  video: socialVideoPresentation(video),
                  fallbackGradient: true,
                  showFollowPill: true,
                  onTap: () => ref.read(videoPlaybackProvider).open(video),
                );
              },
            ),
          );
        },
      );
}
