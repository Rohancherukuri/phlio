import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../design_system/colors.dart';
import '../../domain/entities/room_entity.dart';
import '../controllers/rooms_controller.dart';

class RoomsExploreScreen extends ConsumerStatefulWidget {
  const RoomsExploreScreen({super.key});
  @override
  ConsumerState<RoomsExploreScreen> createState() => _RoomsExploreScreenState();
}

class _RoomsExploreScreenState extends ConsumerState<RoomsExploreScreen> {
  int _section = 0;
  String _query = '';
  RoomCategory? _category;
  final Set<String> _joining = {};
  Future<void> _join(RoomEntity room) async {
    if (_joining.contains(room.id)) return;
    setState(() => _joining.add(room.id));
    final result = await ref.read(joinRoomProvider)(room.id);
    if (!mounted) return;
    setState(() => _joining.remove(room.id));
    result.when(
        success: (_) {
          ref.invalidate(myRoomsProvider);
          ref.invalidate(discoverRoomsProvider);
          ref.invalidate(roomsDirectoryProvider);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Joined ${room.name}')));
        },
        failure: (error) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message))));
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(roomsDirectoryProvider);
    final memberships = ref.watch(myRoomsProvider);
    final joined =
        memberships.valueOrNull?.map((room) => room.id).toSet() ?? <String>{};
    return Scaffold(
        backgroundColor: PhlioColors.roomsRail,
        body: SafeArea(
            bottom: false,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
                      child: Text('Find your people',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w800))),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Rooms, communities, and places to hang out.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: PhlioColors.textSecondary))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                          onChanged: (value) => setState(
                              () => _query = value.toLowerCase().trim()),
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Discover your next conversation'))),
                  SizedBox(
                      height:
                          58 + MediaQuery.textScalerOf(context).scale(12) - 12,
                      child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final (index, label)
                                in ['Rooms', 'Communities', 'Lobbies'].indexed)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: ChoiceChip(
                                      label: Text(label),
                                      showCheckmark: false,
                                      selected: _section == index,
                                      onSelected: (_) => setState(() {
                                            _section = index;
                                            _category = null;
                                          }))),
                          ])),
                  Expanded(
                      child: directory.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, __) => Center(
                              child: TextButton(
                                  onPressed: () =>
                                      ref.invalidate(roomsDirectoryProvider),
                                  child: const Text(
                                      'Could not load rooms. Retry'))),
                          data: (all) {
                            final rooms = all
                                .where((room) =>
                                    !room.isPrivate &&
                                    (_category == null ||
                                        room.category == _category) &&
                                    '${room.name} ${room.description} ${room.category.label}'
                                        .toLowerCase()
                                        .contains(_query))
                                .toList();
                            return RefreshIndicator(
                                onRefresh: () async {
                                  ref.invalidate(roomsDirectoryProvider);
                                  ref.invalidate(myRoomsProvider);
                                  await ref.read(roomsDirectoryProvider.future);
                                },
                                child: ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 4, 16, 24),
                                    children: [
                                      if (_section == 1 &&
                                          _category == null) ...[
                                        const Padding(
                                            padding: EdgeInsets.symmetric(
                                                vertical: 12),
                                            child: Text(
                                                'Explore by interest. Join the conversations inside each community.')),
                                        for (final category
                                            in RoomCategory.values)
                                          if (rooms.any((r) => r.category == category))
                                            Card(
                                                color: PhlioColors.roomsSidebar,
                                                child: ListTile(
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    leading: Text(category.emoji,
                                                        style: const TextStyle(
                                                            fontSize: 28)),
                                                    title: Text(category.label,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                    subtitle: Text(
                                                        '${rooms.where((r) => r.category == category).length} rooms'),
                                                    trailing:
                                                        const Icon(Icons.chevron_right),
                                                    onTap: () => setState(() => _category = category))),
                                      ] else ...[
                                        if (_category != null)
                                          Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton.icon(
                                                  onPressed: () => setState(
                                                      () => _category = null),
                                                  icon: const Icon(
                                                      Icons.arrow_back),
                                                  label:
                                                      Text(_category!.label))),
                                        if (_section == 2)
                                          const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 12),
                                              child: Text(
                                                  'Public lobbies — pick a room and join the conversation.')),
                                        for (final room in rooms)
                                          _card(room, joined.contains(room.id),
                                              memberships.isLoading),
                                      ],
                                      if (rooms.isEmpty)
                                        const Padding(
                                            padding: EdgeInsets.symmetric(
                                                vertical: 48),
                                            child: Text(
                                                'No matches yet. Try another interest or room name.',
                                                textAlign: TextAlign.center)),
                                    ]));
                          })),
                ])));
  }

  Widget _card(RoomEntity room, bool joined, bool loadingMembership) => Card(
      color: PhlioColors.roomsSidebar,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: PhlioColors.roomsInput,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(room.icon, style: const TextStyle(fontSize: 26))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(room.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)))
            ]),
            const SizedBox(height: 12),
            Text(room.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PhlioColors.textSecondary)),
            const SizedBox(height: 12),
            Text('${room.memberCount} members · ${room.category.label}',
                style: const TextStyle(
                    fontSize: 12, color: PhlioColors.textSecondary)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: joined
                      ? () =>
                          context.push('/rooms/${Uri.encodeComponent(room.id)}')
                      : _joining.contains(room.id) || loadingMembership
                          ? null
                          : () => _join(room),
                  icon: Icon(joined ? Icons.chat_bubble_outline : Icons.add),
                  label: Text(joined
                      ? 'Open room'
                      : _joining.contains(room.id)
                          ? 'Joining…'
                          : 'Join')),
              if (!joined)
                TextButton(
                    onPressed: () =>
                        context.push('/rooms/${Uri.encodeComponent(room.id)}'),
                    child: const Text('Preview')),
            ]),
          ])));
}
