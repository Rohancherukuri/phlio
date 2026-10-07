import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';

/// Social Videos — two Twitch-inspired surfaces sharing one seeded catalog:
/// * [SocialVideosView] — the home Videos tab: a "Following" feed with only
///   followed creators' content plus a "Recommended" block, in the Twitch
///   mobile style (full-bleed thumb, LIVE badge + metric on it, avatar/name
///   and the Follow pill BELOW the video, title, category chip).
/// * `SocialExploreVideosView` (social_explore_videos_view.dart) — discovery:
///   live rail, follows/followers/discover grids and category tags.
///
/// Follow state is a local seeded set (fresh accounts already "follow" the
/// story-strip creators) with a best-effort write to the backend follow API —
/// the UI must never block on the backend being reachable.
///
/// The State deliberately stays a plain `State` and owns no Riverpod `ref`;
/// `Consumer` children thread `ref` through parameters, keeping the element
/// tree immune to hot-reload subtype crashes.

/// One video/live entry. `kind` distinguishes live streams (red badge +
/// viewer count) from long-form videos and clips (view count).
@immutable
class SocialVideo {
  const SocialVideo({
    required this.title,
    required this.creator,
    required this.avatarAsset,
    required this.thumbAsset,
    required this.category,
    required this.kind,
    required this.metric,
  });

  final String title;
  final String creator;
  final String avatarAsset;
  final String thumbAsset;
  final String category;
  final SocialVideoKind kind;
  final String metric; // "1,240 viewers" or "48.2K views"
}

enum SocialVideoKind { live, video, clip }

const _assetBase = 'assets/images/placeholders/social';

/// Creators the fresh account already follows (the story-strip row).
const kFollowedCreatorSeed = [
  'pixelpanda',
  'artbykiara',
  'lofinight',
  'devdiaries',
];

/// Fictional creators who follow the account back (Explore "Follows you").
const kFollowersOfMe = ['retroray', 'wanderfox'];

/// Everyone else seeded for discovery.
const kDiscoverCreators = ['ironarena', 'chefatlas'];

/// Local source of truth for which creators are followed. Tapping Follow
/// toggles this instantly; the backend call is fire-and-forget.
final followedCreatorsProvider =
    StateProvider<Set<String>>((_) => kFollowedCreatorSeed.toSet());

