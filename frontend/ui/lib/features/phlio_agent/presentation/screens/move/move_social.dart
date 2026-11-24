// Phlio Move ↔ Phlio Social.
//
//  * [ActivityPostBlock]: an activity post in the feed (route picture with
//    sport, distance / pace / time). Tapping it takes you to the Phlio Agent
//    explore tab, which asks you to open the activity there.
//  * [PendingActivityBanner]: that prompt, at the top of the Agent explore tab.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:phlio/app/config/app_config.dart';
import 'package:phlio/app/platform/phlio_platform.dart';
import 'package:phlio/app/shell/platform_home_screen.dart' show switchPlatform;
import 'package:phlio/core/network/media_cache.dart';
import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';

import 'move_activity_screen.dart';
import 'move_api.dart';

bool isActivityMedia(String url) => url.startsWith('/media/activities/');

final activityByPostProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, postId) async {
  try {
    final res = await moveDio.get('/activities/by-post/${Uri.encodeComponent(postId)}');
    return Map<String, dynamic>.from(res.data as Map);
  } catch (_) {
    return null;
  }
});

/// Go to the Agent explore tab, where a banner offers to open [a].
void openActivityFromPost(BuildContext context, WidgetRef ref, Map a) {
  HapticFeedback.selectionClick();
  final author = (a['author'] as Map?) ?? const {};
  ref.read(pendingActivityProvider.notifier).state = PendingActivity(
    id: '${a['id']}',
    name: '${author['display_name'] ?? author['username'] ?? 'Someone'}',
    title: '${a['title']}',
    imageUrl: a['image_url'] as String?,
  );
  switchPlatform(context, PhlioPlatform.agent);
  context.go('/explore');
}

class ActivityPostBlock extends ConsumerWidget {
  const ActivityPostBlock({required this.postId, required this.imageUrl, super.key});
  final String postId, imageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(activityByPostProvider(postId)).valueOrNull;
    final sport = sportOf(a?['sport'] as String?);
    return GestureDetector(
      onTap: a == null ? null : () => openActivityFromPost(context, ref, a),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: PhlioColors.surfaceInput,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 1080 / 640,
              child: Stack(fit: StackFit.expand, children: [
                phlioNetworkImage(AppConfig.mediaUrl(imageUrl),
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0C131E))),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(sport.icon, size: 14, color: moveAccent),
                      const SizedBox(width: 5),
                      Text(a == null ? 'Phlio Move' : '${a['sport_label']}',
                          style: PhlioTypography.caption.copyWith(color: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ),
            if (a != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(children: [
                  for (final (value, label) in headlineStats(a))
                    Expanded(child: MoveStat(value: value, label: label)),
                  const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class PendingActivityBanner extends ConsumerWidget {
  const PendingActivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pendingActivityProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: p == null
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: PhlioColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: moveAccent.withValues(alpha: .45)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (p.imageUrl != null)
                  AspectRatio(
                    aspectRatio: 1080 / 640,
                    child: phlioNetworkImage(AppConfig.mediaUrl(p.imageUrl!),
                        fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0C131E))),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p.name}’s activity', style: PhlioTypography.bodyStrong),
                        Text(p.title, style: PhlioTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Text('Tap the button to see the route, stats and kudos, and join the conversation.',
                            style: PhlioTypography.caption),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: () => ref.read(pendingActivityProvider.notifier).state = null,
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: moveAccent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.directions_run_rounded),
                    label: Text('View ${p.name.split(' ').first}’s activity'),
                    onPressed: () {
                      ref.read(pendingActivityProvider.notifier).state = null;
                      Navigator.of(context, rootNavigator: true)
                          .push(MaterialPageRoute<void>(builder: (_) => MoveActivityScreen(id: p.id)));
                    },
                  ),
                ),
              ]),
            ),
    );
  }
}
