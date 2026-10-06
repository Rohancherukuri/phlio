import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

/// The conversation core shared by the pushed DM screen and the creator
/// profile's Chat tab: the polling history, the send/upload pipeline
/// (text, files, voice, Foxy stickers/GIFs via the composer) and
/// Instagram-style long-press reactions (quick emoji bar anchored above the
/// message, toggle-on-tap, reaction chips under the message).
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
  final Map<String, LayerLink> _links = {};
  int _lastCount = -1;
  OverlayEntry? _reactionOverlay;

  @override
  void dispose() {
    _dismissReactionBar();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text,
      {List<Map<String, dynamic>> attachments = const []}) async {
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
        if (f.path != null) f.path!
    ];
    final uploaded = paths.isEmpty
        ? <Map<String, dynamic>>[]
        : await api.upload(widget.username, paths);
    await _send(text, attachments: [
      ...uploaded,
      for (final f in files)
        if (f.isPackItem) {'kind': f.kind, 'name': f.name, 'value': f.packId}
    ]);
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
            const SnackBar(content: Text('Could not react. Try again.')));
      }
    }
  }

  // -- Instagram-style reaction bar -------------------------------------------

  void _dismissReactionBar() {
    _reactionOverlay?.remove();
    _reactionOverlay = null;
  }

  void _showReactionBar(String messageId) {
    _dismissReactionBar();
    _reactionOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap anywhere else to dismiss without reacting.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissReactionBar,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _links.putIfAbsent(messageId, LayerLink.new),
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            showWhenUnlinked: false,
            offset: const Offset(0, -10),
            child: _ReactionBar(
              active: _quickEmojis,
              onPick: (emoji) {
                _dismissReactionBar();
                _react(messageId, emoji);
              },
            ),
          ),
        ],
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_reactionOverlay!);
  }

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
                      .where((m) =>
                          (m['text'] as String).toLowerCase().contains(query))
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
                  final mine = message['sender_id'] != peer?['id'];
                  final reactions = [
                    for (final raw in (message['reactions'] as List? ?? []))
                      Map<String, dynamic>.from(raw as Map),
                  ];
                  return Padding(
                    padding: EdgeInsets.only(bottom: widget.compact ? 12 : 20),
                    child: CompositedTransformTarget(
                      link: _links.putIfAbsent(id, LayerLink.new),
                      child: GestureDetector(
                        // Long-press any message: Instagram-style reaction bar.
                        onLongPress: () => _showReactionBar(id),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              // The peer's avatar opens their profile page.
                              onTap: mine
                                  ? null
                                  : () => context
                                      .push('/creator/${widget.username}'),
                              child: PhlioAvatar(
                                  name: mine ? 'You' : name,
                                  size: widget.compact ? 30 : 36),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(mine ? 'You' : name,
                                          style: PhlioTypography.bodyStrong
                                              .copyWith(
                                            color: mine
                                                ? PhlioColors.brandOrange
                                                : PhlioColors.brandLavender,
                                          )),
                                      Text(
                                          timeago.format(DateTime.parse(
                                              message['created_at'] as String)),
                                          style: PhlioTypography.caption
                                              .copyWith(fontSize: 10)),
                                    ],
                                  ),
                                  if ((message['text'] as String).isNotEmpty)
                                    Text(message['text'] as String,
                                        style: PhlioTypography.body),
                                  for (final raw
                                      in message['attachments'] as List)
                                    _PrivateAttachment(
                                      key: ValueKey((raw as Map)['id']),
                                      data: Map<String, dynamic>.from(raw),
                                      mine: mine,
                                    ),
                                  if (reactions.isNotEmpty)
                                    _ReactionChips(
                                        reactions: reactions, myId: me),
                                ],
                              ),
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
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 48),
      Align(
          alignment: Alignment.centerLeft,
          child: PhlioAvatar(name: name, size: 96)),
      const SizedBox(height: 24),
      Text(name, style: PhlioTypography.displayMedium),
      Text('@${widget.username}', style: PhlioTypography.bodyLarge),
      const SizedBox(height: 16),
      Text('This is the beginning of your conversation with $name.',
          style: PhlioTypography.bodyLarge),
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not send your wave. Try again.')));
                  }
                }
              },
              child: Text('Wave to $name'))),
    ]);
  }
}

/// Floating quick-reaction pill anchored above the long-pressed message.
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.active, required this.onPick});

  final List<String> active;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PhlioColors.borderSubtle),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 18, offset: Offset(0, 6))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < active.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              GestureDetector(
                onTap: () => onPick(active[i]),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(active[i], style: const TextStyle(fontSize: 26)),
                ),
              ),
            ],
          ],
        ),
      ),
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
                        : PhlioColors.borderSubtle),
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
              : () => ref
                  .read(messagingApiProvider)
                  .localFile(data['url'] as String),
        ));
  }
}
