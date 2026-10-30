import 'dm_media_album.dart';
import 'dm_media_studio.dart';
import 'dart:ui' show ImageFilter;

import 'package:go_router/go_router.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import '../../../../design_system/widgets/phlio_icons.dart';
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
  static const _quickEmojis = ['❤️', '😂', '😮', '😢', '😡', '👍'];
  static const _moreEmojis = [
    '❤️',
    '😂',
    '😮',
    '😢',
    '😡',
    '👍',
    '🔥',
    '🙏',
    '👏',
    '🎉',
    '😍',
    '🥹',
    '😭',
    '🤯',
    '😎',
    '🤔',
    '👀',
    '💯',
    '✨',
    '🙌',
    '😅',
    '🤝',
    '💀',
    '🫶',
  ];

  final ScrollController _scroll = ScrollController();
  int _lastCount = -1;

  /// Message the composer is replying to (Instagram-style reply bar).
  Map<String, dynamic>? _replyingTo;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(
    String text, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final replyTo = _replyingTo?['id'] as String?;
    await ref.read(messagingApiProvider).send(widget.username, text,
        attachments: attachments, replyTo: replyTo);
    if (!mounted) return;
    if (replyTo != null) setState(() => _replyingTo = null);
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

  // -- Instagram-style long-press actions -----------------------------------

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _refresh() {
    ref.invalidate(dmHistoryProvider(widget.username));
    ref.invalidate(dmConversationsProvider);
  }

  final _improvingAudio = <String>{};

  Future<void> _showMessageActions(
      Map<String, dynamic> message, bool mine) async {
    final created = DateTime.tryParse(message['created_at'] as String? ?? '');
    final time = created == null
        ? ''
        : TimeOfDay.fromDateTime(created.toLocal()).format(context);
    final editable = (message['attachments'] as List? ?? [])
        .whereType<Map>()
        .where((a) => a['kind'] == 'image' || a['kind'] == 'video')
        .toList();
    final pinned = message['pinned'] == true;
    final audio = (message['attachments'] as List? ?? [])
        .whereType<Map>()
        .where((a) => a['kind'] == 'audio')
        .firstOrNull;
    final improved = audio?['enhanced_by'] != null;
    final size = MediaQuery.sizeOf(context);

    Widget tile(BuildContext dialogContext, String value, IconData icon,
            String label,
            {bool danger = false}) =>
        InkWell(
          onTap: () => Navigator.pop(dialogContext, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(children: [
              PhlioIcon(icon,
                  size: 26,
                  color: danger ? PhlioColors.danger : PhlioColors.textPrimary),
              const SizedBox(width: 18),
              Flexible(
                  child: Text(label,
                      style: PhlioTypography.bodyLarge.copyWith(
                          fontSize: 17,
                          color: danger
                              ? PhlioColors.danger
                              : PhlioColors.textPrimary))),
            ]),
          ),
        );

    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss message actions',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      pageBuilder: (dialogContext, _, __) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    _ReactionPill(
                      emojis: _quickEmojis,
                      onPick: (e) => Navigator.pop(dialogContext, 'react:$e'),
                      onMore: () => Navigator.pop(dialogContext, 'react-more'),
                    ),
                    const SizedBox(height: 14),
                    // The message itself, scaled down if it's very tall.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: size.width * .82,
                          maxHeight: size.height * .3),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: size.width * .82),
                          child: IgnorePointer(child: _bubble(message, mine)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: 260,
                      decoration: BoxDecoration(
                        color: const Color(0xFF262A31),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 24)
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (time.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
                              child: Text(time,
                                  style: PhlioTypography.body
                                      .copyWith(color: PhlioColors.textMuted)),
                            ),
                          if (mine &&
                              audio != null &&
                              !_improvingAudio.contains(message['id']))
                            tile(
                                dialogContext,
                                improved ? 'restore-audio' : 'improve-audio',
                                Icons.auto_awesome_rounded,
                                improved
                                    ? 'Restore original audio'
                                    : 'Improve with Foxy AI'),
                          if (editable.isNotEmpty)
                            tile(dialogContext, 'edit-media',
                                Icons.edit_outlined, 'Edit photo / video'),
                          tile(dialogContext, 'reply', Icons.reply_rounded,
                              'Reply'),
                          tile(dialogContext, 'make-sticker',
                              Icons.content_cut_rounded, 'Make a sticker'),
                          tile(dialogContext, 'forward', PhlioIcons.send,
                              'Forward'),
                          tile(
                              dialogContext,
                              'pin',
                              pinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              pinned ? 'Unpin' : 'Pin'),
                          if (mine)
                            tile(dialogContext, 'add-sticker',
                                Icons.add_reaction_outlined, 'Add sticker'),
                          tile(dialogContext, 'delete',
                              Icons.delete_outline_rounded, 'Delete for you'),
                          if (mine)
                            tile(dialogContext, 'unsend',
                                Icons.settings_backup_restore_rounded, 'Unsend',
                                danger: true),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final id = message['id'] as String;
    final api = ref.read(messagingApiProvider);
    try {
      if (action.startsWith('react:')) {
        await _react(id, action.substring(6));
      } else if (action == 'react-more') {
        final emoji = await _pickEmoji();
        if (emoji != null) await _react(id, emoji);
      } else if (action == 'improve-audio' || action == 'restore-audio') {
        if (audio == null || !_improvingAudio.add(id)) return;
        setState(() {});
        try {
          await api.improveAudio(widget.username, id, audio['id'] as String,
              restore: action == 'restore-audio');
          if (mounted) {
            _refresh();
            _say(action == 'restore-audio'
                ? 'Original audio restored'
                : 'Voice message improved with Foxy AI');
          }
        } finally {
          _improvingAudio.remove(id);
          if (mounted) setState(() {});
        }
      } else if (action == 'edit-media') {
        final chosen = editable.length == 1
            ? editable.first
            : await showModalBottomSheet<Map>(
                context: context,
                builder: (ctx) => SafeArea(
                        child: ListView(shrinkWrap: true, children: [
                      for (final item in editable)
                        ListTile(
                            title: Text(item['name'] ?? 'Media'),
                            onTap: () => Navigator.pop(ctx, item)),
                    ])));
        if (chosen == null) return;
        final path = await api.localFile(chosen['url']);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DmMediaStudio(
                peer: widget.username,
                initial: StagedAttachment(
                    kind: chosen['kind'],
                    name: chosen['name'],
                    path: path,
                    size: (chosen['size'] as num?)?.toInt() ?? 0),
                onSend: (edited) async {
                  final uploaded =
                      await api.upload(widget.username, [edited.path!]);
                  await api.send(widget.username, '', attachments: uploaded);
                  if (mounted) _refresh();
                })));
      } else if (action == 'reply') {
        setState(() => _replyingTo = message);
      } else if (action == 'make-sticker') {
        _say('Make a sticker is coming soon.');
      } else if (action == 'forward') {
        await _forward(message);
      } else if (action == 'pin') {
        await api.pin(widget.username, id, !pinned);
        _refresh();
        _say(pinned ? 'Message unpinned' : 'Message pinned');
      } else if (action == 'add-sticker') {
        await _decorate(message, mine);
      } else if (action == 'delete') {
        await api.deleteMessage(widget.username, id);
        if (_replyingTo?['id'] == id) setState(() => _replyingTo = null);
        _refresh();
        _say('Deleted for you');
      } else if (action == 'unsend') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Unsend message?'),
            content: const Text(
                'This removes the message for everyone in the chat.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: PhlioColors.danger),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Unsend')),
            ],
          ),
        );
        if (confirmed != true) return;
        await api.deleteMessage(widget.username, id, everyone: true);
        if (_replyingTo?['id'] == id) setState(() => _replyingTo = null);
        _refresh();
      }
    } catch (_) {
      if (mounted) _say('Something went wrong. Try again.');
    }
  }

  Future<String?> _pickEmoji() => showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 6,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              for (final emoji in _moreEmojis)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(sheet, emoji),
                  child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 30))),
                ),
            ],
          ),
        ),
      );

  Future<void> _forward(Map<String, dynamic> message) async {
    final api = ref.read(messagingApiProvider);
    final to = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _ForwardSheet(load: api.destinations, exclude: widget.username),
    );
    if (to == null || to.isEmpty || !mounted) return;
    final sent =
        await api.forward(widget.username, message['id'] as String, to);
    ref.invalidate(dmConversationsProvider);
    if (mounted) {
      _say(sent.length == 1
          ? 'Forwarded to ${sent.first}'
          : 'Forwarded to ${sent.length} chats');
    }
  }

  Future<void> _decorate(Map<String, dynamic> message, bool mine) async {
    final overlays = await editMessageStickers(
      context,
      child: _messageBody(message, mine),
      initial: _overlays(message),
    );
    if (!mounted || overlays == null) return;
    await ref
        .read(messagingApiProvider)
        .setOverlays(widget.username, message['id'] as String, overlays);
    if (mounted) ref.invalidate(dmHistoryProvider(widget.username));
  }

  /// One-line description of a message, for reply bars and quotes.
  String _snippet(Map message) {
    final text = (message['text'] as String? ?? '').trim();
    if (sharedContentPath(text) != null) {
      final caption = sharedContentCaption(text);
      return caption.isNotEmpty ? caption : 'Shared a post';
    }
    if (text.isNotEmpty) return text;
    final kind = message['kind'] as String? ??
        ((message['attachments'] as List?)?.isNotEmpty == true
            ? ((message['attachments'] as List).first as Map)['kind'] as String?
            : null);
    return switch (kind) {
      'image' => 'Photo',
      'video' => 'Video',
      'audio' => 'Voice message',
      'sticker' => 'Sticker',
      'gif' => 'GIF',
      null => 'Message',
      _ => 'Attachment',
    };
  }

  /// Shared Phlio object card or the regular chat bubble.
  Widget _bubble(Map<String, dynamic> message, bool mine) {
    final attachments = message['attachments'] as List;
    final shared = attachments.isEmpty
        ? sharedContentPath(message['text'] as String)
        : null;
    if (shared != null) {
      final caption = sharedContentCaption(message['text'] as String);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          SharedContentCard(path: shared, mine: mine),
          if (caption.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: mine
                    ? PhlioColors.brandViolet
                    : PhlioColors.surfaceElevated,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(caption, style: PhlioTypography.bodyLarge),
            ),
        ],
      );
    }
    return Container(
      padding: attachments.isEmpty
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: attachments.isNotEmpty
            ? Colors.transparent
            : mine
                ? PhlioColors.brandViolet.withValues(alpha: .65)
                : PhlioColors.surfaceElevated,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 5),
          bottomRight: Radius.circular(mine ? 5 : 20),
        ),
      ),
      child: MessageStickerCanvas(
        overlays: _overlays(message),
        child: _messageBody(message, mine),
      ),
    );
  }

  Widget _replyQuote(Map reply, bool mine, String? me, String name) {
    final fromMe = reply['sender_id'] == me;
    final who = mine
        ? (fromMe ? 'You replied to yourself' : 'You replied to $name')
        : (fromMe ? '$name replied to you' : '$name replied to themselves');
    final text =
        reply['deleted'] == true ? 'Message unavailable' : _snippet(reply);
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.reply_rounded,
                size: 14, color: PhlioColors.textMuted),
            const SizedBox(width: 4),
            Text(who,
                style: PhlioTypography.caption
                    .copyWith(color: PhlioColors.textMuted)),
          ]),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: PhlioColors.surfaceElevated.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PhlioTypography.body
                  .copyWith(color: PhlioColors.textSecondary)),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _overlays(Map<String, dynamic> message) => [
        for (final v in message['overlays'] as List? ?? [])
          Map<String, dynamic>.from(v as Map),
      ];

  Widget _messageBody(Map<String, dynamic> message, bool mine) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((message['text'] as String).isNotEmpty)
              SharedContentText(message['text'] as String,
                  style: PhlioTypography.body),
            if (_improvingAudio.contains(message['id']))
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Foxy is improving audio...'),
                  ])),
            if ((message['attachments'] as List)
                .any((a) => (a as Map)['enhanced_by'] != null))
              const Text('Improved with Foxy AI',
                  style: TextStyle(fontSize: 12, color: PhlioColors.textMuted)),
            DmMediaAlbum(
              attachments: (message['attachments'] as List)
                  .map((raw) => Map<String, dynamic>.from(raw as Map))
                  .toList(),
              tileBuilder: (data, height) => _PrivateAttachment(
                key: ValueKey(data['id']),
                data: data,
                mine: mine,
                previewHeight: height,
              ),
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

    final pinnedMessages = [
      for (final m in history.valueOrNull ?? const <Map<String, dynamic>>[])
        if (m['pinned'] == true) m,
    ]..sort((a, b) => (b['pinned_at'] as String? ?? '')
        .compareTo(a['pinned_at'] as String? ?? ''));

    return Column(
      children: [
        if (pinnedMessages.isNotEmpty)
          Material(
            color: PhlioColors.surfaceElevated.withValues(alpha: .6),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.push_pin_rounded, size: 20),
              title: Text(
                  pinnedMessages.length == 1
                      ? 'Pinned message'
                      : '${pinnedMessages.length} pinned messages',
                  style: PhlioTypography.caption
                      .copyWith(color: PhlioColors.textMuted)),
              subtitle: Text(_snippet(pinnedMessages.first),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Unpin',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () async {
                  await ref.read(messagingApiProvider).pin(widget.username,
                      pinnedMessages.first['id'] as String, false);
                  _refresh();
                },
              ),
            ),
          ),
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
                            if (message['reply_to'] is Map)
                              _replyQuote(
                                  message['reply_to'] as Map, mine, me, name),
                            GestureDetector(
                              onLongPress: () =>
                                  _showMessageActions(message, mine),
                              onDoubleTap: () => _react(id, '❤️'),
                              child: _bubble(message, mine),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!mine) ...[
                                      PhlioAvatar(
                                          name: name,
                                          imageUrl:
                                              peer?['avatar_url'] as String?,
                                          profileId: widget.username,
                                          size: 22),
                                      const SizedBox(width: 6),
                                    ],
                                    if (message['pinned'] == true) ...[
                                      const Icon(Icons.push_pin_rounded,
                                          size: 12,
                                          color: PhlioColors.textMuted),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      timeago.format(
                                        DateTime.parse(
                                          message['created_at'] as String,
                                        ),
                                      ),
                                      style: PhlioTypography.caption
                                          .copyWith(fontSize: 10),
                                    )
                                  ]),
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
        if (_replyingTo != null)
          Container(
            color: PhlioColors.surfaceElevated.withValues(alpha: .6),
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(children: [
              const Icon(Icons.reply_rounded,
                  size: 20, color: PhlioColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _replyingTo!['sender_id'] == me
                            ? 'Replying to yourself'
                            : 'Replying to $name',
                        style: PhlioTypography.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: PhlioColors.textPrimary)),
                    Text(_snippet(_replyingTo!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.caption
                            .copyWith(color: PhlioColors.textMuted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancel reply',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _replyingTo = null),
              ),
            ]),
          ),
        ChatComposer(
          dmPeer: widget.username,
          audience: ChatAudience.directMessage,
          hint: 'Message @${widget.username}',
          compact: true,
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
    final peer = ref.watch(dmPeerProvider(widget.username)).valueOrNull;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 32),
      Center(
          child: PhlioAvatar(
              profileId: widget.username,
              name: name,
              imageUrl: peer?['avatar_url'] as String?,
              size: 112)),
      const SizedBox(height: 18),
      Text(name,
          textAlign: TextAlign.center,
          style: PhlioTypography.bodyStrong.copyWith(fontSize: 24)),
      const SizedBox(height: 6),
      Text(peer?['username'] as String? ?? widget.username,
          textAlign: TextAlign.center, style: PhlioTypography.body),
      const SizedBox(height: 14),
      Center(
          child: FilledButton.tonal(
              onPressed: () => context
                  .push('/creator/${Uri.encodeComponent(widget.username)}'),
              child: const Text('View profile'))),
      const SizedBox(height: 32),
      const Text('Say hello with a message or sticker',
          textAlign: TextAlign.center),
    ]);
  }
}

