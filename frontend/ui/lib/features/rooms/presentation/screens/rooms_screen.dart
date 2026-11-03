import '../../../../shared/realtime/realtime_screen.dart';
import 'package:phlio/shared/content/content_surface.dart';
// Rooms Home hosts friends and search; conversations use the responsive room drawer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
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
import '../widgets/rooms_discord.dart';
import '../widgets/rooms_hub_panels.dart';

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
    // Discord layout: the rail runs to the top, no app bar.
    return Scaffold(
        backgroundColor: PhlioColors.roomsRail,
        body: RoomsHome(
            onSelectRoom: (room) => setState(() => _activeRoomId = room.id)));
  }
}

/// One room's channel view on its own page (opened from Explore): members
/// chat, visitors preview with a Join bar.
class RoomChannelScreen extends StatefulWidget {
  const RoomChannelScreen({required this.roomId, super.key});
  final String roomId;

  @override
  State<RoomChannelScreen> createState() => _RoomChannelScreenState();
}

class _RoomChannelScreenState extends State<RoomChannelScreen> {
  double _sidebarWidth = 320;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PhlioColors.roomsChat,
        body: SafeArea(
          bottom: false,
          child: _RoomsTwoPane(
            mine: false,
            initialRoomId: widget.roomId,
            onGoHome: () => Navigator.of(context).maybePop(),
            onExplore: () => Navigator.of(context).maybePop(),
            sidebarWidth: _sidebarWidth,
            onSidebarWidthChanged: (width) =>
                setState(() => _sidebarWidth = width),
          ),
        ),
      );
}

class _RoomsTwoPane extends ConsumerStatefulWidget {
  const _RoomsTwoPane({
    required this.mine,
    this.initialRoomId,
    this.onGoHome,
    this.onExplore,
    required this.sidebarWidth,
    required this.onSidebarWidthChanged,
  });

  final bool mine;
  final String? initialRoomId;
  final VoidCallback? onGoHome;
  final VoidCallback? onExplore;
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
    // The rail lists the rooms you're in (Discord's server list), plus the
    // room you're previewing when you aren't a member yet.
    final mineAsync = ref.watch(myRoomsProvider);
    final previewing = _selectedRoomId != null &&
        !(mineAsync.valueOrNull ?? const <RoomEntity>[])
            .any((r) => r.id == _selectedRoomId);
    final directory = previewing ? ref.watch(roomsDirectoryProvider) : null;

    if (mineAsync.isLoading && !mineAsync.hasValue ||
        (directory?.isLoading ?? false) && !(directory?.hasValue ?? false)) {
      return const PhlioLoadingIndicator();
    }
    if (mineAsync.hasError && !mineAsync.hasValue) {
      final error = mineAsync.error;
      return PhlioErrorView(
        failure: error is Failure ? error : const Failure.unknown(),
        onRetry: () => ref.invalidate(myRoomsProvider),
      );
    }
    final rooms = [...?mineAsync.valueOrNull];
    if (previewing) {
      for (final room in directory?.valueOrNull ?? const <RoomEntity>[]) {
        if (room.id == _selectedRoomId) {
          rooms.add(room);
          break;
        }
      }
    }
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
    final room = rooms.firstWhere((r) => r.id == selectedId);
    void call({required bool video}) {
      close();
      openRealtime(context,
          endpoint: '/realtime/rooms/${room.id}/join',
          title: room.name,
          rooms: true,
          video: video);
    }

