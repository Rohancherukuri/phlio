// Activity feed state (Riverpod).
//
// Two plain providers: the feed itself and a "mark all read" action that
// optimistically clears unread dots locally before telling the server.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/activity_entity.dart';
import '../../domain/repositories/activity_repository.dart';

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => getIt<ActivityRepository>(),
);

final activityFeedProvider =
    AsyncNotifierProvider<ActivityFeedController, List<ActivityItemEntity>>(
  ActivityFeedController.new,
);

class ActivityFeedController extends AsyncNotifier<List<ActivityItemEntity>> {
  @override
  Future<List<ActivityItemEntity>> build() async {
    final repository = ref.read(activityRepositoryProvider);
    final result = await repository.feed();
    return result.when(success: (items) => items, failure: (failure) => throw failure);
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null) return;

    // Optimistic: clear unread flags immediately, then reconcile with a
    // fresh fetch once the server confirms.
    state = AsyncData([for (final item in current) _replacedRead(item)]);

    final repository = ref.read(activityRepositoryProvider);
    final result = await repository.markAllRead();
    if (result.isSuccess) {
      ref.invalidateSelf();
    }
  }

  ActivityItemEntity _replacedRead(ActivityItemEntity item) => ActivityItemEntity(
        id: item.id,
        kind: item.kind,
        title: item.title,
        body: item.body,
        icon: item.icon,
        refId: item.refId,
        createdAt: item.createdAt,
        isRead: true,
      );
}
