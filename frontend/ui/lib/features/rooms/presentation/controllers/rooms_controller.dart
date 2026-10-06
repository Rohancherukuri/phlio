// Room discovery state management (Riverpod).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
// import '../../../../core/result/result.dart';
import '../../domain/entities/room_entity.dart';
import '../../domain/repositories/rooms_repository.dart';
import '../../domain/usecases/discover_rooms_usecase.dart';
import '../../domain/usecases/join_room_usecase.dart';

final roomsRepositoryProvider =
    Provider<RoomsRepository>((ref) => getIt<RoomsRepository>());

/// `null` category means "all rooms" (the reference UI's "Discover" tab
/// with no filter applied).
final selectedRoomCategoryProvider =
    StateProvider<RoomCategory?>((ref) => null);

final discoverRoomsProvider =
    FutureProvider.autoDispose<List<RoomEntity>>((ref) async {
  final category = ref.watch(selectedRoomCategoryProvider);
  final repository = ref.watch(roomsRepositoryProvider);
  final useCase = DiscoverRoomsUseCase(repository);
  final result = await useCase(category: category);
  return result.when(
      success: (page) => page.items, failure: (failure) => throw failure);
});

final myRoomsProvider =
    FutureProvider.autoDispose<List<RoomEntity>>((ref) async {
  final repository = ref.watch(roomsRepositoryProvider);
  final result = await repository.myRooms();
  return result.when(
      success: (rooms) => rooms, failure: (failure) => throw failure);
});

final joinRoomProvider = Provider<JoinRoomUseCase>(
    (ref) => JoinRoomUseCase(ref.watch(roomsRepositoryProvider)));

final roomsDirectoryProvider =
    FutureProvider.autoDispose<List<RoomEntity>>((ref) async {
  final repository = ref.watch(roomsRepositoryProvider);
  final rooms = <RoomEntity>[];
  String? cursor;
  do {
    final result = await repository.discover(cursor: cursor);
    final page =
        result.when(success: (value) => value, failure: (error) => throw error);
    rooms.addAll(page.items);
    if (!page.hasMore || page.nextCursor == cursor) break;
    cursor = page.nextCursor;
  } while (cursor != null);
  return rooms;
});
