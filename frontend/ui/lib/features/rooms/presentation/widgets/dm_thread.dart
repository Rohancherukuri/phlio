import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../data/datasources/messaging_api.dart';
import '../../domain/entities/room_message_entity.dart';
import '../controllers/messaging_controller.dart';
import '../widgets/attachment_preview.dart';
import '../widgets/chat_composer.dart';
import 'chat_policy.dart';
import 'message_sticker_canvas.dart';

/// Private conversation core for the pushed DM screen: the polling history, the send/upload pipeline
/// (text, files, voice, Foxy stickers/GIFs via the composer) and
/// Long-press reactions, double-tap hearts, and editable sticker overlays.
class DmThread extends ConsumerStatefulWidget {
  const DmThread({
    required this.username,
    this.compact = false,
    this.searchQuery,
    super.key,
  });

  final String username;

  /// Profile-tab sizing: slimmer paddings and a smaller empty state.
  final bool compact;

  /// When non-empty (DM screen's search box), only matching messages show.
  final String? searchQuery;

  @override
  ConsumerState<DmThread> createState() => _DmThreadState();
}

class _DmThreadState extends ConsumerState<DmThread> {
  static const _quickEmojis = ['❤️', '😂', '😮', '😢', '🙏', '🔥'];

  final ScrollController _scroll = ScrollController();
  int _lastCount = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(
    String text, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    await ref
        .read(messagingApiProvider)
        .send(widget.username, text, attachments: attachments);
    if (!mounted) return;
    ref.invalidate(dmHistoryProvider(widget.username));
    ref.invalidate(dmConversationsProvider);
  }

  Future<void> _files(List<StagedAttachment> files, String text) async {
    final api = ref.read(messagingApiProvider);
    final paths = [
      for (final f in files)
        if (f.path != null) f.path!,
    ];
    final uploaded = paths.isEmpty
        ? <Map<String, dynamic>>[]
        : await api.upload(
            widget.username,
            paths,
            edits: [
              for (final f in files)
                if (f.path != null) f.videoEdits,
            ],
          );
    await _send(
      text,
      attachments: [
        ...uploaded,
        for (final f in files)
          if (f.isPackItem) {'kind': f.kind, 'name': f.name, 'value': f.packId},
      ],
    );
  }

