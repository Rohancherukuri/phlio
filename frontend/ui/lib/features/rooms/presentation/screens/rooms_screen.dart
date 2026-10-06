// Rooms Home hosts friends and search; conversations use the responsive room drawer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../domain/entities/room_entity.dart';
import '../../domain/repositories/rooms_repository.dart';
import '../controllers/room_chat_controller.dart';
import '../controllers/rooms_controller.dart';
import '../widgets/chat_composer.dart';
import '../widgets/message_attachments.dart';
import '../widgets/rooms_layout.dart';
import '../widgets/direct_messages_panel.dart';
import '../widgets/rooms_home.dart';

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  String? _activeRoomId;
  double _sidebarWidth = 320;

  @override
  Widget build(BuildContext context) {
    if (_activeRoomId != null) {
      return Scaffold(
          body: SafeArea(
              bottom: false,
              child: _RoomsTwoPane(
                mine: false,
                initialRoomId: _activeRoomId,
                onGoHome: () => setState(() => _activeRoomId = null),
                sidebarWidth: _sidebarWidth,
                onSidebarWidthChanged: (width) =>
                    setState(() => _sidebarWidth = width),
              )));
    }
    return Scaffold(
        body: RoomsHome(
            onSelectRoom: (room) => setState(() => _activeRoomId = room.id)));
  }
}

class _RoomsTwoPane extends ConsumerStatefulWidget {
  const _RoomsTwoPane({
    required this.mine,
    this.initialRoomId,
    this.onGoHome,
    required this.sidebarWidth,
    required this.onSidebarWidthChanged,
  });

  final bool mine;
  final String? initialRoomId;
  final VoidCallback? onGoHome;
  final double sidebarWidth;
  final ValueChanged<double> onSidebarWidthChanged;

  @override
  ConsumerState<_RoomsTwoPane> createState() => _RoomsTwoPaneState();
}

