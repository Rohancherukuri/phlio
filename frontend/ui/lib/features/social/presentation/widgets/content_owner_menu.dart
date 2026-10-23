import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/widgets/profile_posts.dart';
import '../controllers/feed_controller.dart';
import '../controllers/video_library.dart';
import '../controllers/video_playback_controller.dart';
import '../../../../shared/content/content_surface.dart';
import 'social_explore_videos_view.dart';

class ContentOwnerMenu extends ConsumerWidget {
  const ContentOwnerMenu(
      {super.key,
      required this.id,
      required this.owner,
      required this.text,
      this.onComments,
      this.onShare,
      this.video = false});
  final String id, owner, text;
  final bool video;
  final VoidCallback? onComments, onShare;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final own = user != null && (user.id == owner || user.username == owner);
    if (!own && onComments == null && onShare == null)
      return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: onComments != null ? 'Video options' : 'Edit or delete',
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => [
        if (onComments != null)
          const PopupMenuItem(value: 'comments', child: Text('Comments')),
        if (onShare != null)
          const PopupMenuItem(value: 'share', child: Text('Share')),
        if (own) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (own) const PopupMenuItem(value: 'delete', child: Text('Delete'))
      ],
      onSelected: (action) async {
        if (action == 'comments') {
          onComments?.call();
          return;
        }
        if (action == 'share') {
          onShare?.call();
          return;
        }
        await editOrDeleteContent(context, ref,
            action: action, id: id, text: text, video: video);
      },
    );
  }
}

/// Owner actions shared by the post menu and the video options menu:
/// `action` is 'edit' or 'delete'.
Future<void> editOrDeleteContent(BuildContext context, WidgetRef ref,
    {required String action,
    required String id,
    required String text,
    bool video = false}) async {
    final controller = TextEditingController(text: text);
    final result = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text(action == 'edit'
                  ? 'Edit ${video ? 'title' : 'post'}'
                  : 'Delete content?'),
              content: action == 'edit'
                  ? TextField(
                      controller: controller,
                      maxLength: video ? 160 : 2000,
                      maxLines: video ? 3 : 6,
                      autofocus: true)
                  : const Text(
                      'This will remove it from your profile and feeds.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (action == 'delete' ||
                          controller.text.trim().isNotEmpty)
                        Navigator.pop(
                            dialog,
                            action == 'delete'
                                ? 'delete'
                                : controller.text.trim());
                    },
                    child: Text(action == 'edit' ? 'Save' : 'Delete'))
              ],
            ));
    // Wait for the closing dialog transition before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (result == null || !context.mounted) return;
    try {
      final dio = getIt<ApiClient>().dio;
      if (action == 'delete') {
        await dio.delete('/social/manage/$id');
      } else {
        await dio.patch('/social/manage/$id', data: {'text': result});
      }
      ref.invalidate(feedControllerProvider);
      ref.invalidate(socialVideoCatalogProvider);
      ref.invalidate(explorePostsProvider);
      ref.invalidate(profilePostsProvider);
      ref.invalidate(publicProfileProvider);
      ref.invalidate(contentProvider('social/$id'));
      if (video) ref.read(videoPlaybackProvider).close();
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not update content. Please try again.')));
    }
}