  Future<void> _react(String messageId, String value) async {
    try {
      await ref
          .read(messagingApiProvider)
          .react(widget.username, messageId, 'emoji', value);
      if (!mounted) return;
      ref.invalidate(dmHistoryProvider(widget.username));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not react. Try again.')),
        );
      }
    }
  }

  // -- Instagram-style reaction bar -------------------------------------------

  Future<void> _showReactionBar(Map<String, dynamic> message, bool mine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final emoji in _quickEmojis)
                    IconButton(
                      tooltip: 'React $emoji',
                      onPressed: () => Navigator.pop(context, emoji),
                      icon: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                ],
              ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined),
                  title: const Text('Add or edit stickers'),
                  onTap: () => Navigator.pop(context, 'decorate'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action != 'decorate') {
      await _react(message['id'] as String, action);
      return;
    }
    final overlays = await editMessageStickers(
      context,
      child: _messageBody(message, mine),
      initial: _overlays(message),
    );
    if (!mounted || overlays == null) return;
    try {
      await ref
          .read(messagingApiProvider)
          .setOverlays(widget.username, message['id'] as String, overlays);
      if (mounted) ref.invalidate(dmHistoryProvider(widget.username));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save stickers. Try again.'),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _overlays(Map<String, dynamic> message) => [
        for (final v in message['overlays'] as List? ?? [])
          Map<String, dynamic>.from(v as Map),
      ];

  Widget _messageBody(Map<String, dynamic> message, bool mine) =>
      ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: 60, minWidth: double.infinity),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((message['text'] as String).isNotEmpty)
              SharedContentText(message['text'] as String,
                  style: PhlioTypography.body),
            for (final raw in message['attachments'] as List)
              _PrivateAttachment(
                key: ValueKey((raw as Map)['id']),
                data: Map<String, dynamic>.from(raw),
                mine: mine,
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final peerAsync = ref.watch(dmPeerProvider(widget.username));
    final peer = peerAsync.valueOrNull;
    final name = peer?['full_name'] as String? ?? widget.username;
    final me = ref.watch(authControllerProvider).valueOrNull?.id;
    final history = ref.watch(dmHistoryProvider(widget.username));

    return Column(
      children: [
        Expanded(
          child: history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: TextButton(
                onPressed: () =>
                    ref.invalidate(dmHistoryProvider(widget.username)),
                child: const Text('Could not load conversation. Retry'),
              ),
            ),
            data: (all) {
              final query = widget.searchQuery?.trim().toLowerCase() ?? '';
              final messages = query.isEmpty
                  ? all
                  : all
                      .where(
                        (m) =>
                            (m['text'] as String).toLowerCase().contains(query),
                      )
                      .toList();
              if (all.isEmpty) return _empty(name);
              if (messages.isEmpty) {
                return const Center(child: Text('No matching messages'));
              }
              // Keep the newest message visible as the conversation grows.
              final nearBottom =
                  !_scroll.hasClients || _scroll.position.extentAfter < 100;
              if (all.length != _lastCount && nearBottom && query.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });
              }
              _lastCount = all.length;

              return ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.all(widget.compact ? 12 : 16),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final message = messages[i];
                  final id = message['id'] as String;
                  final mine = message['sender_id'] == me;
                  final reactions = [
                    for (final raw in (message['reactions'] as List? ?? []))
                      Map<String, dynamic>.from(raw as Map),
                  ];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .82,
                        ),
                        child: Column(
                          crossAxisAlignment: mine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onLongPress: () =>
                                  _showReactionBar(message, mine),
                              onDoubleTap: () => _react(id, '❤️'),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? PhlioColors.brandViolet
                                          .withValues(alpha: .65)
                                      : PhlioColors.surfaceElevated,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(20),
                                    topRight: const Radius.circular(20),
                                    bottomLeft: Radius.circular(
                                      mine ? 20 : 5,
                                    ),
                                    bottomRight: Radius.circular(
                                      mine ? 5 : 20,
                                    ),
                                  ),
                                ),
                                child: MessageStickerCanvas(
                                  overlays: _overlays(message),
                                  child: _messageBody(
                                    message,
                                    mine,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                timeago.format(
                                  DateTime.parse(
                                    message['created_at'] as String,
                                  ),
                                ),
                                style: PhlioTypography.caption
                                    .copyWith(fontSize: 10),
                              ),
                            ),
                            if (reactions.isNotEmpty)
                              _ReactionChips(
                                reactions: reactions,
                                myId: me,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        ChatComposer(
          audience: ChatAudience.directMessage,
          hint: 'Message @${widget.username}',
          surfaceColor: PhlioColors.roomsInput,
          onSendText: _send,
          onSendFiles: _files,
          onSendVoice: (duration, path) async {
            if (path == null) return;
            final uploaded = await ref
                .read(messagingApiProvider)
                .upload(widget.username, [path]);
            await _send('', attachments: uploaded);
          },
        ),
      ],
    );
  }

  Widget _empty(String name) {
    if (widget.compact) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PhlioFox(size: 72, pose: PhlioFoxPose.happy),
            const SizedBox(height: PhlioSpacing.sm),
            Text('Say hi to $name', style: PhlioTypography.body),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Align(
          alignment: Alignment.centerLeft,
          child: PhlioAvatar(profileId: widget.username, name: name, size: 96),
        ),
        const SizedBox(height: 24),
        Text(name, style: PhlioTypography.displayMedium),
        Text('@${widget.username}', style: PhlioTypography.bodyLarge),
        const SizedBox(height: 16),
        Text(
          'This is the beginning of your conversation with $name.',
          style: PhlioTypography.bodyLarge,
        ),
        const SizedBox(height: 48),
        const Center(child: PhlioFox(size: 96, pose: PhlioFoxPose.happy)),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(
            onPressed: () async {
              try {
                await _send('👋');
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not send your wave. Try again.'),
                    ),
                  );
                }
              }
            },
            child: Text('Wave to $name'),
          ),
        ),
      ],
    );
  }
}

/// Reaction chips under a message, grouped per emoji, highlighted when the
/// signed-in user reacted.
class _ReactionChips extends StatelessWidget {
  const _ReactionChips({required this.reactions, required this.myId});

  final List<Map<String, dynamic>> reactions;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, int>{};
    final mine = <String>{};
    for (final r in reactions) {
      final value = r['value'] as String;
      grouped[value] = (grouped[value] ?? 0) + 1;
      if (r['user_id'] == myId) mine.add(value);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        children: [
          for (final entry in grouped.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: mine.contains(entry.key)
                    ? PhlioColors.brandViolet.withValues(alpha: 0.22)
                    : PhlioColors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: mine.contains(entry.key)
                      ? PhlioColors.brandViolet.withValues(alpha: 0.5)
                      : PhlioColors.borderSubtle,
                ),
              ),
              child: Text(
                entry.key + (entry.value > 1 ? '  ${entry.value}' : ''),
                style: PhlioTypography.caption.copyWith(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// One private attachment, fetched through the authenticated media route.
class _PrivateAttachment extends ConsumerWidget {
  const _PrivateAttachment({required this.data, required this.mine, super.key});
  final Map<String, dynamic> data;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AttachmentPreview(
        attachment: MessageAttachmentEntity(
          id: data['id'] as String,
          kind: data['kind'] as String,
          name: data['name'] as String,
          size: (data['size'] as num?)?.toInt() ?? 0,
          mime: data['mime'] as String? ?? '',
          url: data['url'] as String? ?? '',
          value: data['value'] as String? ?? '',
        ),
        loadPrivateFile: (data['url'] as String? ?? '').isEmpty
            ? null
            : () =>
                ref.read(messagingApiProvider).localFile(data['url'] as String),
      ),
    );
  }
}
