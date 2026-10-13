import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../../shared/content/social_comments_sheet.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import 'creator_follow_button.dart';

/// Portrait watch page: pinned picture, compact actions, and the same rich
/// comment list/composer that Clips presents as a modal.
class SocialWatchView extends ConsumerStatefulWidget {
  const SocialWatchView(
      {required this.video,
      required this.picture,
      required this.onSettings,
      required this.onShare,
      required this.onComments,
      required this.onProfile,
      super.key});
  final PlayableVideo video;
  final Widget picture;
  final VoidCallback onSettings, onShare, onComments;
  final void Function(String) onProfile;
  @override
  ConsumerState<SocialWatchView> createState() => _SocialWatchViewState();
}

class _SocialWatchViewState extends ConsumerState<SocialWatchView> {
  bool busy = false;
  String get path => 'social/${widget.video.contentId ?? widget.video.id}';
  Future<void> action(String verb) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await getIt<ApiClient>()
          .dio
          .put('/content/$path/${verb == 'like' ? 'like' : 'actions/$verb'}');
      ref.invalidate(engagementProvider(path));
      ref.invalidate(contentLibraryProvider);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update. Try again.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(videoPlaybackProvider);
    final data = ref.watch(engagementProvider(path)).valueOrNull;
    final comments = ref.watch(
        socialCommentsProvider(widget.video.contentId ?? widget.video.id));
    final p = c.player;
    final ready = p?.value.isInitialized == true;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    String time(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    Widget button(IconData icon, String label, VoidCallback tap) => IconButton(
        tooltip: label, onPressed: tap, icon: Icon(icon, color: Colors.white));
    return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: LayoutBuilder(builder: (context, bounds) {
          final pictureHeight =
              (bounds.maxWidth * 9 / 16).clamp(0.0, bounds.maxHeight * .38);
          return Column(children: [
            SizedBox(
                height: pictureHeight,
                child: Stack(fit: StackFit.expand, children: [
                  widget.picture,
                  const IgnorePointer(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                        Colors.black45,
                        Colors.transparent,
                        Colors.black54
                      ])))),
                  Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Row(children: [
                        button(Icons.keyboard_arrow_down, 'Minimize player',
                            () => c.setMode(SocialPlayerMode.floating)),
                        const Spacer(),
                        button(Icons.settings_outlined, 'Playback settings',
                            widget.onSettings),
                        button(Icons.close, 'Close player', c.close),
                      ])),
                  if (ready)
                    Center(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                      button(
                          Icons.replay_10,
                          'Back 10 seconds',
                          () => c.seek(
                              p!.value.position - const Duration(seconds: 10))),
                      button(
                          p!.value.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          'Play or pause',
                          c.toggle),
                      button(
                          Icons.forward_10,
                          'Forward 10 seconds',
                          () => c.seek(
                              p.value.position + const Duration(seconds: 10))),
                    ])),
                  if (ready)
                    Positioned(
                        left: 12,
                        right: 12,
                        bottom: 0,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Row(children: [
                            Text(
                                '${time(p!.value.position)} / ${time(p.value.duration)}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                            const Spacer(),
                            button(
                                Icons.picture_in_picture_alt,
                                'Floating player',
                                () => c.setMode(SocialPlayerMode.floating)),
                            button(Icons.fullscreen, 'Fullscreen',
                                () => c.setMode(SocialPlayerMode.fullscreen))
                          ]),
                          Slider(
                              min: 0,
                              max: p.value.duration.inMilliseconds
                                  .toDouble()
                                  .clamp(1, double.infinity),
                              value: p.value.position.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                      0,
                                      p.value.duration.inMilliseconds
                                          .toDouble()),
                              onChanged: (value) => c
                                  .seek(Duration(milliseconds: value.round()))),
                        ])),
                  if (!ready)
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: Row(children: [
                          button(
                              Icons.picture_in_picture_alt,
                              'Floating player',
                              () => c.setMode(SocialPlayerMode.floating)),
                          button(Icons.fullscreen, 'Fullscreen',
                              () => c.setMode(SocialPlayerMode.fullscreen)),
                        ])),
                ])),
            if (keyboard == 0)
              ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: bounds.maxHeight * .27),
                  child: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.video.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700)),
                                Row(children: [
                                  Expanded(
                                      child: InkWell(
                                          onTap: () => widget
                                              .onProfile(widget.video.creator),
                                          child: Text(
                                              '@${widget.video.creator} · ${formatEngagementCount(data?['views_count'] as num? ?? 0)} views',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF858D9E))))),
                                  CreatorFollowButton(
                                      creator: widget.video.creator)
                                ]),
                                Wrap(spacing: 4, children: [
                                  TextButton.icon(
                                      onPressed:
                                          busy ? null : () => action('like'),
                                      icon: Icon(
                                          data?['liked_by_me'] == true
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          size: 20),
                                      label: Text(
                                          '${formatEngagementCount(data?['count'] as num? ?? 0)} likes')),
                                  TextButton.icon(
                                      onPressed: widget.onComments,
                                      icon: const Icon(
                                          Icons.chat_bubble_outline,
                                          size: 20),
                                      label: Text(
                                          '${comments.valueOrNull?.length ?? 0} comments')),
                                  TextButton.icon(
                                      onPressed: widget.onShare,
                                      icon:
                                          const Icon(Icons.ios_share, size: 20),
                                      label: const Text('Share')),
                                  TextButton.icon(
                                      onPressed:
                                          busy ? null : () => action('saved'),
                                      icon: Icon(
                                          data?['saved_by_me'] == true
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          size: 20),
                                      label: Text(data?['saved_by_me'] == true
                                          ? 'Saved'
                                          : 'Save')),
                                ]),
                              ])))),
            Expanded(
                child: SocialCommentsSheet(
                    key: ValueKey(widget.video.id),
                    contentId: widget.video.contentId ?? widget.video.id,
                    embedded: true,
                    onProfileTap: widget.onProfile)),
          ]);
        }));
  }
}
