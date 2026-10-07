// Room detail/chat screen — mirrors the Rooms two-pane thread style:
// thread (e.g. "#general"): Discord-style full-width rows + a composer bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../controllers/room_chat_controller.dart';
import '../widgets/message_attachments.dart';

class RoomDetailScreen extends ConsumerStatefulWidget {
  const RoomDetailScreen({required this.roomId, super.key});

  final String roomId;

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen> {
  final _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    final result = await ref
        .read(roomChatControllerProvider(widget.roomId).notifier)
        .sendMessage(text);
    if (!mounted) return;
    result.when(
      success: (_) => _messageController.clear(),
      failure: (failure) => showErrorSnackBar(context, failure),
    );
    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(roomChatControllerProvider(widget.roomId));
    final currentUserId = ref.watch(authControllerProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(
          title: Text('# ${widget.roomId}', style: PhlioTypography.title)),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const PhlioLoadingIndicator(),
              error: (error, _) => PhlioErrorView(
                failure: error is Failure ? error : const Failure.unknown(),
                onRetry: () =>
                    ref.invalidate(roomChatControllerProvider(widget.roomId)),
              ),
              data: (messages) => ListView.builder(
                reverse: false,
                padding: const EdgeInsets.all(PhlioSpacing.lg),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isMine = message.authorId == currentUserId;
                  // Long-press to react with Foxy — same as the two-pane.
                  Future<void> react(String kind, String value) async {
                    final result = await ref
                        .read(
                            roomChatControllerProvider(widget.roomId).notifier)
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

                  // Discord-style: every message is a full-width row from
                  // the left edge — own messages keep the same alignment,
                  // the name carries the color instead of a bubble split.
                  return Padding(
                    padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PhlioAvatar(
                            profileId: message.authorId,
                            name: message.authorId,
                            size: 32),
                        const SizedBox(width: PhlioSpacing.sm),
                        Expanded(
                          child: GestureDetector(
                            onLongPress: () => showReactionPickerAndReact(
                                context,
                                onReact: react),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        message.authorId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: PhlioTypography.label.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: isMine
                                              ? PhlioColors.brandOrange
                                              : PhlioColors.brandLavender,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: PhlioSpacing.xs),
                                    Text(
                                      timeago.format(message.createdAt),
                                      style: PhlioTypography.caption
                                          .copyWith(fontSize: 10),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                if (message.text.isNotEmpty)
                                  Text(message.text,
                                      style: PhlioTypography.body),
                                if (message.attachments.isNotEmpty) ...[
                                  const SizedBox(height: PhlioSpacing.xs),
                                  MessageAttachmentView(
                                    attachments: message.attachments,
                                    reactions: message.reactions,
                                    onReact: react,
                                  ),
                                ] else if (message.reactions.isNotEmpty) ...[
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(PhlioSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PhlioSpacing.lg),
                      decoration: BoxDecoration(
                        color: PhlioColors.surfaceInput,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: PhlioTypography.bodyLarge,
                        decoration: const InputDecoration(
                          hintText: 'Message #general',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: PhlioSpacing.sm),
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: PhlioColors.brandPurple),
                    onPressed: _isSending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
