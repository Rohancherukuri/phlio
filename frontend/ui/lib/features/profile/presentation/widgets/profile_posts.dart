import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../social/data/models/post_model.dart';
import '../../../social/domain/entities/post_entity.dart';
import '../../../social/presentation/controllers/feed_controller.dart';
import '../../../social/presentation/controllers/video_library.dart';
import '../../../social/presentation/controllers/video_playback_controller.dart';
import '../../../social/presentation/widgets/social_clips_grid.dart';
import '../../../social/presentation/widgets/social_videos_view.dart';

final publicProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
  return (await getIt<ApiClient>().dio.get('/users/${Uri.encodeComponent(id)}'))
      .data as Map<String, dynamic>;
});

final profilePostsProvider = FutureProvider.autoDispose
    .family<List<PostEntity>, String>((ref, id) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  ref.watch(feedControllerProvider.select((value) => value.valueOrNull?.posts));
  final posts = <PostEntity>[];
  String? cursor;
  do {
    final data = (await getIt<ApiClient>().dio.get(
            '/users/${Uri.encodeComponent(id)}/posts',
            queryParameters: {if (cursor != null) 'cursor': cursor}))
        .data as Map;
    posts.addAll((data['items'] as List).map((item) =>
        PostModel.fromJson(Map<String, dynamic>.from(item as Map)).toEntity()));
    final next = (data['meta'] as Map)['next_cursor'] as String?;
    if (next == cursor) break;
    cursor = next;
  } while (cursor != null);
  return posts;
});

enum ProfilePostType {
  all('All', Icons.dashboard_outlined),
  articles('Articles', Icons.article_outlined),
  videos('Videos', Icons.videocam_outlined),
  pics('Pics', Icons.photo_outlined);

  const ProfilePostType(this.label, this.icon);
  final String label;
  final IconData icon;
  bool matches(PostEntity post) => switch (this) {
        all => true,
        articles => post.media.isEmpty,
        videos => post.media.any((m) => m.kind == MediaKind.video),
        pics => post.media.any((m) => m.kind == MediaKind.image),
      };

  /// Which uploaded videos (Social → New video) belong under this filter.
  /// Clips have their own profile tab.
  bool get includesUploads =>
      this == ProfilePostType.all || this == ProfilePostType.videos;
}

/// The menu lives in the Posts tab itself, so there is only one Posts control.
class ProfilePostsMenu extends StatelessWidget {
  const ProfilePostsMenu(
      {required this.selected,
      required this.onSelected,
      this.onOpened,
      super.key});
  final ProfilePostType selected;
  final ValueChanged<ProfilePostType> onSelected;
  final VoidCallback? onOpened;
  @override
  Widget build(BuildContext context) => PopupMenuButton<ProfilePostType>(
        tooltip: 'Filter posts: ${selected.label}',
        position: PopupMenuPosition.under,
        initialValue: selected,
        onOpened: onOpened,
        onSelected: onSelected,
        color: PhlioColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        itemBuilder: (_) => [
          for (final type in ProfilePostType.values)
            PopupMenuItem(
                value: type,
                child: Row(children: [
                  Icon(type.icon, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(type.label)),
                  if (selected == type)
                    const Icon(Icons.check, color: PhlioColors.brandBlue),
                ])),
        ],
        child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Posts'),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 20)
            ])),
      );
}