/// Emoji pill above a long-pressed message, like Instagram's.
class _ReactionPill extends StatelessWidget {
  const _ReactionPill(
      {required this.emojis, required this.onPick, required this.onMore});
  final List<String> emojis;
  final ValueChanged<String> onPick;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF262A31),
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 24)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Tap and hold to super react',
              style: PhlioTypography.caption
                  .copyWith(color: PhlioColors.textSecondary)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final emoji in emojis)
                GestureDetector(
                  onTap: () => onPick(emoji),
                  // Super reactions are a placeholder: same as a tap for now.
                  onLongPress: () => onPick(emoji),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Text(emoji,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(fontSize: 32)),
                  ),
                ),
              IconButton(
                tooltip: 'More reactions',
                onPressed: onMore,
                icon: const Icon(Icons.add_rounded,
                    size: 30, color: PhlioColors.textSecondary),
              ),
            ]),
          ),
        ]),
      );
}

/// Pick people to forward a message to (recent chats and connections first).
class _ForwardSheet extends StatefulWidget {
  const _ForwardSheet({required this.load, required this.exclude});
  final Future<List<Map<String, dynamic>>> Function() load;
  final String exclude;
  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  late final Future<List<Map<String, dynamic>>> people = widget.load();
  final selected = <String, String>{};
  String query = '';

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => query = v.toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search',
                filled: true,
                fillColor: PhlioColors.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: people,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Could not load people.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!
                    .where((p) =>
                        p['username'] != widget.exclude &&
                        p['id'] != widget.exclude &&
                        '${p['display_name'] ?? ''} ${p['username'] ?? ''}'
                            .toLowerCase()
                            .contains(query))
                    .toList();
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final p = rows[i];
                    final handle = (p['username'] ?? p['id']).toString();
                    final on = selected.containsKey(handle);
                    return ListTile(
                      onTap: () => setState(() => on
                          ? selected.remove(handle)
                          : selected[handle] =
                              (p['display_name'] ?? handle).toString()),
                      leading: PhlioAvatar(
                          name: (p['display_name'] ?? handle).toString(),
                          imageUrl: p['avatar_url'] as String?,
                          size: 44),
                      title: Text((p['display_name'] ?? handle).toString()),
                      subtitle: Text(
                          p['recent'] == true
                              ? 'Recent chat'
                              : (p['relation'] ?? handle).toString(),
                          style: PhlioTypography.caption),
                      trailing: Icon(
                          on
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: on
                              ? PhlioColors.brandViolet
                              : PhlioColors.textMuted),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, selected.keys.toList()),
                  child: Text(selected.isEmpty
                      ? 'Forward'
                      : selected.length == 1
                          ? 'Send to ${selected.values.first}'
                          : 'Send separately (${selected.length})'),
                ),
              ),
            ),
          ),
        ]),
      );
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
  const _PrivateAttachment(
      {required this.data, required this.mine, this.previewHeight, super.key});
  final Map<String, dynamic> data;
  final bool mine;
  final double? previewHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.only(top: previewHeight == null ? 8 : 0),
      child: AttachmentPreview(
        previewHeight: previewHeight,
        mediaOnly: ['image', 'gif', 'sticker', 'video'].contains(data['kind']),
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
