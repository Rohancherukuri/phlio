import 'package:timeago/timeago.dart' as timeago;
import 'video_details_sheet.dart';
import 'content_owner_menu.dart';
import '../../../../shared/music/song_picker.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
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
  bool busy = false, choosingMedia = false;
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
          final pictureHeight = (bounds.maxWidth * 9 / 16)
              .clamp(0.0, bounds.maxHeight * (choosingMedia ? .22 : .38));
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
            if (keyboard == 0 && !choosingMedia)
              ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: bounds.maxHeight * .27),
                  child: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ContentSongBadge(kind: 'video', target: widget.video.id),
                                // Tap the title for full details: stats,
                                // likers, description, tags and links.
                                InkWell(
                                    onTap: () => showVideoDetails(
                                        context, widget.video,
                                        onProfile: widget.onProfile),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: Text(widget.video.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w700))),
                                          const Icon(
                                              Icons.expand_more_rounded,
                                              color: Color(0xFF858D9E)),
                                        ])),
                                Row(children: [
                                  ContentAuthorAvatar(
                                      author: widget.video.creator,
                                      name: widget.video.creator,
                                      imageUrl: widget.video.avatarUrl,
                                      size: 32),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: InkWell(
                                          onTap: () => widget
                                              .onProfile(widget.video.creator),
                                          child: Text(
                                              '@${widget.video.creator} · ${formatEngagementCount(data?['views_count'] as num? ?? 0)} views${widget.video.createdAt == null ? '' : ' · ${timeago.format(widget.video.createdAt!)}'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF858D9E))))),
                                  CreatorFollowButton(
                                      creator: widget.video.creator),
                                  if (widget.video.platform == 'social' && widget.video.contentId == null) ContentOwnerMenu(id: widget.video.id, owner: widget.video.creator, text: widget.video.title, video: true),
                                ]),
                                // Same engagement bar as every other
                                // Phlio surface: liker stack + like,
                                // comments, reposts, views, bookmarks and
                                // shares, each with its count.
                                Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: EngagementRow(path: path)),
                              ])))),
            Expanded(
                child: SocialCommentsSheet(
                    key: ValueKey(widget.video.id),
                    contentId: widget.video.contentId ?? widget.video.id,
                    embedded: true,
                    onPickerChanged: (value) =>
                        setState(() => choosingMedia = value),
                    onProfileTap: widget.onProfile)),
          ]);
        }));
  }
}
