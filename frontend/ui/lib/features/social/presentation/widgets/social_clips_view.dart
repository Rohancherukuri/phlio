// The Clips tab: short-form vertical content (Instagram Reels / YouTube
// Shorts style). A vertically snapping PageView of full-bleed cards, each
// with a Reels-style overlay — creator + follow on the left, an action
// rail (like, comment, share, more) on the right, title and a music
// ticker at the bottom, and a progress bar.
//
// Clips are seeded placeholder content rendered from
// `assets/images/placeholders/social/clip_*.png`; playback (Phlio Stream)
// replaces the tap response when that platform ships.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';

@immutable
class SocialClip {
  const SocialClip({
    required this.title,
    required this.creator,
    required this.avatarAsset,
    required this.clipAsset,
    required this.song,
    required this.likes,
    required this.comments,
  });

  final String title;
  final String creator;
  final String avatarAsset;
  final String clipAsset;
  final String song;
  final int likes;
  final int comments;
}

const _assetBase = 'assets/images/placeholders/social';

const List<SocialClip> kSocialClips = [
  SocialClip(
    title: 'The 1v4 clutch that won us the match',
    creator: 'retroray',
    avatarAsset: '$_assetBase/avatar_retroray.png',
    clipAsset: '$_assetBase/clip_gaming.png',
    song: 'phonk rampage · dj volt',
    likes: 24800,
    comments: 1204,
  ),
  SocialClip(
    title: '30-second sketch challenge: dusk edition',
    creator: 'artbykiara',
    avatarAsset: '$_assetBase/avatar_artbykiara.png',
    clipAsset: '$_assetBase/clip_art.png',
    song: 'golden hour · mellow tapes',
    likes: 9400,
    comments: 342,
  ),
  SocialClip(
    title: 'The beat switch everyone saw coming',
    creator: 'lofinight',
    avatarAsset: '$_assetBase/avatar_lofinight.png',
    clipAsset: '$_assetBase/clip_music.png',
    song: 'late night lofi · original',
    likes: 15600,
    comments: 891,
  ),
  SocialClip(
    title: 'Hot reload is still magic, honestly',
    creator: 'devdiaries',
    avatarAsset: '$_assetBase/avatar_devdiaries.png',
    clipAsset: '$_assetBase/clip_tech.png',
    song: 'focus flow · synth wave',
    likes: 7200,
    comments: 216,
  ),
  SocialClip(
    title: 'Form check: fix your squat in 60s',
    creator: 'ironarena',
    avatarAsset: '$_assetBase/avatar_ironarena.png',
    clipAsset: '$_assetBase/clip_fitness.png',
    song: 'power hour · gym session',
    likes: 11200,
    comments: 402,
  ),
];

class SocialClipsView extends StatefulWidget {
  const SocialClipsView({super.key});

  @override
  State<SocialClipsView> createState() => _SocialClipsViewState();
}

class _SocialClipsViewState extends State<SocialClipsView> {
  final Set<String> _liked = {};
  final Set<String> _following = {};

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: kSocialClips.length,
      itemBuilder: (context, index) {
        final clip = kSocialClips[index];
        return _ClipPage(
          clip: clip,
          isLiked: _liked.contains(clip.creator + clip.title),
          isFollowing: _following.contains(clip.creator),
          onToggleLike: () => setState(() {
            final key = clip.creator + clip.title;
            _liked.contains(key) ? _liked.remove(key) : _liked.add(key);
          }),
          onToggleFollow: () => setState(() {
            _following.contains(clip.creator)
                ? _following.remove(clip.creator)
                : _following.add(clip.creator);
          }),
        );
      },
    );
  }
}

class _ClipPage extends StatelessWidget {
  const _ClipPage({
    required this.clip,
    required this.isLiked,
    required this.isFollowing,
    required this.onToggleLike,
    required this.onToggleFollow,
  });

  final SocialClip clip;
  final bool isLiked;
  final bool isFollowing;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleFollow;

  String get _likeCount {
    final count = clip.likes + (isLiked ? 1 : 0);
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  String get _commentCount {
    if (clip.comments >= 1000)
      return '${(clip.comments / 1000).toStringAsFixed(1)}K';
    return '${clip.comments}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tap-to-like, like every short-form feed.
      onTap: onToggleLike,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed clip art.
          Image.asset(
            clip.clipAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => Container(color: PhlioColors.surface),
          ),
          // Bottom scrim so the overlay text stays readable.
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom-left: creator + follow, title, music ticker.
          Positioned(
            left: PhlioSpacing.lg,
            right: 88,
            bottom: PhlioSpacing.xl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      // Creator profile from the clip's avatar/name.
                      onTap: () => context.push('/creator/${clip.creator}'),
                      child: ClipOval(
                        child: Image.asset(
                          clip.avatarAsset,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (_, __, ___) => const CircleAvatar(
                            radius: 19,
                            backgroundColor: PhlioColors.surfaceElevated,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: PhlioSpacing.sm),
                    GestureDetector(
                      onTap: () => context.push('/creator/${clip.creator}'),
                      child: Text(
                        clip.creator,
                        style:
                            PhlioTypography.bodyStrong.copyWith(fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: PhlioSpacing.md),
                    GestureDetector(
                      onTap: onToggleFollow,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isFollowing
                              ? Colors.white.withValues(alpha: 0.14)
                              : PhlioColors.brandOrange,
                          borderRadius: BorderRadius.circular(999),
                          border: isFollowing
                              ? Border.all(color: Colors.white24)
                              : null,
                        ),
                        child: Text(
                          isFollowing ? 'Following' : 'Follow',
                          style: PhlioTypography.label.copyWith(
                            color: isFollowing
                                ? Colors.white
                                : PhlioColors.textOnBrand,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PhlioSpacing.md),
                Text(
                  clip.title,
                  style:
                      PhlioTypography.bodyLarge.copyWith(color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: PhlioSpacing.sm),
                Row(
                  children: [
                    const Icon(Icons.music_note_rounded,
                        size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        clip.song,
                        style: PhlioTypography.caption
                            .copyWith(color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right action rail: like, comment, share, more.
          Positioned(
            right: PhlioSpacing.md,
            bottom: PhlioSpacing.xl,
            child: Column(
              children: [
                _railButton(
                  icon: isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  label: _likeCount,
                  color: isLiked ? PhlioColors.danger : Colors.white,
                  onTap: onToggleLike,
                ),
                _railButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: _commentCount,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Clip comments are coming soon.')),
                  ),
                ),
                _railButton(
                  icon: Icons.reply_rounded,
                  label: 'Share',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sharing is coming soon.')),
                  ),
                ),
                _railButton(
                  icon: Icons.more_vert_rounded,
                  label: '',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('More options are coming soon.')),
                  ),
                ),
              ],
            ),
          ),
          // Playback progress bar (decorative until real playback lands).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: 0.35,
              minHeight: 2.5,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _railButton({
    required IconData icon,
    required String label,
    Color color = Colors.white,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: PhlioSpacing.lg),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, size: 30, color: color, shadows: const [
              Shadow(color: Colors.black45, blurRadius: 8),
            ]),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: PhlioTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
