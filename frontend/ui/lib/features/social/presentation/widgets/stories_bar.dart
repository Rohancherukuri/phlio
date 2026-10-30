import '../../../../shared/content/moment_viewer.dart';
import '../../../../shared/moments/moments.dart';
import 'moment_composer.dart';
import 'package:phlio/shared/content/content_surface.dart';
// Stories for the Social home, following the reference app's behavior:
//
//  * At rest (feed at top) — a full-width strip of large circle avatars
//    with names below them, sitting above the Posts/Videos/Clips tabs.
//  * When the user scrolls — the strip collapses away and a compact
//    overlapping avatar stack slides into the header row, inline with the
//    tabs (what the reference shows in its scrolled state).
//
// The first tile opens 24-hour content reshares; creator circles open profiles.

import 'package:flutter/material.dart';
import '../../../../app/config/app_config.dart';
import '../controllers/video_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';

String storyDisplayName(WidgetRef ref, String id) {
  for (final group in ref.watch(momentFeedProvider).valueOrNull ?? const []) {
    final author = group['author'] as Map;
    if (author['username'] == id || author['id'] == id) {
      return author['display_name'] as String? ?? id;
    }
  }
  for (final video in ref.watch(socialVideoCatalogProvider).valueOrNull ??
      <PlayableVideo>[]) {
    if (video.creator == id && video.creatorName?.isNotEmpty == true)
      return video.creatorName!;
  }
  return id;
}

/// Seeded "following" list for the stories surfaces — mirrors the creators
/// in the Videos tab (`social_videos_view.dart`) so the surfaces feel like
/// one social graph. Replaced by real follows once the social graph API
/// lands.
final storyUsersProvider =
    Provider.autoDispose<List<({String name, String avatarAsset})>>((ref) {
  // People with live moments (story rail), excluding yourself.
  final me = ref.watch(authControllerProvider).valueOrNull?.id;
  final groups = ref.watch(momentFeedProvider).valueOrNull ?? const [];
  return [
    for (final group in groups)
      if ((group['author'] as Map)['id'] != me)
        (
          name: ((group['author'] as Map)['username'] ??
                  (group['author'] as Map)['id'])
              .toString(),
          avatarAsset: (group['author'] as Map)['avatar_url'] as String? ?? ''
        )
  ];
});

/// Circles open that person's moments, then continue through the rail.
void _openCreator(BuildContext context, WidgetRef ref, String name) {
  final groups = ref.read(momentFeedProvider).valueOrNull ?? const [];
  final start = groups.indexWhere((g) =>
      (g['author'] as Map)['username'] == name ||
      (g['author'] as Map)['id'] == name);
  if (start < 0) {
    openUserMoments(context, name);
  } else {
    openMomentGroups(context, groups, start: start);
  }
}

/// Your own circle: tap plays your live moments (or starts a new one),
/// the + badge always starts a new one.
Widget _ownMoment(BuildContext context, WidgetRef ref, String name, double size) {
  final me = ref.watch(authControllerProvider).valueOrNull;
  final badge = (size * .38).clamp(16.0, 22.0);
  return Stack(clipBehavior: Clip.none, children: [
    MomentRingAvatar(
      userId: me?.id ?? '',
      size: size,
      plain: GestureDetector(
          onTap: () => openMomentComposer(context),
          child: MeAvatar(name: name, size: size)),
      ringed: (inner) => MeAvatar(name: name, size: inner),
    ),
    Positioned(
      right: -1,
      bottom: -1,
      child: GestureDetector(
        onTap: () => openMomentComposer(context),
        child: Container(
          width: badge,
          height: badge,
          decoration: BoxDecoration(
              gradient: PhlioColors.sunsetGradient,
              shape: BoxShape.circle,
              border: Border.all(color: PhlioColors.background, width: 2)),
          child: Icon(Icons.add_rounded,
              size: badge * .66, color: PhlioColors.textOnBrand),
        ),
      ),
    ),
  ]);
}

