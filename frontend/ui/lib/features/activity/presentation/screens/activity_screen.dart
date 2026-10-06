// Activity — the cross-domain notification feed, opened from the home
// screen's bell. Items arrive from Phlio Book/Pay/Social/Agent: bookings
// confirmed, payments received, plan ideas. The feed defaults to the
// current platform's slice (switch platforms via the tray to see other
// slices) with an "All" chip to see everything. Foxy anchors the empty
// state so a fresh account feels greeted rather than broken.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:go_router/go_router.dart';

import '../../../../app/platform/phlio_platform.dart';
import '../../../../app/shell/platform_home_screen.dart' show switchPlatform;
import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/entities/activity_entity.dart';
import '../controllers/activity_controller.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();

  /// Which activity kinds belong to the given platform's slice of the feed.
  static List<String> kindsFor(PhlioPlatform platform) => switch (platform) {
        PhlioPlatform.social => ['social', 'rooms'],
        PhlioPlatform.rooms => ['rooms'],
        PhlioPlatform.shop => ['shop'],
        PhlioPlatform.book => ['book'],
        PhlioPlatform.pay => ['pay'],
        PhlioPlatform.agent => ['agent'],
        _ => [], // stream/news: no activity yet — default to everything
      };

  static Color kindColor(String kind) => switch (kind) {
        'book' => PhlioColors.domainBook,
        'pay' => PhlioColors.success,
        'social' => PhlioColors.domainSocial,
        'rooms' => PhlioColors.domainRooms,
        'shop' => PhlioColors.domainShop,
        'agent' => PhlioColors.brandOrange,
        _ => PhlioColors.info,
      };

  static void handleTap(BuildContext context, ActivityItemEntity item) {
    final matches = PhlioPlatform.values.where((p) => p.name == item.kind).toList();
    if (matches.isEmpty || !matches.first.isAvailable) return;
    switchPlatform(context, matches.first);
    context.go('/home');
  }
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  /// null = All kinds; otherwise a kind string ('book', 'pay', ...).
  /// Defaults to the current platform's slice on first open.
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(currentPlatformProvider);
    final feedAsync = ref.watch(activityFeedProvider);
    final hasUnread = feedAsync.valueOrNull?.any((item) => !item.isRead) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => ref.read(activityFeedProvider.notifier).markAllRead(),
              child: Text(
                'Mark all read',
                style: PhlioTypography.label.copyWith(color: PhlioColors.brandOrange),
              ),
            ),
        ],
      ),
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PhlioErrorView(
          failure: error is Failure ? error : const Failure.unknown(),
          onRetry: () => ref.invalidate(activityFeedProvider),
        ),
        data: (items) {
          final kinds = items.map((i) => i.kind).toSet().toList();
          final defaultKinds = ActivityScreen.kindsFor(platform);
          final effectiveFilter =
              _filter ?? (defaultKinds.length == 1 ? defaultKinds.first : null);
          final filtered = effectiveFilter == null
              ? items
              : items.where((item) => item.kind == effectiveFilter).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PhlioFox(size: 120, pose: PhlioFoxPose.sleepy),
                  const SizedBox(height: PhlioSpacing.lg),
                  Text('All quiet for now', style: PhlioTypography.title),
                  const SizedBox(height: PhlioSpacing.xs),
                  Text(
                    'Bookings, payments and plan ideas\nwill land here.',
                    textAlign: TextAlign.center,
                    style: PhlioTypography.body,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(activityFeedProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.lg, PhlioSpacing.xxl,
              ),
              itemCount: filtered.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _FilterChipRow(
                    kinds: kinds,
                    selected: effectiveFilter,
                    onSelected: (kind) => setState(() => _filter = kind),
                  );
                }
                final item = filtered[index - 1];
                return _ActivityTile(
                  item: item,
                  accent: ActivityScreen.kindColor(item.kind),
                  onTap: () => ActivityScreen.handleTap(context, item),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.kinds,
    required this.selected,
    required this.onSelected,
  });

  final List<String> kinds;
  final String? selected;
  final ValueChanged<String?> onSelected;

  static const _kindLabels = {
    'book': 'Book',
    'pay': 'Pay',
    'social': 'Social',
    'rooms': 'Rooms',
    'shop': 'Shop',
    'agent': 'Agent',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          PhlioChipButton(
            label: 'All',
            selected: selected == null,
            onPressed: () => onSelected(null),
          ),
          const SizedBox(width: PhlioSpacing.sm),
          for (final kind in kinds) ...[
            PhlioChipButton(
              label: _kindLabels[kind] ?? kind,
              selected: selected == kind,
              onPressed: () => onSelected(kind),
            ),
            const SizedBox(width: PhlioSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item, required this.accent, required this.onTap});

  final ActivityItemEntity item;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.sm),
      child: PhlioCard(
        onTap: onTap,
        padding: const EdgeInsets.all(PhlioSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Text(item.icon, style: const TextStyle(fontSize: 20)),
                ),
                if (!item.isRead)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: PhlioColors.brandOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: PhlioColors.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: PhlioSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: item.isRead
                              ? PhlioTypography.bodyStrong
                                  .copyWith(color: PhlioColors.textSecondary)
                              : PhlioTypography.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(timeago.format(item.createdAt), style: PhlioTypography.caption),
                    ],
                  ),
                  const SizedBox(height: PhlioSpacing.xxs),
                  Text(
                    item.body,
                    style: PhlioTypography.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
