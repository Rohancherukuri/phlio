import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../domain/entities/room_entity.dart';
import '../controllers/rooms_controller.dart';
import '../widgets/rooms_discord.dart';
import 'rooms_screen.dart';

/// Explore communities, laid out like Discord's server discovery: the same
/// rail as the Rooms home, then a rounded "Communities" sheet with category
/// chips and banner cards (icon, about, active/members, Preview).
class RoomsExploreScreen extends ConsumerStatefulWidget {
  const RoomsExploreScreen({super.key});
  @override
  ConsumerState<RoomsExploreScreen> createState() => _RoomsExploreScreenState();
}

class _RoomsExploreScreenState extends ConsumerState<RoomsExploreScreen> {
  String _query = '';
  bool _searching = false;
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
          ref.invalidate(roomsDirectoryProvider);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Joined ${room.name}')));
        },
        failure: (error) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message))));
  }

  void _open(RoomEntity room) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoomChannelScreen(roomId: room.id)));

  void _more(RoomEntity room, bool joined) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: PhlioColors.roomsSidebar,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  RoomAvatar(room: room, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PhlioTypography.title
                                .copyWith(fontWeight: FontWeight.w800)),
                        Text(room.category.label,
                            style: PhlioTypography.caption),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                if (!joined)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const RoomGlyph('plus',
                        color: PhlioColors.textPrimary),
                    title: const Text('Join community'),
                    onTap: () {
                      Navigator.pop(sheet);
                      _join(room);
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const RoomGlyph('hash', color: PhlioColors.textPrimary),
                  title: Text(joined ? 'Open #${room.slug}' : 'Preview'),
                  onTap: () {
                    Navigator.pop(sheet);
                    _open(room);
                  },
                ),
                if ((room.credit ?? '').isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('Artwork', style: PhlioTypography.caption),
                  const SizedBox(height: 4),
                  Text(room.credit!,
                      style: PhlioTypography.caption
                          .copyWith(color: PhlioColors.textSecondary)),
                ],
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(roomsDirectoryProvider);
    final memberships = ref.watch(myRoomsProvider);
    final mine = memberships.valueOrNull ?? const <RoomEntity>[];
    final joined = mine.map((room) => room.id).toSet();
    return Scaffold(
        backgroundColor: PhlioColors.roomsRail,
        body: SafeArea(
            bottom: false,
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ServerRail(
                    rooms: mine,
                    loading: memberships.isLoading && !memberships.hasValue,
                    section: RailSection.explore,
                    onSelect: _open,
                    onMessages: () => context.go('/home'),
                    onExplore: () {
                      ref.invalidate(roomsDirectoryProvider);
                      setState(() => _category = null);
                    },
                  ),
                  Expanded(
                      child: RailPanel(
                          title: 'Communities',
                          actions: [
                            RoomIconButton(_searching ? 'close' : 'search',
                                tooltip: _searching ? 'Close search' : 'Search',
                                color: PhlioColors.textPrimary,
                                onTap: () => setState(() {
                                      _searching = !_searching;
                                      if (!_searching) _query = '';
                                    })),
                          ],
                          child: directory.when(
                              loading: () => const Center(
                                  child: CircularProgressIndicator()),
                              error: (_, __) => Center(
                                  child: TextButton(
                                      onPressed: () => ref
                                          .invalidate(roomsDirectoryProvider),
                                      child: const Text(
                                          'Could not load communities. Retry'))),
                              data: (all) => _list(all, joined)))),
                ])));
  }

  Widget _list(List<RoomEntity> all, Set<String> joined) {
    // De-duplicate (the directory pages by member count) and keep public.
    final seen = <String>{};
    final rooms = [
      for (final room in all)
        if (!room.isPrivate && seen.add(room.id)) room
    ];
    final categories = [
      for (final category in RoomCategory.values)
        if (rooms.any((r) => r.category == category)) category
    ];
    final visible = rooms
        .where((room) =>
            (_category == null || room.category == _category) &&
            '${room.name} ${room.description} ${room.category.label}'
                .toLowerCase()
                .contains(_query))
        .toList()
      ..sort((a, b) => b.memberCount.compareTo(a.memberCount));

    Widget card(RoomEntity room) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ContentSurface(
            platform: 'rooms',
            contentId: room.id,
            child: CommunityCard(
              room: room,
              joined: joined.contains(room.id),
              onPreview: () => _open(room),
              onMore: () => _more(room, joined.contains(room.id)),
            ),
          ),
        );

    final grouped = _category == null && _query.isEmpty;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(roomsDirectoryProvider);
        ref.invalidate(myRoomsProvider);
        await ref.read(roomsDirectoryProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                    color: PhlioColors.roomsInput,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const SizedBox(width: 12),
                  const RoomGlyph('search', size: 18),
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) =>
                          setState(() => _query = value.toLowerCase().trim()),
                      style: PhlioTypography.body
                          .copyWith(color: PhlioColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search communities',
                        hintStyle: PhlioTypography.body
                            .copyWith(color: PhlioColors.textMuted),
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          // Category chips.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip('All', _category == null,
                    () => setState(() => _category = null)),
                for (final category in categories)
                  _chip(category.label, _category == category,
                      () => setState(() => _category = category)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Text('No communities match yet. Try another interest.',
                    textAlign: TextAlign.center)),
          if (grouped)
            for (final category in categories) ...[
              _heading(category.label),
              for (final room in visible.where((r) => r.category == category))
                card(room),
            ]
          else
            for (final room in visible) card(room),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Text(text,
            style: PhlioTypography.title
                .copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? PhlioColors.textPrimary : PhlioColors.roomsInput,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(label,
                    style: PhlioTypography.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? PhlioColors.roomsRail
                            : PhlioColors.textSecondary)),
              ),
            ),
          ),
        ),
      );
}
