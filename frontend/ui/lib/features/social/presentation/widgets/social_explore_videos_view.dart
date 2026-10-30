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
  String category = 'All';

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
          final me = ref.watch(authControllerProvider).valueOrNull;
          final followed = ref.watch(followedCreatorsProvider);
          bool mine(PlayableVideo v) =>
              me != null && (v.creator == me.username || v.creator == me.id);
          final videos = all
              .where((video) =>
                  video.kind == 'video' &&
                  '${video.title} ${video.description} ${video.creatorName ?? ''} ${video.creator}'
                      .toLowerCase()
                      .contains(query))
              .toList();
          final yours = videos.where(mine).toList();
          final following = videos
              .where((v) => !mine(v) && followed.contains(v.creator))
              .toList();
          final recommended = videos
              .where((v) => !mine(v) && !followed.contains(v.creator))
              .toList();
          // Topic chips: only those with at least one video.
          final topics = [
            for (final topic in kVideoTopics.keys)
              if (videos.any((v) => videoTopics(v).contains(topic))) topic
          ];
          final chips = [
            'All',
            'Your uploads',
            if (following.isNotEmpty) 'Following',
            'Recommended for you',
            ...topics,
          ];
          if (!chips.contains(category)) category = 'All';

          // Rows: section labels (String) and videos.
          final rows = <Object>[];
          switch (category) {
            case 'All':
              if (yours.isNotEmpty) rows..add('Your uploads')..addAll(yours);
              if (following.isNotEmpty) {
                rows..add('Following')..addAll(following);
              }
              if (recommended.isNotEmpty) {
                rows..add('Recommended for you')..addAll(recommended);
              }
            case 'Your uploads':
              rows.addAll(yours);
            case 'Following':
              rows.addAll(following);
            case 'Recommended for you':
              rows.addAll(recommended);
            default:
              rows.addAll(videos.where((v) => videoTopics(v).contains(category)));
          }

          return Column(children: [
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final chip = chips[i];
                  final on = chip == category;
                  return ChoiceChip(
                    label: Text(chip),
                    selected: on,
                    showCheckmark: false,
                    avatar: chip == 'Your uploads'
                        ? Icon(Icons.video_library_outlined,
                            size: 16,
                            color: on ? Colors.black : Colors.white70)
                        : null,
                    labelStyle: TextStyle(
                        color: on ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w600),
                    selectedColor: Colors.white,
                    backgroundColor: const Color(0xFF202A3A),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    onSelected: (_) => setState(() => category = chip),
                  );
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(socialVideoCatalogProvider);
                  await ref.read(socialVideoCatalogProvider.future);
                },
                child: ListView.builder(
                  key: ValueKey('videos:$query:$category'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: rows.isEmpty ? 1 : rows.length,
                  itemBuilder: (context, index) {
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(category == 'Your uploads'
                            ? 'You haven\'t uploaded a video yet. Tap + → New video to share one.'
                            : query.isEmpty
                                ? 'No videos here yet.'
                                : 'No videos match your search.'),
                      );
                    }
                    final row = rows[index];
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                        child: Text(row,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      );
                    }
                    final video = row as PlayableVideo;
                    return SocialVideoCard(
                      key: ValueKey('${category}_${video.id}'),
                      video: socialVideoPresentation(video),
                      fallbackGradient: true,
                      showFollowPill: !mine(video) && !followed.contains(video.creator),
                      onTap: () => ref.read(videoPlaybackProvider).open(video),
                    );
                  },
                ),
              ),
            ),
          ]);
        },
      );
}

/// Topic → keywords matched against a video's title, description and tags.
const kVideoTopics = <String, List<String>>{
  'Film & Animation': ['film', 'movie', 'cinema', 'scene', 'tears of steel', 'animation', 'trailer', 'vfx', 'blender', 'short film'],
  'Music': ['music', 'song', 'beat', 'guitar', 'piano', 'concert', 'cover', 'gig', 'studio session', 'singing'],
  'Gaming': ['game', 'gaming', 'gameplay', 'ranked', 'esports', 'minecraft', 'valorant', 'bgmi'],
  'Tech & Code': ['code', 'coding', 'tech', 'programming', 'flutter', 'developer', 'app', ' ai ', 'software', 'build'],
  'Travel': ['travel', 'trip', 'vlog', 'city', 'beach', 'mountain', 'road trip', 'explore'],
  'Food': ['food', 'recipe', 'cook', 'kitchen', 'cafe', 'dinner', 'street food', 'biryani'],
  'Fitness': ['workout', 'gym', 'fitness', 'run', 'yoga', 'training', 'cardio'],
  'Photography': ['photo', 'camera', 'lens', 'shot', 'cinematography', 'portrait'],
  'Design & Art': ['design', 'art', 'drawing', 'paint', 'sketch', 'illustration', 'ui'],
  'Science': ['science', 'space', 'physics', 'lab', 'astronomy', 'experiment'],
  'Books': ['book', 'reading', 'novel', 'author', 'library'],
  'Comedy': ['funny', 'comedy', 'lol', 'prank', 'meme', 'stand-up'],
  'Education': ['learn', 'tutorial', 'how to', 'explained', 'study', 'lesson', 'tips'],
  'Lifestyle': ['day in my life', 'routine', 'lifestyle', 'vlog', 'home', 'fashion'],
};

Set<String> videoTopics(PlayableVideo video) {
  final text =
      ' ${video.title} ${video.description} ${video.songTitle ?? ''} '.toLowerCase();
  return {
    for (final entry in kVideoTopics.entries)
      if (entry.value.any(text.contains)) entry.key
  };
}
