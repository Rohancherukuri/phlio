// Video likes summary (for cards) and the full "Details" sheet (for the
// player), shared by the Social Videos tab and Social Explore → Videos.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../../design_system/widgets/phlio_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../controllers/video_library.dart';

const _likeColor = Color(0xFFFF4F79);
final _linkPattern = RegExp(r'(https?://[^\s]+)|(#[A-Za-z0-9_]+)|(@[A-Za-z0-9_.]+)');

String _engagementPath(PlayableVideo video) =>
    'social/${video.contentId ?? video.id}';

/// Card summary: [avatar stack] ♥ 128 likes · 2h ago
/// The stack and count open the "Likes" sheet.
class VideoLikesLine extends ConsumerWidget {
  const VideoLikesLine({required this.video, super.key});
  final PlayableVideo video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = _engagementPath(video);
    final data = ref.watch(engagementProvider(path)).valueOrNull;
    final likes = (data?['count'] as num?)?.toInt() ?? 0;
    final liked = data?['liked_by_me'] == true;
    final muted = PhlioTypography.caption
        .copyWith(color: PhlioColors.textMuted, fontSize: 12.5);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: data == null ? null : () => showContentLikers(context, data, likes),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          LikersAvatarStack(path: path, size: 20),
          const SizedBox(width: 6),
          Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 15, color: liked ? _likeColor : PhlioColors.textSecondary),
          const SizedBox(width: 4),
          Text(
              data == null
                  ? '— likes'
                  : '${formatEngagementCount(likes)} ${likes == 1 ? 'like' : 'likes'}',
              style: muted.copyWith(
                  color: PhlioColors.textSecondary,
                  fontWeight: FontWeight.w600)),
          if (video.createdAt != null) ...[
            Text('  ·  ', style: muted),
            Flexible(
              child: Text(timeago.format(video.createdAt!),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Text with tappable links, highlighted #tags and @mentions.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text,
      {this.style, this.maxLines, this.onMention, super.key});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final ValueChanged<String>? onMention;
  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final base = widget.style ?? PhlioTypography.body;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _linkPattern.allMatches(widget.text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      final token = m[0]!;
      TapGestureRecognizer? tap;
      if (m[1] != null) {
        tap = TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(token),
              mode: LaunchMode.externalApplication);
      } else if (m[3] != null && widget.onMention != null) {
        tap = TapGestureRecognizer()
          ..onTap = () => widget.onMention!(token.substring(1));
      }
      if (tap != null) _recognizers.add(tap);
      spans.add(TextSpan(
          text: token,
          recognizer: tap,
          style: TextStyle(
              color: m[1] != null ? PhlioColors.brandBlue : PhlioColors.brandViolet,
              fontWeight: FontWeight.w600,
              decoration: m[1] != null ? TextDecoration.underline : null)));
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }
    return Text.rich(TextSpan(style: base, children: spans),
        maxLines: widget.maxLines,
        overflow:
            widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis);
  }
}

/// The full information sheet for a video: stats, likers, upload time,
/// description with tags and links, music, sources and attribution.
Future<void> showVideoDetails(BuildContext context, PlayableVideo video,
        {ValueChanged<String>? onProfile}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (_) => FractionallySizedBox(
          heightFactor: .85,
          child: _VideoDetails(video: video, onProfile: onProfile)),
    );

