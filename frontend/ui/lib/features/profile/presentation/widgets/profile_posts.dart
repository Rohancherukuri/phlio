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
import '../../../social/presentation/widgets/post_photos.dart';
import 'package:phlio/core/network/media_cache.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../shared/content/social_comments_sheet.dart' show showSocialComments;
import '../../../../shared/fact_checks/fact_checks.dart' show showFactCheckActions;
import '../../../../shared/moments/moment_features.dart' show setPostPinned, showPostQuickMenu;

final publicProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
  return (await getIt<ApiClient>().dio.get('/users/${Uri.encodeComponent(id)}'))
      .data as Map<String, dynamic>;
});

/// Post ids pinned on each profile (up to 6), in the server's order —
/// filled in by [profilePostsProvider] (the API sends them first).
final profilePinnedIds = <String, List<String>>{};

final profilePostsProvider = FutureProvider.autoDispose
    .family<List<PostEntity>, String>((ref, id) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  ref.watch(feedControllerProvider.select((value) => value.valueOrNull?.posts));
  final posts = <PostEntity>[];
  final pins = <String>[];
  String? cursor;
  do {
    final data = (await getIt<ApiClient>().dio.get(
            '/users/${Uri.encodeComponent(id)}/posts',
            queryParameters: {if (cursor != null) 'cursor': cursor}))
        .data as Map;
    for (final item in data['items'] as List) {
      final json = Map<String, dynamic>.from(item as Map);
      if (json['pinned'] == true) pins.add('${json['id']}');
      posts.add(PostModel.fromJson(json).toEntity());
    }
    final next = (data['meta'] as Map)['next_cursor'] as String?;
    if (next == cursor) break;
    cursor = next;
  } while (cursor != null);
  profilePinnedIds[id] = pins;
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
        // Pinned posts first (newest pin first), then newest first across
        // posts and uploaded videos.
        final pins = profilePinnedIds[author] ?? const <String>[];
        // Pics: an Instagram-style 3-column grid (Videos keep the cards).
        if (type == ProfilePostType.pics) {
          return _grid(context, ref, posts, videos, pins);
        }
        final pinned = [
          for (final pid in pins)
            for (final post in posts)
              if (post.id == pid) _postCard(context, ref, post, pinned: true)
        ];
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
          for (final post in posts)
            if (!pins.contains(post.id)) (post.createdAt, _postCard(context, ref, post)),
        ]..sort((a, b) => b.$1.compareTo(a.$1));
        return ListView(padding: const EdgeInsets.all(12), children: [
          for (final card in pinned)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
          for (final entry in entries)
            Padding(
                padding: const EdgeInsets.only(bottom: 12), child: entry.$2),
        ]);
      },
    );
  }

  /// One tile per post (its first photo or video), pinned first, then newest
  /// first; uploaded videos join the Videos grid by date.
  Widget _grid(BuildContext context, WidgetRef ref, List<PostEntity> posts, List<PlayableVideo> videos,
      List<String> pins) {
    final pics = type == ProfilePostType.pics;
    final want = pics ? MediaKind.image : MediaKind.video;
    Widget postTile(PostEntity post) {
      final media = post.media.where((m) => m.kind == want).toList();
      final first = media.first;
      final pinned = pins.contains(post.id);
      return _GridTile(
        key: ValueKey('grid-post-${post.id}'),
        pinned: pinned,
        multiple: media.length > 1,
        video: !pics,
        picture: pics ? first.url : first.thumbnailUrl,
        videoUrl: pics ? null : first.url,
        onTap: () {
          if (pics) {
            GoRouter.of(context).push('/shared/social/${Uri.encodeComponent(post.id)}');
          } else {
            ref.read(videoPlaybackProvider).open(PlayableVideo(
                id: '${post.id}-${first.url}',
                contentId: post.id,
                title: post.text.isEmpty ? 'Video' : post.text,
                creator: author,
                url: first.url));
          }
        },
        onLongPress: () => _quickMenu(context, ref, post, pinned),
      );
    }

    final pinnedTiles = [
      for (final pid in pins)
        for (final post in posts)
          if (post.id == pid) postTile(post)
    ];
    final rest = <(DateTime, Widget)>[
      for (final post in posts)
        if (!pins.contains(post.id)) (post.createdAt, postTile(post)),
      if (!pics)
        for (final video in videos)
          (
            video.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            _GridTile(
              key: ValueKey('grid-video-${video.id}'),
              video: true,
              picture: video.thumbnailUrl,
              videoUrl: video.url,
              onTap: () => ref.read(videoPlaybackProvider).open(video),
            )
          ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final tiles = [...pinnedTiles, for (final e in rest) e.$2];
    return GridView.builder(
      padding: const EdgeInsets.only(top: 2, bottom: 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: pics ? .8 : .66),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tiles[i],
    );
  }

  /// Long-press: Pin to your main grid (your own profile), Like, Comment,
  /// Share — with the post shown above the menu.
  Future<void> _quickMenu(BuildContext context, WidgetRef ref, PostEntity post, bool pinned) async {
    final me = ref.read(authControllerProvider).valueOrNull;
    final mine = me != null && (me.username == author || me.id == author || me.id == post.authorId);
    final action = await showPostQuickMenu(context,
        mine: mine, pinned: pinned, liked: post.likedByMe, preview: _postBody(ref, post, preview: true), more: true);
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'pin':
        if (await setPostPinned(context, post.id, !pinned)) ref.invalidate(profilePostsProvider(author));
      case 'like':
        try {
          await getIt<ApiClient>().dio.post('/social/posts/${Uri.encodeComponent(post.id)}/like');
          ref.invalidate(profilePostsProvider(author));
        } catch (_) {}
      case 'comment':
        await showSocialComments(context, post.id);
      case 'share':
        await showContentShare(context, 'social/${post.id}');
      case 'more': // Add context (fact checks) and the rest
        await showFactCheckActions(context, 'social/${post.id}',
            onShare: () => showContentShare(context, 'social/${post.id}'));
    }
  }

  Widget _postCard(BuildContext context, WidgetRef ref, PostEntity post, {bool pinned = false}) => ContentSurface(
      platform: 'social',
      contentId: post.id,
      child: GestureDetector(
        onLongPress: () => _quickMenu(context, ref, post, pinned),
        child: Card(
          key: ValueKey('profile-post-${post.id}'),
          child: _postBody(ref, post, pinned: pinned))));

  Widget _postBody(WidgetRef ref, PostEntity post, {bool pinned = false, bool preview = false}) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pinned)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Icon(Icons.push_pin_rounded, size: 15, color: PhlioColors.brandViolet),
                          SizedBox(width: 5),
                          Text('Pinned',
                              style: TextStyle(color: PhlioColors.brandViolet, fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    if (post.text.isNotEmpty) Text(post.text, maxLines: preview ? 6 : null),
                    // Photos share one full-width frame, like the feed.
                    if (type != ProfilePostType.videos &&
                        post.media.any((m) => m.kind == MediaKind.image))
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: PostPhotos(urls: [
                            for (final m in post.media)
                              if (m.kind == MediaKind.image) m.url
                          ])),
                    for (final media in post.media.where((m) =>
                        m.kind == MediaKind.video &&
                        type != ProfilePostType.pics))
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ListTile(
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
                  ]));
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