    // Discord layout: the server rail, then the selected room's channels.
    // Picking another room keeps the drawer open on its channel list.
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ServerRail(
        rooms: rooms,
        selectedId: selectedId,
        onSelect: (next) => setState(() => _selectedRoomId = next.id),
        onMessages: widget.onGoHome ?? () => showDirectMessagesPanel(context),
        onExplore: widget.onExplore,
      ),
      Expanded(
        child: ChannelPanel(
          room: room,
          onOpenChat: close,
          onVoice: () => call(video: false),
          onVideo: () => call(video: true),
          onSearch: () => showRoomsSearch(context),
          onInvite: () => showRoomsFriends(context),
        ),
      ),
    ]);
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
  void _call({required bool video}) => openRealtime(context,
      endpoint: '/realtime/rooms/${widget.room.id}/join',
      title: widget.room.name,
      rooms: true,
      video: video);

  void _showPinned() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: PhlioColors.roomsSidebar,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const RoomGlyph('pin',
                      size: 18, color: PhlioColors.brandLavender),
                  const SizedBox(width: 8),
                  Text('Pinned messages', style: PhlioTypography.title),
                ]),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PhlioColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(widget.room.description,
                      style: PhlioTypography.body),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(roomChatControllerProvider(widget.room.id));
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return ColoredBox(
      color: PhlioColors.roomsChat,
      child: Column(
        children: [
          // Channel header: ☰  # channel ›        🎧  📹  📌
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              color: PhlioColors.roomsChat,
              border:
                  Border(bottom: BorderSide(color: PhlioColors.borderSubtle)),
            ),
            child: Row(
              children: [
                if (widget.onOpenRooms != null)
                  RoomIconButton('menu',
                      tooltip: 'Channels',
                      color: PhlioColors.textPrimary,
                      onTap: widget.onOpenRooms)
                else if (widget.onGoHome != null)
                  RoomIconButton('back',
                      tooltip: 'Back',
                      color: PhlioColors.textPrimary,
                      onTap: widget.onGoHome)
                else
                  const SizedBox(width: 8),
                const SizedBox(width: 2),
                const RoomGlyph('hash', size: 20, color: PhlioColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpenRooms,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.room.slug,
                            style: PhlioTypography.title.copyWith(
                                fontWeight: FontWeight.w800, fontSize: 17),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                            '${widget.room.name} · ${widget.room.memberCount} members',
                            style: PhlioTypography.caption.copyWith(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
                _JoinPill(roomId: widget.room.id, compact: narrow),
                RoomIconButton('headphones',
                    tooltip: 'Join voice', onTap: () => _call(video: false)),
                RoomIconButton('video',
                    tooltip: 'Join video', onTap: () => _call(video: true)),
                if (!narrow)
                  RoomIconButton('pin',
                      tooltip: 'Pinned messages', onTap: _showPinned),
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
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: messages.length + 1,
                itemBuilder: (context, index) {
                  // "Welcome to #channel!" opens the history.
                  if (index == 0) return ChannelWelcome(room: widget.room);
                  final message = messages[index - 1];
                  final previous = index > 1 ? messages[index - 2] : null;
                  final newDay = previous == null ||
                      !sameDay(previous.createdAt, message.createdAt);
                  // Discord groups consecutive messages from one person
                  // within a few minutes under a single name.
                  final grouped = previous != null &&
                      !newDay &&
                      previous.authorId == message.authorId &&
                      message.createdAt
                              .difference(previous.createdAt)
                              .inMinutes
                              .abs() <
                          7;
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

                  final body = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!grouped)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: GestureDetector(
                                  onTap: openDm,
                                  child: Text(message.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: PhlioTypography.label.copyWith(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: authorColor(message.authorId),
                                      )),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(discordTime(message.createdAt),
                                  style: PhlioTypography.caption.copyWith(
                                      fontSize: 11,
                                      color: PhlioColors.textMuted)),
                            ],
                          ),
                        ),
                      if (message.text.isNotEmpty)
                        SharedContentText(message.text,
                            style: PhlioTypography.body.copyWith(
                                color: PhlioColors.textPrimary, height: 1.4)),
                      // Document/image/sticker previews with the
                      // Foxy reaction overlay riding on top.
                      if (message.attachments.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        MessageAttachmentView(
                          attachments: message.attachments,
                          reactions: message.reactions,
                          onReact: react,
                        ),
                      ],
                      // Text-only messages show reactions under the text;
                      // document cards carry the overlay themselves.
                      if (message.attachments.isEmpty &&
                          message.reactions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ReactionChipsRow(
                          reactions: message.reactions,
                          onReact: react,
                        ),
                      ],
                    ],
                  );

                  final row = InkWell(
                    // Long-press any message to react with Foxy.
                    onLongPress: () =>
                        showReactionPickerAndReact(context, onReact: react),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, grouped ? 2 : 14, 16, 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 40,
                            child: grouped
                                ? null
                                : GestureDetector(
                                    onTap: openDm,
                                    child: PhlioAvatar(
                                        profileId: message.authorId,
                                        name: message.displayName,
                                        size: 40),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  );
                  if (!newDay) return row;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [DayDivider(message.createdAt.toLocal()), row],
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
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    final result = await ref.read(joinRoomProvider)(widget.room.id);
    if (!mounted) return;
    setState(() => _joining = false);
    result.when(
      success: (_) => ref.invalidate(myRoomsProvider),
      failure: (failure) => showErrorSnackBar(context, failure),
    );
  }

  /// Visitors preview the channel (as on Discord) with a Join bar in place
  /// of the composer.
  Widget _previewBar() => ColoredBox(
        color: PhlioColors.roomsSidebar,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              RoomAvatar(room: widget.room, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: "You're previewing "),
                    TextSpan(
                        text: widget.room.name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  maxLines: 2,
                  style: PhlioTypography.body
                      .copyWith(color: PhlioColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                    gradient: PhlioColors.sunsetGradient,
                    borderRadius: BorderRadius.circular(999)),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _joining ? null : _join,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: _joining
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: PhlioColors.textOnBrand))
                          : Text('Join',
                              style: PhlioTypography.label.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: PhlioColors.textOnBrand)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myRoomsProvider);
    final rooms = mine.valueOrNull;
    if (rooms != null && !rooms.any((room) => room.id == widget.room.id)) {
      return _previewBar();
    }
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
    // Members don't need a badge (as on Discord); visitors get a Join pill.
    if (joined || ref.watch(myRoomsProvider).isLoading) {
      return const SizedBox.shrink();
    }

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