class _VideoDetails extends ConsumerWidget {
  const _VideoDetails({required this.video, this.onProfile});
  final PlayableVideo video;
  final ValueChanged<String>? onProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = _engagementPath(video);
    final data = ref.watch(engagementProvider(path)).valueOrNull;
    num stat(String key) => data?[key] as num? ?? 0;
    final likes = stat('count').toInt();
    final tags = {
      for (final m in RegExp(r'#([A-Za-z0-9_]+)')
          .allMatches('${video.title} ${video.description}'))
        m[1]!.toLowerCase()
    };
    final duration = video.durationSeconds > 0
        ? '${video.durationSeconds ~/ 60}:${(video.durationSeconds % 60).toString().padLeft(2, '0')}'
        : null;
    final links = [
      for (final source in video.sources)
        if ((source['url'] ?? source['link']) != null)
          (
            (source['title'] ?? source['label'] ?? source['name'] ??
                    source['url'] ??
                    source['link'])
                .toString(),
            (source['url'] ?? source['link']).toString()
          )
    ];
    final muted = PhlioTypography.caption.copyWith(color: PhlioColors.textMuted);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.xl, 0, PhlioSpacing.xl, PhlioSpacing.xxxl),
      children: [
        Text('Details', style: PhlioTypography.headline),
        const SizedBox(height: PhlioSpacing.lg),
        // Creator
        InkWell(
          borderRadius: PhlioRadii.mdRadius,
          onTap: onProfile == null
              ? null
              : () {
                  Navigator.pop(context);
                  onProfile!(video.creator);
                },
          child: Row(children: [
            ContentAuthorAvatar(
                author: video.creator,
                name: video.creatorName ?? video.creator,
                imageUrl: video.avatarUrl,
                size: 40),
            const SizedBox(width: PhlioSpacing.md),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(video.creatorName ?? video.creator,
                    style: PhlioTypography.bodyStrong),
                Text('@${video.creator}', style: muted),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: PhlioSpacing.lg),
        // Stats
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: PhlioSpacing.sm,
          crossAxisSpacing: PhlioSpacing.sm,
          childAspectRatio: 1.35,
          children: [
            _Stat(Icons.favorite_rounded, 'Likes', data == null ? null : likes,
                color: _likeColor),
            _Stat(Icons.bar_chart_rounded, 'Views',
                data == null ? null : stat('views_count')),
            _Stat(Icons.chat_bubble_outline_rounded, 'Comments',
                data == null ? null : stat('comments_count')),
            _Stat(PhlioIcons.send, 'Shares',
                data == null ? null : stat('shares_count')),
            _Stat(Icons.bookmark_rounded, 'Bookmarks',
                data == null ? null : stat('bookmarks_count'),
                color: PhlioColors.brandOrange),
            _Stat(Icons.repeat_rounded, 'Reposts',
                data == null ? null : stat('reposts_count'),
                color: PhlioColors.success),
          ],
        ),
        if (likes > 0) ...[
          const SizedBox(height: PhlioSpacing.md),
          InkWell(
            borderRadius: PhlioRadii.mdRadius,
            onTap: () => showContentLikers(context, data, likes),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: PhlioSpacing.xs),
              child: Row(children: [
                LikersAvatarStack(path: path, ringColor: PhlioColors.surface),
                const SizedBox(width: PhlioSpacing.sm),
                Expanded(
                  child: Text(_likedBy(data!, likes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.body),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: PhlioColors.textMuted),
              ]),
            ),
          ),
        ],
        const _Rule(),
        // Upload info
        _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Uploaded',
            value: video.createdAt == null
                ? 'Unknown'
                : '${_date(video.createdAt!)} · ${timeago.format(video.createdAt!)}'),
        if (duration != null)
          _InfoRow(
              icon: Icons.timelapse_rounded, label: 'Duration', value: duration),
        _InfoRow(
            icon: Icons.video_library_outlined,
            label: 'Type',
            value: video.kind == 'clip' ? 'Clip' : 'Video'),
        if (video.location != null)
          _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Location',
              value: video.location!),
        if (video.songTitle != null)
          _InfoRow(
              icon: Icons.music_note_rounded,
              label: 'Music',
              value: [video.songTitle, video.songArtist]
                  .whereType<String>()
                  .join(' · ')),
        const _Rule(),
        // Description
        Text('Description', style: PhlioTypography.title),
        const SizedBox(height: PhlioSpacing.sm),
        LinkifiedText(
            video.description.trim().isEmpty
                ? video.title
                : '${video.title}\n\n${video.description.trim()}',
            style: PhlioTypography.bodyLarge,
            onMention: onProfile == null
                ? null
                : (handle) {
                    Navigator.pop(context);
                    onProfile!(handle);
                  }),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: PhlioSpacing.md),
          Wrap(spacing: PhlioSpacing.sm, runSpacing: PhlioSpacing.sm, children: [
            for (final tag in tags)
              Chip(
                label: Text('#$tag'),
                visualDensity: VisualDensity.compact,
                side: const BorderSide(color: PhlioColors.border),
                labelStyle: PhlioTypography.label
                    .copyWith(color: PhlioColors.brandViolet),
              ),
          ]),
        ],
        if (links.isNotEmpty) ...[
          const _Rule(),
          Text('Links', style: PhlioTypography.title),
          const SizedBox(height: PhlioSpacing.xs),
          for (final (label, url) in links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_rounded,
                  color: PhlioColors.brandBlue),
              title: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.bodyStrong),
              subtitle: Text(url,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              trailing: const Icon(Icons.open_in_new_rounded,
                  size: 18, color: PhlioColors.textMuted),
              onTap: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
            ),
        ],
        if (video.attribution != null) ...[
          const _Rule(),
          Text('Credits', style: PhlioTypography.title),
          const SizedBox(height: PhlioSpacing.xs),
          LinkifiedText(video.attribution!, style: muted),
        ],
      ],
    );
  }
}

String _likedBy(Map data, int likes) {
  final people = [
    ...?(data['follower_avatars'] as List?),
    ...?(data['avatars'] as List?),
  ].whereType<Map>().toList();
  if (people.isEmpty) return '${formatEngagementCount(likes)} likes';
  final first = people.first['display_name'] ?? 'someone';
  final others = likes - 1;
  return others > 0
      ? 'Liked by $first and ${formatEngagementCount(others)} ${others == 1 ? 'other' : 'others'}'
      : 'Liked by $first';
}

String _date(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label, this.value,
      {this.color = PhlioColors.textSecondary});
  final IconData icon;
  final String label;
  final num? value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: PhlioColors.surfaceElevated,
            borderRadius: PhlioRadii.lgRadius),
        padding: const EdgeInsets.all(PhlioSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PhlioIcon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(value == null ? '—' : formatEngagementCount(value!),
                style: PhlioTypography.title.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text(label,
                style:
                    PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: PhlioColors.textMuted),
          const SizedBox(width: PhlioSpacing.md),
          SizedBox(
              width: 84,
              child: Text(label,
                  style: PhlioTypography.caption
                      .copyWith(color: PhlioColors.textMuted))),
          Expanded(
              child: Text(value,
                  style: PhlioTypography.body
                      .copyWith(color: PhlioColors.textPrimary))),
        ]),
      );
}

class _Rule extends StatelessWidget {
  const _Rule();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: PhlioSpacing.lg),
        child: Divider(height: 1, color: PhlioColors.borderSubtle),
      );
}
