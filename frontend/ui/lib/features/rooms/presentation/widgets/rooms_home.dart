import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../domain/entities/room_entity.dart';
import '../controllers/messaging_controller.dart';
import '../controllers/rooms_controller.dart';
import 'direct_messages_panel.dart';
import 'rooms_hub_panels.dart';

/// Discord-inspired mobile home: a persistent room rail and rounded inbox.
class RoomsHome extends ConsumerStatefulWidget {
  const RoomsHome({required this.onSelectRoom, super.key});
  final ValueChanged<RoomEntity> onSelectRoom;
  @override
  ConsumerState<RoomsHome> createState() => _RoomsHomeState();
}

class _RoomsHomeState extends ConsumerState<RoomsHome> {
  final String _query = '';

  void _dm(Map peer) =>
      context.push('/dm/${Uri.encodeComponent(peer['id'] as String)}');

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(myRoomsProvider);
    final conversations = ref.watch(dmConversationsProvider);
    final railWidth = MediaQuery.sizeOf(context).width < 360 ? 60.0 : 68.0;
    return ColoredBox(
        color: PhlioColors.roomsRail,
        child: SafeArea(
            bottom: false,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                  width: railWidth,
                  child: ListView(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 8),
                      children: [
                        _railButton(
                            icon: const Icon(Icons.chat_bubble_rounded,
                                color: Colors.white),
                            label: 'Messages',
                            selected: true,
                            onTap: () =>
                                ref.invalidate(dmConversationsProvider)),
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Divider(height: 24)),
                        ...rooms.when(
                            loading: () => [
                                  const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                ],
                            error: (_, __) => [
                                  _railButton(
                                      icon: const Icon(Icons.refresh),
                                      label: 'Reload rooms',
                                      onTap: () =>
                                          ref.invalidate(myRoomsProvider))
                                ],
                            data: (items) => [
                                  for (final room in items)
                                    _railButton(
                                        icon: Text(room.icon,
                                            style:
                                                const TextStyle(fontSize: 23)),
                                        label: room.name,
                                        onTap: () => widget.onSelectRoom(room))
                                ]),
                        _railButton(
                            icon: const Icon(Icons.explore_outlined,
                                color: PhlioColors.domainRooms),
                            label: 'Explore rooms',
                            onTap: () => context.go('/explore')),
                      ])),
              Expanded(
                  child: ClipRRect(
                      borderRadius:
                          const BorderRadius.only(topLeft: Radius.circular(28)),
                      child: ColoredBox(
                          color: PhlioColors.roomsSidebar,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                                    child: Text('PHLIO ROOMS',
                                        style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 1.8,
                                            color: PhlioColors.textSecondary))),
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 16),
                                    child: Text('Messages',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white))),
                                Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        10, 12, 10, 16),
                                    child: Row(children: [
                                      IconButton.filledTonal(
                                          tooltip: 'Search Rooms',
                                          onPressed: () =>
                                              showRoomsSearch(context),
                                          icon: const Icon(Icons.search)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: FilledButton.tonal(
                                              onPressed: () =>
                                                  showRoomsFriends(context),
                                              style: FilledButton.styleFrom(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 12)),
                                              child: const Text('Add Friends',
                                                  textAlign:
                                                      TextAlign.center))),
                                      const SizedBox(width: 6),
                                      IconButton.filled(
                                          tooltip: 'New message',
                                          onPressed: () =>
                                              showDirectMessagesPanel(context),
                                          style: IconButton.styleFrom(
                                              backgroundColor:
                                                  PhlioColors.brandViolet),
                                          icon: const Icon(Icons.edit_square)),
                                    ])),
                                Expanded(
                                    child: conversations.when(
                                        loading: () => const Center(
                                            child: CircularProgressIndicator()),
                                        error: (_, __) => SingleChildScrollView(
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                child: Column(children: [
                                                  const Icon(
                                                      Icons
                                                          .chat_bubble_outline_rounded,
                                                      size: 40,
                                                      color: PhlioColors
                                                          .textSecondary),
                                                  const SizedBox(height: 16),
                                                  const Text(
                                                      'Could not load your conversations.',
                                                      textAlign:
                                                          TextAlign.center),
                                                  TextButton(
                                                      onPressed: () =>
                                                          ref.invalidate(
                                                              dmConversationsProvider),
                                                      child: const Text(
                                                          'Try again')),
                                                ]))),
                                        data: _inbox)),
                              ])))),
            ])));
  }

  Widget _railButton(
          {required Widget icon,
          required String label,
          required VoidCallback onTap,
          bool selected = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Tooltip(
              message: label,
              child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(selected ? 16 : 22),
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: selected
                              ? PhlioColors.brandViolet
                              : PhlioColors.roomsSidebar,
                          borderRadius:
                              BorderRadius.circular(selected ? 16 : 22)),
                      child: icon))));

  Widget _inbox(List<Map<String, dynamic>> items) {
    final filtered = items
        .where((item) => (item['peer'] as Map)['full_name']
            .toString()
            .toLowerCase()
            .contains(_query.toLowerCase()))
        .toList();
    if (items.isEmpty)
      return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 28),
            const PhlioFox(size: 100, pose: PhlioFoxPose.hello),
            const SizedBox(height: 20),
            const Text('A little hello goes a long way.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text(
                'Message someone you know, or find your people in a room.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: PhlioColors.textSecondary, height: 1.5)),
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: () => showDirectMessagesPanel(context),
                icon: const Icon(Icons.waving_hand_outlined),
                label: const Text('Start a conversation')),
          ]));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dmConversationsProvider);
        await ref.read(dmConversationsProvider.future);
      },
      child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        if (_query.isEmpty) ...[
          SizedBox(
              height: 106 + (MediaQuery.textScalerOf(context).scale(12) - 12),
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length.clamp(0, 8),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final peer = items[i]['peer'] as Map;
                    return InkWell(
                        onTap: () => _dm(peer),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                            width: 88,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: PhlioColors.roomsInput,
                                borderRadius: BorderRadius.circular(20)),
                            child: Column(children: [
                              PhlioAvatar(
                                  profileId: peer['id'] as String,
                                  imageUrl: peer['avatar_url'] as String?,
                                  name: peer['full_name'] as String,
                                  size: 46),
                              const SizedBox(height: 8),
                              Text(
                                  (peer['full_name'] as String)
                                      .split(' ')
                                      .first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12))
                            ])));
                  })),
          const Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, 10),
              child: Text('DIRECT MESSAGES',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: PhlioColors.textSecondary))),
        ],
        if (filtered.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matching conversations.')),
        for (final item in filtered)
          Builder(builder: (context) {
            final peer = item['peer'] as Map;
            final message = item['last_message'] as Map?;
            final stamp =
                DateTime.tryParse(message?['created_at'] as String? ?? '');
            return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  onTap: () => _dm(peer),
                  leading: PhlioAvatar(
                      profileId: peer['id'] as String,
                      imageUrl: peer['avatar_url'] as String?,
                      name: peer['full_name'] as String,
                      size: 44),
                  title: Text(peer['full_name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(message?['text'] as String? ?? 'Attachment',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: PhlioColors.textSecondary)),
                  trailing: stamp == null
                      ? null
                      : Text(timeago.format(stamp, locale: 'en_short'),
                          style: const TextStyle(fontSize: 11)),
                ));
          }),
      ]),
    );
  }
}