const List<SocialVideo> kSocialVideos = [
  // -- Followed creators -------------------------------------------------------
  SocialVideo(
    title: 'Ranked grind till dawn — road to top 500',
    creator: 'pixelpanda',
    avatarAsset: '$_assetBase/avatar_pixelpanda.png',
    thumbAsset: '$_assetBase/thumb_gaming_1.png',
    category: 'Gaming',
    kind: SocialVideoKind.live,
    metric: '1,240 viewers',
  ),
  SocialVideo(
    title: 'Painting a dusk skyline in acrylics',
    creator: 'artbykiara',
    avatarAsset: '$_assetBase/avatar_artbykiara.png',
    thumbAsset: '$_assetBase/thumb_art_1.png',
    category: 'Art',
    kind: SocialVideoKind.live,
    metric: '342 viewers',
  ),
  SocialVideo(
    title: 'Late night lofi + chat',
    creator: 'lofinight',
    avatarAsset: '$_assetBase/avatar_lofinight.png',
    thumbAsset: '$_assetBase/thumb_music_1.png',
    category: 'Music',
    kind: SocialVideoKind.live,
    metric: '891 viewers',
  ),
  SocialVideo(
    title: 'Building a Flutter app from scratch — day 12',
    creator: 'devdiaries',
    avatarAsset: '$_assetBase/avatar_devdiaries.png',
    thumbAsset: '$_assetBase/thumb_tech_1.png',
    category: 'Tech',
    kind: SocialVideoKind.live,
    metric: '216 viewers',
  ),
  SocialVideo(
    title: "How I built Phlio's design system",
    creator: 'devdiaries',
    avatarAsset: '$_assetBase/avatar_devdiaries.png',
    thumbAsset: '$_assetBase/thumb_tech_2.png',
    category: 'Tech',
    kind: SocialVideoKind.video,
    metric: '12.4K views',
  ),
  SocialVideo(
    title: 'Speedrun practice — the castle skip, explained',
    creator: 'pixelpanda',
    avatarAsset: '$_assetBase/avatar_pixelpanda.png',
    thumbAsset: '$_assetBase/thumb_gaming_2.png',
    category: 'Gaming',
    kind: SocialVideoKind.video,
    metric: '24.6K views',
  ),
  SocialVideo(
    title: 'Line art to full colour in 45 seconds',
    creator: 'artbykiara',
    avatarAsset: '$_assetBase/avatar_artbykiara.png',
    thumbAsset: '$_assetBase/thumb_art_1.png',
    category: 'Art',
    kind: SocialVideoKind.clip,
    metric: '15.3K views',
  ),
  SocialVideo(
    title: '3AM study session — chill lofi mix',
    creator: 'lofinight',
    avatarAsset: '$_assetBase/avatar_lofinight.png',
    thumbAsset: '$_assetBase/thumb_music_1.png',
    category: 'Music',
    kind: SocialVideoKind.video,
    metric: '31K views',
  ),
  SocialVideo(
    title: 'Code review highlights — the 60 second cut',
    creator: 'devdiaries',
    avatarAsset: '$_assetBase/avatar_devdiaries.png',
    thumbAsset: '$_assetBase/thumb_tech_1.png',
    category: 'Tech',
    kind: SocialVideoKind.clip,
    metric: '6.4K views',
  ),
  // -- Follows you ---------------------------------------------------------------
  SocialVideo(
    title: 'Insane 1v4 clutch in the final circle',
    creator: 'retroray',
    avatarAsset: '$_assetBase/avatar_retroray.png',
    thumbAsset: '$_assetBase/thumb_gaming_2.png',
    category: 'Gaming',
    kind: SocialVideoKind.clip,
    metric: '48.2K views',
  ),
  SocialVideo(
    title: 'Ranked arena — viewer duos',
    creator: 'retroray',
    avatarAsset: '$_assetBase/avatar_retroray.png',
    thumbAsset: '$_assetBase/thumb_gaming_1.png',
    category: 'Gaming',
    kind: SocialVideoKind.live,
    metric: '4,880 viewers',
  ),
  SocialVideo(
    title: '48 hours in Hyderabad — food street tour',
    creator: 'wanderfox',
    avatarAsset: '$_assetBase/avatar_wanderfox.png',
    thumbAsset: '$_assetBase/thumb_travel_1.png',
    category: 'Travel',
    kind: SocialVideoKind.video,
    metric: '8.9K views',
  ),
  // -- Discover ------------------------------------------------------------------
  SocialVideo(
    title: 'Perfect squat form in 60 seconds',
    creator: 'ironarena',
    avatarAsset: '$_assetBase/avatar_ironarena.png',
    thumbAsset: '$_assetBase/thumb_fitness_1.png',
    category: 'Fitness',
    kind: SocialVideoKind.clip,
    metric: '22.1K views',
  ),
  SocialVideo(
    title: 'Push day — full session breakdown',
    creator: 'ironarena',
    avatarAsset: '$_assetBase/avatar_ironarena.png',
    thumbAsset: '$_assetBase/thumb_fitness_1.png',
    category: 'Fitness',
    kind: SocialVideoKind.video,
    metric: '11K views',
  ),
  SocialVideo(
    title: 'Dinner service — Indian street classics',
    creator: 'chefatlas',
    avatarAsset: '$_assetBase/avatar_chefatlas.png',
    thumbAsset: '$_assetBase/thumb_travel_1.png',
    category: 'Food',
    kind: SocialVideoKind.live,
    metric: '512 viewers',
  ),
  SocialVideo(
    title: 'Butter chicken in 60 seconds',
    creator: 'chefatlas',
    avatarAsset: '$_assetBase/avatar_chefatlas.png',
    thumbAsset: '$_assetBase/thumb_travel_1.png',
    category: 'Food',
    kind: SocialVideoKind.video,
    metric: '9.7K views',
  ),
];

/// Home Videos tab — the Following feed.
class SocialVideosView extends StatefulWidget {
  const SocialVideosView({super.key});
  @override
  State<SocialVideosView> createState() => _SocialVideosViewState();
}

class _SocialVideosViewState extends State<SocialVideosView> {
  bool uploading = false;
  double progress = 0;
  String? error;

