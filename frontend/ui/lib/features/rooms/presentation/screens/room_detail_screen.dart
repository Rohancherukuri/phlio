// Room detail/chat screen — mirrors the reference Rooms screen's message
// thread (e.g. "#general"): a scrollable message list plus a composer bar.

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
    final result = await ref.read(roomChatControllerProvider(widget.roomId).notifier).sendMessage(text);
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
      appBar: AppBar(title: Text('# ${widget.roomId}', style: PhlioTypography.title)),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const PhlioLoadingIndicator(),
              error: (error, _) => PhlioErrorView(
                failure: error is Failure ? error : const Failure.unknown(),
                onRetry: () => ref.invalidate(roomChatControllerProvider(widget.roomId)),
              ),
              data: (messages) => ListView.builder(
                reverse: false,
                padding: const EdgeInsets.all(PhlioSpacing.lg),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isMine = message.authorId == currentUserId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                      children: [
                        if (!isMine) ...[
                          PhlioAvatar(name: message.authorId, size: 32),
                          const SizedBox(width: PhlioSpacing.sm),
                        ],
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PhlioSpacing.md,
                              vertical: PhlioSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: isMine ? PhlioColors.brandPurple.withOpacity(0.25) : PhlioColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(message.text, style: PhlioTypography.bodyLarge),
                                const SizedBox(height: 2),
                                Text(timeago.format(message.createdAt), style: PhlioTypography.caption),
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
                      padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
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
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded, color: PhlioColors.brandPurple),
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
