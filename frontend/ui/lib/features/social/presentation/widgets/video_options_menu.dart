// The ⋮ options button that sits inside a video thumbnail (top-right) and
// its menu: cast, queue, Watch later, playlist, share, not interested,
// don't recommend creator and report — plus Edit/Delete for the owner.

import 'package:flutter/material.dart';
import '../../../../design_system/widgets/phlio_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../../shared/content/playlists_screen.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import 'content_owner_menu.dart';

enum _VideoAction {
  cast,
  playNext,
  playLast,
  watchLater,
  playlist,
  share,
  notInterested,
  hideCreator,
  report,
  edit,
  delete,
}

class VideoOptionsButton extends ConsumerWidget {
  const VideoOptionsButton({required this.video, super.key});
  final PlayableVideo video;

  String get _ref => video.contentId ?? video.id;
  String get _path => 'social/$_ref';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final own = me != null &&
        (me.username == video.creator || me.id == video.creator);

    PopupMenuItem<_VideoAction> item(
            _VideoAction value, IconData icon, String label,
            {Color? color}) =>
        PopupMenuItem(
          value: value,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.xl),
          child: Row(children: [
            PhlioIcon(icon, size: 24, color: color ?? PhlioColors.textPrimary),
            const SizedBox(width: PhlioSpacing.lg),
            Expanded(
              child: Text(label,
                  style: PhlioTypography.bodyLarge
                      .copyWith(color: color ?? PhlioColors.textPrimary)),
            ),
          ]),
        );

    return PopupMenuButton<_VideoAction>(
      tooltip: 'More options',
      color: PhlioColors.surfaceElevated,
      elevation: 8,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: EdgeInsets.zero,
      itemBuilder: (_) => [
        item(_VideoAction.cast, Icons.cast_rounded, 'Play on different device'),
        item(_VideoAction.playNext, Icons.queue_play_next_rounded,
            'Play next in queue'),
        item(_VideoAction.playLast, Icons.playlist_add_rounded,
            'Play last in queue'),
        item(_VideoAction.watchLater, Icons.schedule_rounded,
            'Save to Watch later'),
        item(_VideoAction.playlist, Icons.bookmark_border_rounded,
            'Save to playlist'),
        item(_VideoAction.share, PhlioIcons.send, 'Share'),
        if (!own) ...[
          item(_VideoAction.notInterested, Icons.block_rounded,
              'Not interested'),
          item(_VideoAction.hideCreator, Icons.person_off_outlined,
              "Don't recommend creator"),
          item(_VideoAction.report, Icons.outlined_flag_rounded, 'Report'),
        ],
        if (own) ...[
          const PopupMenuDivider(),
          item(_VideoAction.edit, Icons.edit_outlined, 'Edit title'),
          item(_VideoAction.delete, Icons.delete_outline_rounded, 'Delete',
              color: PhlioColors.danger),
        ],
      ],
      onSelected: (action) => _handle(context, ref, action),
      // Frosted circle so the glyph reads on any thumbnail.
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: const Icon(Icons.more_vert_rounded,
            size: 20, color: Colors.white),
      ),
    );
  }

  Future<void> _handle(
      BuildContext context, WidgetRef ref, _VideoAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    final dio = getIt<ApiClient>().dio;
    try {
      switch (action) {
        case _VideoAction.cast:
          await _playElsewhere(context);
        case _VideoAction.playNext:
          ref.read(videoPlaybackProvider).playNext(video);
          say('Playing next');
        case _VideoAction.playLast:
          ref.read(videoPlaybackProvider).playLast(video);
          say('Added to the end of your queue');
        case _VideoAction.watchLater:
          await _saveToWatchLater(ref);
          say('Saved to Watch later');
        case _VideoAction.playlist:
          await saveContentToPlaylist(context, ref, _path);
        case _VideoAction.share:
          await showContentShare(context, _path);
        case _VideoAction.notInterested:
          await dio.put('/social/clips/$_ref/preference',
              data: {'preference': 'not_interested'});
          ref.invalidate(socialVideoCatalogProvider);
          say("Got it — we'll show fewer videos like this");
        case _VideoAction.hideCreator:
          await dio.put(
              '/social/creators/${Uri.encodeComponent(video.creator)}/preference');
          ref.invalidate(socialVideoCatalogProvider);
          say("We won't recommend @${video.creator} to you");
        case _VideoAction.report:
          final reason = await _pickReportReason(context);
          if (reason == null) return;
          await dio.post('/social/clips/$_ref/report',
              data: {'reason': reason});
          say('Thanks — our team will review this video');
        case _VideoAction.edit:
        case _VideoAction.delete:
          if (!context.mounted) return;
          await editOrDeleteContent(context, ref,
              action: action == _VideoAction.edit ? 'edit' : 'delete',
              id: video.id,
              text: video.title,
              video: true);
      }
    } catch (_) {
      say('Something went wrong. Please try again.');
    }
  }

  /// Watch later is a Social playlist; created on first use.
  Future<void> _saveToWatchLater(WidgetRef ref) async {
    final dio = getIt<ApiClient>().dio;
    final rows = ((await dio.get('/playlists',
                queryParameters: {'platform': 'social'}))
            .data as Map)['items'] as List;
    var id = rows
        .whereType<Map>()
        .firstWhere((r) => r['name'] == 'Watch later', orElse: () => const {})['id']
        as String?;
    id ??= ((await dio.post('/playlists',
                data: {'platform': 'social', 'name': 'Watch later'}))
            .data as Map)['id'] as String;
    await dio.post('/playlists/save/bookmark', data: {
      'platform': 'social',
      'ref': _ref,
      'playlist_id': id,
      'move': false,
    });
    ref.invalidate(playlistsProvider('social'));
    ref.invalidate(engagementProvider(_path));
  }

  Future<void> _playElsewhere(BuildContext context) {
    final link = 'phlio://app/shared/$_path';
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.cast_rounded),
            title: Text('Play on a different device',
                style: PhlioTypography.title),
            subtitle: const Text(
                'Casting to TVs and speakers is coming soon. Send this video '
                'to your other device and keep watching there.'),
          ),
          ListTile(
            leading: const Icon(Icons.devices_rounded),
            title: const Text('Send to another device'),
            onTap: () async {
              Navigator.pop(sheet);
              await SharePlus.instance
                  .share(ShareParams(text: link, subject: video.title));
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Copy link'),
            onTap: () async {
              Navigator.pop(sheet);
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied')));
              }
            },
          ),
          const SizedBox(height: PhlioSpacing.sm),
        ]),
      ),
    );
  }
}

Future<String?> _pickReportReason(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                PhlioSpacing.xl, 0, PhlioSpacing.xl, PhlioSpacing.sm),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Report video', style: PhlioTypography.title)),
          ),
          for (final reason in const [
            'Spam or misleading',
            'Hateful or abusive content',
            'Violent or dangerous acts',
            'Sexual content',
            'Harassment or bullying',
            'Infringes my rights',
            'Something else',
          ])
            ListTile(
              title: Text(reason),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: PhlioColors.textMuted),
              onTap: () => Navigator.pop(sheet, reason),
            ),
        ]),
      ),
    );