  Future<void> pick(WidgetRef ref, bool publish) async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    if (!mounted || result == null || result.files.single.path == null) return;
    final file = result.files.single;
    if (!publish) {
      ref.read(videoPlaybackProvider).open(
            PlayableVideo(
              id: 'local:${file.path}',
              title: file.name,
              creator: '',
              url: '',
              localPath: file.path,
            ),
          );
      return;
    }
    if (file.size > 2 * 1024 * 1024 * 1024) {
      setState(() => error = 'Choose a video smaller than 2 GB.');
      return;
    }
    final title = TextEditingController(
      text: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish video'),
        content: TextField(
          controller: title,
          autofocus: true,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    final name = title.text.trim();
    // The dialog may still be animating out; its text field owns this listener until then.
    Future.delayed(const Duration(seconds: 1), title.dispose);
    if (!mounted || confirmed != true || name.isEmpty) return;
    setState(() {
      uploading = true;
      error = null;
      progress = 0;
    });
    try {
      final video = await ref.read(socialVideoApiProvider).upload(
        file.path!,
        name,
        onProgress: (sent, total) {
          if (mounted) setState(() => progress = total > 0 ? sent / total : 0);
        },
      );
      if (!mounted) return;
      ref.invalidate(socialVideoCatalogProvider);
      ref.read(videoPlaybackProvider).open(video);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Upload failed. Check your connection and video format, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consumer child owns the Riverpod ref; this State stays ref-free.
    return Consumer(
      builder: (context, ref, child) => _followingFeed(context, ref),
    );
  }

  Widget _followingFeed(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedCreatorsProvider);
    final fromFollows =
        kSocialVideos.where((v) => followed.contains(v.creator)).toList();
    final recommended =
        kSocialVideos.where((v) => !followed.contains(v.creator)).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.xxl),
      children: [
        // Slim header: the real upload pipeline stays one tap away without
        // turning the feed into a "Discover" page.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.sm, 0),
          child: Row(
            children: [
              Expanded(
                  child: Text('Following', style: PhlioTypography.headline)),
              IconButton(
                tooltip: 'Open a video from your device',
                icon: const Icon(Icons.video_library_outlined,
                    size: 22, color: PhlioColors.textSecondary),
                onPressed: uploading ? null : () => pick(ref, false),
              ),
              IconButton(
                tooltip: 'Upload a video',
                icon: const Icon(Icons.upload_rounded,
                    size: 22, color: PhlioColors.textSecondary),
                onPressed: uploading ? null : () => pick(ref, true),
              ),
            ],
          ),
        ),
        if (uploading)
          const Padding(
            padding:
                EdgeInsets.symmetric(horizontal: PhlioSpacing.lg, vertical: 4),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: PhlioSpacing.lg, vertical: 4),
            child: Text(error!,
                style: PhlioTypography.caption
                    .copyWith(color: PhlioColors.danger)),
          ),
        // Followed creators' content — live and VOD interleaved, newest-first
        // feel via the seed order.
        for (final video in fromFollows)
          SocialVideoCard(video: video, onTap: () => _demoNote(context, video)),
        _sectionLabel('Recommended for you'),
        for (final video in recommended)
          SocialVideoCard(
            video: video,
            showFollowPill: true,
            onTap: () => _demoNote(context, video),
          ),
        _sectionLabel('Your uploads'),
        _uploadsSection(context, ref),
      ],
    );
  }

  Widget _uploadsSection(BuildContext context, WidgetRef ref) {
    // Real backend videos, when the API is reachable — the feed must never
    // block or error on it, so failures render as nothing at all.
    final catalog = ref.watch(socialVideoCatalogProvider);
    return catalog.whenOrNull(
          data: (videos) => videos.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    for (final video in videos)
                      SocialVideoCard(
                        video: SocialVideo(
                          title: video.title,
                          creator: video.creator,
                          avatarAsset: '',
                          thumbAsset: '',
                          category: 'Your upload',
                          kind: SocialVideoKind.video,
                          metric: 'Just you',
                        ),
                        fallbackGradient: true,
                        onTap: () =>
                            ref.read(videoPlaybackProvider).open(video),
                      ),
                  ],
                ),
        ) ??
        const SizedBox.shrink();
  }

  void _demoNote(BuildContext context, SocialVideo video) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        video.kind == SocialVideoKind.live
            ? 'Demo stream — real live playback lands with the Stream platform.'
            : 'Demo video — upload one to get real playback.',
      ),
    ));
  }

  static Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.xl, PhlioSpacing.lg, PhlioSpacing.sm),
      child: Text(text, style: PhlioTypography.title),
    );
  }
}