/// The expanded, full-width strip shown while the feed is at the top:
/// "Your story" first, then followed users, each a large circle with their
/// name underneath.
class StoriesStrip extends ConsumerWidget {
  const StoriesStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authControllerProvider).valueOrNull;
    final kStoryUsers = ref.watch(storyUsersProvider);

    return SizedBox(
      height: 100 +
          (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0, 60) * 1.4,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.fromLTRB(PhlioSpacing.lg, 12, PhlioSpacing.lg, 8),
        children: [
          _StripItem(
            label: 'Your moment',
            onTap: () {},
            child: _ownMoment(context, ref, currentUser?.fullName ?? 'You', 56),
          ),
          for (final user in kStoryUsers) ...[
            _StripItem(
              label: storyDisplayName(ref, user.name),
              onTap: () => _openCreator(context, ref, user.name),
              child: _ringedAvatar(user,
                  size: 56, onTap: () => _openCreator(context, ref, user.name)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  const _StripItem(
      {required this.label, required this.child, required this.onTap});

  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        // ClipRect: the parent strip animates its height between 0 and full,
        // and mid-animation the tight constraints are smaller than this
        // content — clip instead of throwing a RenderFlex overflow.
        child: ClipRect(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              const SizedBox(height: 4),
              Text(
                label,
                style: PhlioTypography.caption.copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The compact overlapping stack that appears in the header row once the
/// user has scrolled — the reference app's collapsed state.
class StoriesHeaderStack extends ConsumerWidget {
  const StoriesHeaderStack({super.key, this.avatarSize = 26});

  final double avatarSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Your avatar + the first few followed users, overlapping Twitch-style.
    final visible = ref.watch(storyUsersProvider).take(4).toList();
    return SizedBox(
      height: avatarSize + 4,
      width: avatarSize + (visible.length - 1) * (avatarSize * 0.55) + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = visible.length - 1; i >= 0; i--)
            Positioned(
              left: i * avatarSize * 0.55,
              child: _StoryRing(
                userId: visible[i].name,
                onTap: () => _openCreator(context, ref, visible[i].name),
                size: avatarSize,
                child: ClipOval(
                  child: Image.network(
                    AppConfig.mediaUrl(visible[i].avatarAsset),
                    width: avatarSize - 7,
                    height: avatarSize - 7,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => PhlioAvatar(
                        name: visible[i].name, size: avatarSize - 7),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Phlio rim light around a story-rail avatar (bright when unseen).
class _StoryRing extends ConsumerWidget {
  const _StoryRing(
      {required this.child,
      required this.size,
      required this.onTap,
      this.userId});

  final Widget child;
  final double size;
  final VoidCallback onTap;
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = userId == null
        ? null
        : ref.watch(momentRingsProvider).valueOrNull?[userId];
    return GestureDetector(
      onTap: onTap,
      child: RimLight(
        size: size,
        unseen: state == null || state['unseen'] == true,
        fresh: state?['fresh'] == true,
        child: child,
      ),
    );
  }
}

Widget _ringedAvatar(
  ({String name, String avatarAsset}) user, {
  required double size,
  required VoidCallback onTap,
}) {
  return _StoryRing(
    onTap: onTap,
    size: size,
    userId: user.name,
    child: ClipOval(
      child: Image.network(
        AppConfig.mediaUrl(user.avatarAsset),
        width: size - 7,
        height: size - 7,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) =>
            PhlioAvatar(name: user.name, size: size - 7),
      ),
    ),
  );
}

/// A single set of avatars moves from the story rail into the toolbar.
/// Positions, spacing and sizes share the same scroll progress; there is no
/// second avatar row to cross-fade into or swap at the end of the animation.
class MorphingStoriesHeader extends ConsumerStatefulWidget {
  const MorphingStoriesHeader(
      {required this.progress,
      required this.toolbar,
      required this.compactBelow,
      this.onExpand,
      this.clipMode = false,
      super.key});
  final bool clipMode;
  final double progress;
  final Widget toolbar;
  final bool compactBelow;
  final VoidCallback? onExpand;
  @override
  ConsumerState<MorphingStoriesHeader> createState() =>
      _MorphingStoriesHeaderState();
}

class _MorphingStoriesHeaderState extends ConsumerState<MorphingStoriesHeader> {
  double _horizontalOffset = 0;
  @override
  Widget build(BuildContext context) {
    if (widget.clipMode) {
      final groups = ref.watch(momentFeedProvider).valueOrNull ?? const [];
      final people = [for (final g in groups) g['author'] as Map];
      final p = widget.progress.clamp(0.0, 1.0);
      Widget avatar(int index, double size) {
        if (index >= people.length)
          return Semantics(
              label: 'No moment',
              child: Container(
                  key: ValueKey('empty-moment-$index'),
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                      color: Color(0xff44464B), shape: BoxShape.circle)));
        final author = people[index];
        final ring = RimLight(
            size: size,
            unseen: groups[index]['unseen'] == true,
            child: PhlioAvatar(
                name: author['display_name'] as String? ?? '',
                imageUrl: author['avatar_url'] as String?,
                showMomentRing: false,
                size: size - 2 * RimLight.insetFor(size)));
        return GestureDetector(
            onTap: () => openMomentGroups(context, groups, start: index),
            child: ring);
      }

      return LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final toolbarHeight = 56.0 +
            (MediaQuery.textScalerOf(context).scale(16) - 22).clamp(0, 60);
        final count = people.length < 4 ? 4 : people.length;
        return SizedBox(
            height: toolbarHeight + 104 * (1 - p),
            child: GestureDetector(
              onHorizontalDragUpdate: p < .1
                  ? (event) => setState(() => _horizontalOffset =
                      (_horizontalOffset - event.delta.dx).clamp(
                          0.0,
                          (count * 80.0 + 32 - width)
                              .clamp(0.0, double.infinity)))
                  : null,
              child: ClipRect(
                  child: Stack(children: [
                Positioned(
                    left: 0,
                    right: 62 * p,
                    top: 104 * (1 - p),
                    height: toolbarHeight,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(18 * (1 - p))),
                            border: Border(
                                top: BorderSide(
                                    color: PhlioColors.borderSubtle))),
                        child: widget.toolbar)),
                for (var index = count - 1; index >= 0; index--)
                  if (index < 4 || p < .95)
                    Positioned(
                        key: ValueKey('moment-position-$index'),
                        left: (16 + index * 80 - _horizontalOffset) * (1 - p) +
                            (width - 62 + index * 11) * p,
                        top: 8 * (1 - p) + (toolbarHeight - 24) / 2 * p,
                        child: Opacity(
                          opacity: index < 4 ? 1 : 1 - p,
                          child: SizedBox(
                              width: 56 - 32 * p,
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    avatar(index, 56 - 32 * p),
                                    if (index < people.length && p < .95)
                                      Opacity(
                                          opacity: (1 - p * 3).clamp(0.0, 1.0),
                                          child: Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 6),
                                              child: Text(
                                                  people[index]['display_name']
                                                      as String,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 11)))),
                                  ])),
                        )),
              ])),
            ));
      });
    }
    final currentUser = ref.watch(authControllerProvider).valueOrNull;
    final kStoryUsers = ref.watch(storyUsersProvider);
    final p = widget.progress.clamp(0.0, 1.0);
    final storyHeight = 100 +
        (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0, 60) * 1.4;
    final toolbarHeight =
        52.0 + (MediaQuery.textScalerOf(context).scale(16) - 22).clamp(0, 60);
    final extra = widget.compactBelow ? 36.0 : 0.0;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final compactLeft = width - (widget.compactBelow ? 16 : 60) - 62;
      final compactTop =
          widget.compactBelow ? toolbarHeight + 4 : (toolbarHeight - 22) / 2;
      final height = toolbarHeight + storyHeight * (1 - p) + extra * p;
      final labels = (1 - p * 5).clamp(0.0, 1.0);
      return SizedBox(
          key: const ValueKey('social-morph-header'),
          height: height,
          child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: p < .05
                  ? (event) => setState(() => _horizontalOffset =
                      (_horizontalOffset - event.delta.dx).clamp(
                          0.0,
                          (68.0 * (kStoryUsers.length + 1) + 32 - width)
                              .clamp(0.0, double.infinity)))
                  : null,
              child: ClipRect(
                  child: Stack(children: [
                Positioned(
                    left: 0,
                    right: 0,
                    top: storyHeight * (1 - p),
                    height: toolbarHeight,
                    child: widget.toolbar),
                for (var index = kStoryUsers.length; index >= 0; index--)
                  _movingStory(context, index, p, labels, compactLeft,
                      compactTop, currentUser?.fullName ?? 'You', kStoryUsers),
                if (p > .95)
                  Positioned(
                      left: compactLeft - 4,
                      top: compactTop - 10,
                      width: 70,
                      height: 44,
                      child: Semantics(
                          button: true,
                          label: 'Expand stories',
                          child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onExpand))),
              ]))));
    });
  }

  Widget _movingStory(
      BuildContext context,
      int index,
      double p,
      double labels,
      double compactLeft,
      double compactTop,
      String ownName,
      List<({String name, String avatarAsset})> kStoryUsers) {
    final retained = index >= 1 && index <= 4;
    final opacity = retained ? 1.0 : (1 - p * 5).clamp(0.0, 1.0);
    final size = 56 + (22 - 56) * p;
    final start = 22 + index * 68.0 - _horizontalOffset;
    final target = compactLeft + (index - 1) * 12.0;
    final left = start + (target - start) * p;
    final top = 12 + (compactTop - 12) * p;
    final user = index == 0 ? null : kStoryUsers[index - 1];
    final name = user == null ? ownName : storyDisplayName(ref, user.name);
    return Positioned(
        key: ValueKey('social-story-position-$index'),
        left: left,
        top: top,
        width: size,
        height: size + 40 * (1 - p),
        child: IgnorePointer(
            ignoring: p > .05,
            child: ExcludeSemantics(
                excluding: p > .05,
                child: Opacity(
                    opacity: opacity,
                    child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: 68,
                        maxWidth: 68,
                        minHeight: 0,
                        maxHeight: 130,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                              key: ValueKey('social-story-avatar-$index'),
                              width: size,
                              height: size,
                              child: index == 0
                                  ? _ownMoment(context, ref, ownName, size)
                                  : _ringedAvatar(user!,
                                      size: size,
                                      onTap: () =>
                                          _openCreator(context, ref, user.name))),
                          if (labels > 0)
                            Opacity(
                                opacity: labels,
                                child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: PhlioTypography.caption
                                            .copyWith(fontSize: 11)))),
                        ]))))));
  }
}
