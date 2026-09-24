// Rooms discovery screen — mirrors the reference "3. ROOMS" screen's
// Discover tab: category filter chips up top, then a scrollable list of
// rooms.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../domain/entities/room_entity.dart';
import '../controllers/rooms_controller.dart';
import '../widgets/room_card.dart';

class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(discoverRoomsProvider);
    final selectedCategory = ref.watch(selectedRoomCategoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Phlio Rooms', style: PhlioTypography.displayMedium)),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
              children: [
                PhlioChipButton(
                  label: 'All',
                  selected: selectedCategory == null,
                  onPressed: () => ref.read(selectedRoomCategoryProvider.notifier).state = null,
                ),
                const SizedBox(width: PhlioSpacing.sm),
                for (final category in RoomCategory.values) ...[
                  PhlioChipButton(
                    label: category.label,
                    selected: selectedCategory == category,
                    onPressed: () => ref.read(selectedRoomCategoryProvider.notifier).state = category,
                  ),
                  const SizedBox(width: PhlioSpacing.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: PhlioSpacing.md),
          Expanded(
            child: roomsAsync.when(
              loading: () => const PhlioLoadingIndicator(),
              error: (error, _) => PhlioErrorView(
                failure: error is Failure ? error : const Failure.unknown(),
                onRetry: () => ref.invalidate(discoverRoomsProvider),
              ),
              data: (rooms) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(discoverRoomsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    PhlioSpacing.lg, 0, PhlioSpacing.lg, PhlioSpacing.lg,
                  ),
                  itemCount: rooms.length,
                  separatorBuilder: (context, index) => const SizedBox(height: PhlioSpacing.md),
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return RoomCard(room: room, onTap: () => context.push('/rooms/${room.id}'));
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