/// Twitch-style full-width card: 16:9 thumb with LIVE badge + metric overlay,
/// then avatar / creator / Follow pill, title and category chip below.
class SocialVideoCard extends ConsumerWidget {
  const SocialVideoCard({
    required this.video,
    required this.onTap,
    this.showFollowPill = false,
    this.fallbackGradient = false,
    super.key,
  });

  final SocialVideo video;
  final VoidCallback onTap;
  final bool showFollowPill;
  final bool fallbackGradient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLive = video.kind == SocialVideoKind.live;
    return Padding(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: fallbackGradient && video.thumbAsset.isEmpty
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                PhlioColors.brandViolet.withValues(alpha: 0.35),
                                PhlioColors.surfaceElevated,
                              ],
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.play_arrow_rounded,
                                size: 44, color: PhlioColors.textSecondary),
                          ),
                        )
                      : Image.asset(
                          video.thumbAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  PhlioColors.brandViolet
                                      .withValues(alpha: 0.35),
                                  PhlioColors.surfaceElevated,
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.play_arrow_rounded,
                                  size: 44, color: PhlioColors.textSecondary),
                            ),
                          ),
                        ),
                ),
                if (isLive)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _liveBadge(),
                  ),
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: _overlayPill(video.metric),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.lg, 0),
              child: Row(
                children: [
                  GestureDetector(
                    // Tap the creator's avatar/name to open their profile.
                    onTap: () => context.push('/creator/${video.creator}'),
                    child: ClipOval(
                      child: Image.asset(
                        video.avatarAsset,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 36,
                          height: 36,
                          color:
                              PhlioColors.brandViolet.withValues(alpha: 0.25),
                          alignment: Alignment.center,
                          child: Text(
                            video.creator.isEmpty
                                ? '?'
                                : video.creator[0].toUpperCase(),
                            style: PhlioTypography.label
                                .copyWith(color: PhlioColors.brandLavender),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: PhlioSpacing.sm),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('/creator/${video.creator}'),
                      child: Text(
                        video.creator,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.bodyStrong,
                      ),
                    ),
                  ),
                  if (showFollowPill) ...[
                    const SizedBox(width: PhlioSpacing.sm),
                    CreatorFollowPill(creator: video.creator),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  PhlioSpacing.lg, PhlioSpacing.xxs, PhlioSpacing.lg, 0),
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.body
                    .copyWith(color: PhlioColors.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  PhlioSpacing.lg, PhlioSpacing.xs, PhlioSpacing.lg, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: PhlioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: PhlioColors.borderSubtle),
                ),
                child: Text(
                  video.category,
                  style: PhlioTypography.caption
                      .copyWith(fontSize: 11, color: PhlioColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PhlioColors.danger,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text('LIVE',
              style: PhlioTypography.label.copyWith(
                fontSize: 11,
                letterSpacing: 0.6,
                color: Colors.white,
              )),
        ],
      ),
    );
  }

  static Widget _overlayPill(String metric) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        metric,
        style: PhlioTypography.caption.copyWith(
          fontSize: 11,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Follow / Following pill driven by the local followed set, with a
/// best-effort write to the backend follow API (never blocks the UI).
class CreatorFollowPill extends ConsumerWidget {
  const CreatorFollowPill({required this.creator, super.key});

  final String creator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedCreatorsProvider);
    final isFollowed = followed.contains(creator);
    return GestureDetector(
      onTap: () {
        ref.read(followedCreatorsProvider.notifier).update((set) {
          final next = Set<String>.from(set);
          if (!next.remove(creator)) next.add(creator);
          return next;
        });
        // Backend stays in the loop when it is reachable; failures are fine —
        // the local state is the demo source of truth.
        ref
            .read(socialVideoApiProvider)
            .follow(creator, !isFollowed)
            .catchError((_) {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isFollowed ? Colors.transparent : PhlioColors.brandViolet,
          borderRadius: BorderRadius.circular(999),
          border:
              isFollowed ? Border.all(color: PhlioColors.borderSubtle) : null,
        ),
        child: Text(
          isFollowed ? 'Following' : 'Follow',
          style: PhlioTypography.label.copyWith(
            fontSize: 12,
            color: isFollowed ? PhlioColors.textSecondary : Colors.white,
          ),
        ),
      ),
    );
  }
}