class ProfilePosts extends ConsumerWidget {
  const ProfilePosts({required this.author, required this.type, super.key});
  final String author;
  final ProfilePostType type;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profilePostsProvider(author));
    // Uploaded long-form videos sit with posts; clips have their own tab.
    final uploads =
        type.includesUploads ? ref.watch(socialVideoCatalogProvider) : null;
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
          child: TextButton.icon(
              onPressed: () => ref.invalidate(profilePostsProvider(author)),
              icon: const Icon(Icons.refresh),
              label: const Text('Could not load posts. Retry'))),
      data: (all) {
        final posts = all.where(type.matches).toList();
        final videos = uploads?.valueOrNull
                ?.where((v) => v.creator == author && v.kind != 'clip')
                .toList() ??
            <PlayableVideo>[];
        if (posts.isEmpty && videos.isEmpty) {
          if (uploads?.isLoading == true)
            return const Center(child: CircularProgressIndicator());
          if (uploads?.hasError == true)
            return Center(
                child: TextButton(
                    onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                    child: const Text('Could not load videos. Retry')));
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(type.icon, size: 40, color: PhlioColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                        type == ProfilePostType.all
                            ? 'No posts yet'
                            : 'No ${type.label.toLowerCase()} yet',
                        style: Theme.of(context).textTheme.titleMedium)
                  ])));
        }
        // Newest first across posts and uploaded videos.
        final entries = <(DateTime, Widget)>[
          for (final video in videos)
            (
              video.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              SocialVideoCard(
                  key: ValueKey('profile-video-${video.id}'),
                  video: socialVideoPresentation(video),
                  fallbackGradient: true,
                  onTap: () => ref.read(videoPlaybackProvider).open(video))
            ),
          for (final post in posts) (post.createdAt, _postCard(ref, post)),
        ]..sort((a, b) => b.$1.compareTo(a.$1));
        return ListView(padding: const EdgeInsets.all(12), children: [
          for (final entry in entries)
            Padding(
                padding: const EdgeInsets.only(bottom: 12), child: entry.$2),
        ]);
      },
    );
  }

  Widget _postCard(WidgetRef ref, PostEntity post) => ContentSurface(
      platform: 'social',
      contentId: post.id,
      child: Card(
          key: ValueKey('profile-post-${post.id}'),
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.text.isNotEmpty) Text(post.text),
                    for (final media in post.media.where((m) =>
                        type == ProfilePostType.all ||
                        (type == ProfilePostType.pics
                            ? m.kind == MediaKind.image
                            : m.kind == MediaKind.video)))
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: media.kind == MediaKind.image
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                      AppConfig.mediaUrl(media.url),
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const SizedBox(
                                              height: 100,
                                              child: Center(
                                                  child: Text(
                                                      'Image unavailable')))))
                              : ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                      Icons.play_circle_outline_rounded),
                                  title: const Text('Play video'),
                                  onTap: () => ref
                                      .read(videoPlaybackProvider)
                                      .open(PlayableVideo(
                                          id: '${post.id}-${media.url}',
                                          contentId: post.id,
                                          title: post.text.isEmpty
                                              ? 'Video'
                                              : post.text,
                                          creator: author,
                                          url: media.url)))),
                  ]))));
}

/// The profile Clips tab: the author's uploaded clips as a 3-column grid
/// with view counts; tapping plays them full-screen starting there.
class ProfileClips extends ConsumerWidget {
  const ProfileClips({required this.author, super.key});
  final String author;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(socialVideoCatalogProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
                child: TextButton(
                    onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                    child: const Text('Could not load clips. Retry'))),
            data: (all) {
              final clips = all
                  .where((v) => v.creator == author && v.kind == 'clip')
                  .toList();
              if (clips.isEmpty) {
                return Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.content_cut_rounded,
                              size: 40, color: PhlioColors.textMuted),
                          const SizedBox(height: 12),
                          Text('No clips yet',
                              style: Theme.of(context).textTheme.titleMedium),
                        ])));
              }
              final ids = [for (final clip in clips) clip.id];
              return GridView.builder(
                padding: const EdgeInsets.only(top: 2, bottom: 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    childAspectRatio: 0.66),
                itemCount: clips.length,
                itemBuilder: (_, i) => ClipTile(
                  thumbnailUrl: clips[i].thumbnailUrl,
                  viewsPath: 'social/${clips[i].id}',
                  onTap: () => openClipsPlayer(context,
                      initialClipId: clips[i].id, onlyIds: ids),
                ),
              );
            },
          );
}

/// Posts + uploaded videos + clips — the number shown on the profile.
int profileContentCount(WidgetRef ref, String author) {
  final posts = ref.watch(profilePostsProvider(author)).valueOrNull?.length ?? 0;
  final uploads = ref
          .watch(socialVideoCatalogProvider)
          .valueOrNull
          ?.where((v) => v.creator == author)
          .length ??
      0;
  return posts + uploads;
}