class _RoomsTwoPaneState extends ConsumerState<_RoomsTwoPane> {
  String? _selectedRoomId;
  @override
  void initState() {
    super.initState();
    _selectedRoomId = widget.initialRoomId;
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync =
        ref.watch(widget.mine ? myRoomsProvider : discoverRoomsProvider);

    return roomsAsync.when(
      loading: () => const PhlioLoadingIndicator(),
      error: (error, _) => PhlioErrorView(
        failure: error is Failure ? error : const Failure.unknown(),
        onRetry: () => ref
            .invalidate(widget.mine ? myRoomsProvider : discoverRoomsProvider),
      ),
      data: (rooms) {
        if (rooms.isEmpty) {
          return _emptyState();
        }
        final selectedId = (_selectedRoomId != null &&
                rooms.any((r) => r.id == _selectedRoomId))
            ? _selectedRoomId!
            : rooms.first.id;
        final selectedRoom = rooms.firstWhere((r) => r.id == selectedId);

        return RoomsLayout(
          composer:
              _RoomComposer(key: ValueKey(selectedRoom.id), room: selectedRoom),
          sidebarWidth: widget.sidebarWidth,
          onSidebarWidthChanged: widget.onSidebarWidthChanged,
          sidebarBuilder: (close) => _sidebar(rooms, selectedRoom.id, close),
          chatBuilder: (open) => _RoomChatPane(
            key: ValueKey(selectedRoom.id),
            room: selectedRoom,
            onOpenRooms: open,
            onGoHome: widget.onGoHome,
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PhlioFox(size: 110, pose: PhlioFoxPose.hello),
          const SizedBox(height: PhlioSpacing.md),
          Text(
            widget.mine ? "You haven't joined any rooms yet" : 'No rooms found',
            style: PhlioTypography.title,
          ),
          const SizedBox(height: PhlioSpacing.xs),
          Text(
            widget.mine
                ? 'Browse Lobbies or create your own room.'
                : 'Check back soon.',
            style: PhlioTypography.body,
          ),
        ],
      ),
    );
  }

  Widget _sidebar(
      List<RoomEntity> rooms, String selectedId, VoidCallback close) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
          width: 60,
          child: ColoredBox(
            color: PhlioColors.roomsRail,
            child: ListView(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                children: [
                  IconButton.filled(
                      tooltip: 'Messages',
                      style: IconButton.styleFrom(
                          backgroundColor: PhlioColors.brandViolet),
                      onPressed: widget.onGoHome ??
                          () => showDirectMessagesPanel(context),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 22)),
                  const Divider(height: 28),
                  for (final room in rooms)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Tooltip(
                          message: room.name,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                                room.id == selectedId ? 14 : 22),
                            onTap: () {
                              setState(() => _selectedRoomId = room.id);
                              close();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: room.id == selectedId
                                      ? PhlioColors.brandViolet
                                      : PhlioColors.roomsInput,
                                  borderRadius: BorderRadius.circular(
                                      room.id == selectedId ? 14 : 22)),
                              child: Text(room.icon,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          )),
                    ),
                ]),
          )),
      Expanded(
          child: Container(
        decoration: const BoxDecoration(
          color: PhlioColors.roomsSidebar,
          border: Border(right: BorderSide(color: PhlioColors.borderSubtle)),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: PhlioSpacing.sm),
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text('Your hangouts', style: PhlioTypography.title)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.md),
              child: Text(
                'CHANNELS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.caption
                    .copyWith(fontSize: 10, letterSpacing: 1.4),
              ),
            ),
            const SizedBox(height: PhlioSpacing.xs),
            for (final room in rooms)
              _sidebarRow(
                emoji: room.icon,
                label: room.name,
                selected: room.id == selectedId,
                onTap: () {
                  setState(() => _selectedRoomId = room.id);
                  close();
                },
              ),
            const Divider(height: 32),
            ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: const Text('Messages'),
                onTap:
                    widget.onGoHome ?? () => showDirectMessagesPanel(context)),
          ],
        ),
      )),
    ]);
  }

  Widget _sidebarRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? iconColor,
    String? emoji,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: PhlioSpacing.xs, vertical: 2),
      child: InkWell(
        borderRadius: PhlioRadii.mdRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: PhlioSpacing.sm, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? PhlioColors.surfaceElevated : Colors.transparent,
            borderRadius: PhlioRadii.mdRadius,
          ),
          child: Row(
            children: [
              if (icon != null)
                Icon(icon,
                    size: 16, color: iconColor ?? PhlioColors.textSecondary)
              else
                Text(emoji ?? '💬', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: PhlioSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: PhlioTypography.label.copyWith(
                    color: selected
                        ? PhlioColors.textPrimary
                        : PhlioColors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Chat pane -------------------------------------------------------------------

class _RoomChatPane extends ConsumerStatefulWidget {
  const _RoomChatPane(
      {required this.room, this.onOpenRooms, this.onGoHome, super.key});

  final RoomEntity room;
  final VoidCallback? onOpenRooms;
  final VoidCallback? onGoHome;

  @override
  ConsumerState<_RoomChatPane> createState() => _RoomChatPaneState();
}

class _RoomChatPaneState extends ConsumerState<_RoomChatPane> {
  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(roomChatControllerProvider(widget.room.id));

    return ColoredBox(
      color: PhlioColors.roomsChat,
      child: Column(
        children: [
          // Channel header.
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: PhlioSpacing.md, vertical: 10),
            decoration: const BoxDecoration(
              color: PhlioColors.roomsChat,
              border:
                  Border(bottom: BorderSide(color: PhlioColors.borderSubtle)),
            ),
            child: Row(
              children: [
                if (widget.onGoHome != null && widget.onOpenRooms == null)
                  IconButton(
                      tooltip: 'Back to messages',
                      onPressed: widget.onGoHome,
                      icon: const Icon(Icons.arrow_back_rounded)),
                if (widget.onOpenRooms != null)
                  IconButton(
                    tooltip: 'Browse rooms',
                    onPressed: widget.onOpenRooms,
                    icon: const Icon(Icons.menu_rounded),
                  ),
                Text(widget.room.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: PhlioSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.room.name,
                          style: PhlioTypography.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('${widget.room.memberCount} members',
                          style: PhlioTypography.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: PhlioSpacing.sm),
                _JoinPill(
                    roomId: widget.room.id,
                    compact: MediaQuery.sizeOf(context).width < 360),
              ],
            ),
          ),
          // Thread.
          Expanded(
            child: messagesAsync.when(
              loading: () => const PhlioLoadingIndicator(),
              error: (error, _) => PhlioErrorView(
                failure: error is Failure ? error : const Failure.unknown(),
                onRetry: () =>
                    ref.invalidate(roomChatControllerProvider(widget.room.id)),
              ),
              data: (messages) => ListView.builder(
                padding: const EdgeInsets.all(PhlioSpacing.md),
                itemCount: messages.length + 1,
                itemBuilder: (context, index) {
                  // Pinned description card on top, like the reference.
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
                      child: Container(
                        padding: const EdgeInsets.all(PhlioSpacing.md),
                        decoration: BoxDecoration(
                          color:
                              PhlioColors.brandViolet.withValues(alpha: 0.12),
                          borderRadius: PhlioRadii.mdRadius,
                          border: Border.all(
                              color: PhlioColors.brandViolet
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.push_pin_rounded,
                                    size: 13, color: PhlioColors.brandLavender),
                                const SizedBox(width: 4),
                                Text('Pinned',
                                    style: PhlioTypography.caption.copyWith(
                                        color: PhlioColors.brandLavender)),
                              ],
                            ),
                            const SizedBox(height: PhlioSpacing.xxs),
                            Text(widget.room.description,
                                style: PhlioTypography.body),
                          ],
                        ),
                      ),
                    );
                  }
                  final message = messages[index - 1];
                  // Tap the avatar/name to open a direct message with the
                  // author — Discord-style.
                  void openDm() => context.push('/dm/${message.authorId}');
                  Future<void> react(String kind, String value) async {
                    final result = await ref
                        .read(
                            roomChatControllerProvider(widget.room.id).notifier)
                        .toggleReaction(
                            messageId: message.id, kind: kind, value: value);
                    if (result.isFailure && mounted) {
                      showErrorSnackBar(
                          context,
                          result.when(
                            success: (_) => const Failure.unknown(),
                            failure: (failure) => failure,
                          ));
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: openDm,
                          child:
                              PhlioAvatar(name: message.displayName, size: 28),
                        ),
                        const SizedBox(width: PhlioSpacing.sm),
                        Expanded(
                          child: GestureDetector(
                            // Long-press any message to react with Foxy.
                            onLongPress: () => showReactionPickerAndReact(
                                context,
                                onReact: react),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: PhlioSpacing.xs,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: openDm,
                                      child: Text(message.displayName,
                                          style: PhlioTypography.label.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: PhlioColors.brandLavender,
                                          )),
                                    ),
                                    Text(timeago.format(message.createdAt),
                                        style: PhlioTypography.caption
                                            .copyWith(fontSize: 10)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                if (message.text.isNotEmpty)
                                  Text(message.text,
                                      style: PhlioTypography.body),
                                // Document/image/sticker previews with the
                                // Foxy reaction overlay riding on top.
                                if (message.attachments.isNotEmpty) ...[
                                  const SizedBox(height: PhlioSpacing.xs),
                                  MessageAttachmentView(
                                    attachments: message.attachments,
                                    reactions: message.reactions,
                                    onReact: react,
                                  ),
                                ],
                                // Text-only messages show reactions inline
                                // under the text; document cards carry the
                                // overlay themselves.
                                if (message.attachments.isEmpty &&
                                    message.reactions.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  ReactionChipsRow(
                                    reactions: message.reactions,
                                    onReact: react,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomComposer extends ConsumerStatefulWidget {
  const _RoomComposer({required this.room, super.key});
  final RoomEntity room;
  @override
  ConsumerState<_RoomComposer> createState() => _RoomComposerState();
}

class _RoomComposerState extends ConsumerState<_RoomComposer> {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PhlioColors.roomsChat,
      child: SafeArea(
        top: false,
        child: ChatComposer(
          compact: true,
          surfaceColor: PhlioColors.roomsInput,
          hint: 'Message #${widget.room.slug}',
          onSendText: (text) async {
            final result = await ref
                .read(roomChatControllerProvider(widget.room.id).notifier)
                .sendMessage(text);
            if (result.isFailure) throw StateError('Message could not be sent');
          },
          onSendFiles: (files, text) async {
            final notifier =
                ref.read(roomChatControllerProvider(widget.room.id).notifier);
            // Picked files stream from disk to the server; Foxy pack
            // items (stickers/GIFs) ride as metadata-only attachments.
            final result = await notifier.sendFiles(
              text: text,
              filePaths: [
                for (final file in files)
                  if (file.path != null) file.path!,
              ],
              extraAttachments: [
                for (final file in files)
                  if (file.isPackItem)
                    OutgoingAttachment(
                      kind: file.kind,
                      name: file.name,
                      value: file.packId!,
                    ),
              ],
            );
            if (result.isFailure)
              throw StateError('Attachments could not be sent');
          },
          onSendVoice: (duration, audioPath) async {
            if (audioPath == null) return;
            final result = await ref
                .read(roomChatControllerProvider(widget.room.id).notifier)
                .sendFiles(text: '', filePaths: [audioPath]);
            if (result.isFailure)
              throw StateError('Voice note could not be sent');
          },
        ),
      ),
    );
  }
}

// -- Join pill ---------------------------------------------------------------------

/// Shows Joined when the user is a member, else a Join pill that posts the
/// join to the backend and refreshes My Rooms.
class _JoinPill extends ConsumerWidget {
  const _JoinPill({required this.roomId, this.compact = false});

  final String roomId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRooms = ref.watch(myRoomsProvider).valueOrNull ?? const [];
    final joined = myRooms.any((room) => room.id == roomId);

    return GestureDetector(
      onTap: joined
          ? null
          : () async {
              final result = await ref.read(joinRoomProvider)(roomId);
              if (!context.mounted) return;
              result.when(
                success: (_) {
                  ref.invalidate(myRoomsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Room joined — it now lives in My Rooms.')),
                  );
                },
                failure: (failure) => showErrorSnackBar(context, failure),
              );
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: joined
              ? PhlioColors.success.withValues(alpha: 0.15)
              : PhlioColors.brandViolet,
          borderRadius: BorderRadius.circular(999),
        ),
        child: compact && joined
            ? const Tooltip(
                message: 'Joined',
                child: Icon(Icons.check_rounded,
                    size: 18, color: PhlioColors.success))
            : Text(
                joined ? 'Joined' : 'Join',
                style: PhlioTypography.label.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: joined ? PhlioColors.success : Colors.white,
                ),
              ),
      ),
    );
  }
}

// -- Events empty state ------------------------------------------------------------
