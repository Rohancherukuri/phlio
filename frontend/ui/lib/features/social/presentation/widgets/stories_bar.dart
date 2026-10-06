// Stories for the Social home, following the reference app's behavior:
//
//  * At rest (feed at top) — a full-width strip of large circle avatars
//    with names below them, sitting above the Posts/Videos/Clips tabs.
//  * When the user scrolls — the strip collapses away and a compact
//    overlapping avatar stack slides into the header row, inline with the
//    tabs (what the reference shows in its scrolled state).
//
// Story playback needs the Stories domain (blueprint section 5) — tapping
// a creator's circle opens their profile page; "Your story" keeps the
// honest "coming soon" snackbar. The visual language is already the real
// one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';

/// Seeded "following" list for the stories surfaces — mirrors the creators
/// in the Videos tab (`social_videos_view.dart`) so the surfaces feel like
/// one social graph. Replaced by real follows once the social graph API
/// lands.
const List<({String name, String avatarAsset})> kStoryUsers = [
  (
    name: 'pixelpanda',
    avatarAsset: 'assets/images/placeholders/social/avatar_pixelpanda.png'
  ),
  (
    name: 'artbykiara',
    avatarAsset: 'assets/images/placeholders/social/avatar_artbykiara.png'
  ),
  (
    name: 'lofinight',
    avatarAsset: 'assets/images/placeholders/social/avatar_lofinight.png'
  ),
  (
    name: 'devdiaries',
    avatarAsset: 'assets/images/placeholders/social/avatar_devdiaries.png'
  ),
  (
    name: 'wanderfox',
    avatarAsset: 'assets/images/placeholders/social/avatar_wanderfox.png'
  ),
  (
    name: 'ironarena',
    avatarAsset: 'assets/images/placeholders/social/avatar_ironarena.png'
  ),
  (
    name: 'retroray',
    avatarAsset: 'assets/images/placeholders/social/avatar_retroray.png'
  ),
  (
    name: 'chefatlas',
    avatarAsset: 'assets/images/placeholders/social/avatar_chefatlas.png'
  ),
];

void _comingSoon(BuildContext context, String name) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("$name's stories are coming soon.")),
  );
}

/// Creator circles open the creator's profile page; story playback itself
/// stays a coming-soon until the Stories domain lands.
void _openCreator(BuildContext context, String name) {
  context.push('/creator/$name');
}

/// The expanded, full-width strip shown while the feed is at the top:
/// "Your story" first, then followed users, each a large circle with their
/// name underneath.
class StoriesStrip extends ConsumerWidget {
  const StoriesStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authControllerProvider).valueOrNull;

    return SizedBox(
      height: 100 +
          (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0, 60) * 1.4,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.fromLTRB(PhlioSpacing.lg, 12, PhlioSpacing.lg, 8),
        children: [
          _StripItem(
            label: 'Your story',
            onTap: () => _comingSoon(context, 'Your'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PhlioAvatar(name: currentUser?.fullName ?? 'You', size: 56),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      gradient: PhlioColors.sunsetGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_rounded,
                        size: 14, color: PhlioColors.textOnBrand),
                  ),
                ),
              ],
            ),
          ),
          for (final user in kStoryUsers) ...[
            _StripItem(
              label: user.name,
              onTap: () => _openCreator(context, user.name),
              child: _ringedAvatar(user,
                  size: 56, onTap: () => _openCreator(context, user.name)),
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
class StoriesHeaderStack extends StatelessWidget {
  const StoriesHeaderStack({super.key, this.avatarSize = 26});

  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    // Your avatar + the first few followed users, overlapping Twitch-style.
    final visible = kStoryUsers.take(4).toList();
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
                onTap: () => _openCreator(context, visible[i].name),
                size: avatarSize,
                child: ClipOval(
                  child: Image.asset(
                    visible[i].avatarAsset,
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

/// Sunset-gradient story ring around any child.
class _StoryRing extends StatelessWidget {
  const _StoryRing(
      {required this.child, required this.size, required this.onTap});

  final Widget child;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          gradient: PhlioColors.sunsetGradient,
          shape: BoxShape.circle,
        ),
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: const BoxDecoration(
            color: PhlioColors.background,
            shape: BoxShape.circle,
          ),
          child: child,
        ),
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
    child: ClipOval(
      child: Image.asset(
        user.avatarAsset,
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
      super.key});
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
    final currentUser = ref.watch(authControllerProvider).valueOrNull;
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
                      compactTop, currentUser?.fullName ?? 'You'),
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

  Widget _movingStory(BuildContext context, int index, double p, double labels,
      double compactLeft, double compactTop, String ownName) {
    final retained = index >= 1 && index <= 4;
    final opacity = retained ? 1.0 : (1 - p * 5).clamp(0.0, 1.0);
    final size = 56 + (22 - 56) * p;
    final start = 22 + index * 68.0 - _horizontalOffset;
    final target = compactLeft + (index - 1) * 12.0;
    final left = start + (target - start) * p;
    final top = 12 + (compactTop - 12) * p;
    final user = index == 0 ? null : kStoryUsers[index - 1];
    final name = user?.name ?? 'Your story';
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
                                  ? GestureDetector(
                                      onTap: () => _comingSoon(context, 'Your'),
                                      child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            PhlioAvatar(
                                                name: ownName, size: size),
                                            Positioned(
                                                right: -1,
                                                bottom: -1,
                                                child: Container(
                                                    width: 22,
                                                    height: 22,
                                                    decoration:
                                                        const BoxDecoration(
                                                            gradient: PhlioColors
                                                                .sunsetGradient,
                                                            shape: BoxShape
                                                                .circle),
                                                    child: const Icon(Icons.add,
                                                        size: 14,
                                                        color: PhlioColors
                                                            .textOnBrand))),
                                          ]))
                                  : _ringedAvatar(user!,
                                      size: size,
                                      onTap: () =>
                                          _openCreator(context, name))),
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
