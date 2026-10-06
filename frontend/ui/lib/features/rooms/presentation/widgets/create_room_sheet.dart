import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/colors.dart';
import '../../domain/entities/room_entity.dart';
import '../controllers/rooms_controller.dart';

Future<void> showCreateRoomSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.roomsSidebar,
      builder: (_) => const _CreateRoomSheet(),
    );

class _CreateRoomSheet extends ConsumerStatefulWidget {
  const _CreateRoomSheet();
  @override
  ConsumerState<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends ConsumerState<_CreateRoomSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  RoomCategory _category = RoomCategory.localNearby;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref.read(roomsRepositoryProvider).createRoom(
          name: _name.text.trim(),
          description: _description.text.trim(),
          category: _category,
          icon: _category.emoji,
        );
    if (!mounted) return;
    result.when(
      success: (_) {
        ref.invalidate(myRoomsProvider);
        ref.invalidate(discoverRoomsProvider);
        ref.invalidate(roomsDirectoryProvider);
        Navigator.of(context).pop();
      },
      failure: (_) => setState(() {
        _saving = false;
        _error = 'Could not create this room. Please try again.';
      }),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 8, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Create a room',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('A place for your people and your conversations.'),
                  const SizedBox(height: 24),
                  TextFormField(
                      controller: _name,
                      maxLength: 80,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                          labelText: 'Room name', hintText: 'Weekend hangout'),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Use at least two characters.'
                          : null),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _description,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 4,
                      enabled: !_saving,
                      decoration:
                          const InputDecoration(labelText: 'About this room')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RoomCategory>(
                    value: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Community'),
                    items: [
                      for (final c in RoomCategory.values)
                        DropdownMenuItem(
                            value: c,
                            child: Text('${c.emoji}  ${c.label}',
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged:
                        _saving ? null : (c) => setState(() => _category = c!),
                  ),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: const TextStyle(color: PhlioColors.danger))),
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: _saving ? null : _create,
                      child: Text(_saving ? 'Creating…' : 'Create room')),
                ],
              )),
        ),
      );
}