/// A square-ish grid tile: the photo (or the video's thumbnail / first
/// frame), with a pin, a "more photos" mark or a play mark in the corner.
class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.onTap,
    this.onLongPress,
    this.picture,
    this.videoUrl,
    this.video = false,
    this.pinned = false,
    this.multiple = false,
    super.key,
  });
  final String? picture, videoUrl;
  final bool video, pinned, multiple;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 6)];
    final Widget image = picture != null && picture!.isNotEmpty
        ? phlioNetworkImage(AppConfig.mediaUrl(picture!),
            fit: BoxFit.cover,
            cacheWidth: 360,
            errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined, color: PhlioColors.textMuted)))
        : videoUrl != null
            ? _FirstFrame(url: videoUrl!)
            : const Center(child: Icon(Icons.image_outlined, color: PhlioColors.textMuted));
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: PhlioColors.surfaceElevated, child: image),
        Positioned(
          top: 6,
          right: 6,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (pinned)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.push_pin_rounded, color: Colors.white, size: 17, shadows: shadow),
              ),
            if (multiple && !video)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.collections_rounded, color: Colors.white, size: 17, shadows: shadow),
              ),
            if (video)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 21, shadows: shadow),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A video's first frame, for videos without a thumbnail.
class _FirstFrame extends StatefulWidget {
  const _FirstFrame({required this.url});
  final String url;
  @override
  State<_FirstFrame> createState() => _FirstFrameState();
}

class _FirstFrameState extends State<_FirstFrame> {
  late final VideoPlayerController video =
      VideoPlayerController.networkUrl(Uri.parse(AppConfig.mediaUrl(widget.url)));

  @override
  void initState() {
    super.initState();
    video.initialize().then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => video.value.isInitialized
      ? FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: video.value.size.width, height: video.value.size.height, child: VideoPlayer(video)),
        )
      : const Center(child: Icon(Icons.movie_outlined, color: PhlioColors.textMuted));
}
