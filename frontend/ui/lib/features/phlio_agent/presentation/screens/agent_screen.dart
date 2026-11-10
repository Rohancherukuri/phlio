import 'package:phlio/shared/widgets/notifications_button.dart';
// Phlio Agent (Foxy) screen — mirrors the reference "4. PHLIO AGENT"
// screen: Foxy's header with a BETA badge and tagline, a scrolling chat
// transcript, and a message composer.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../domain/entities/agent_message_entity.dart';
import '../controllers/agent_controller.dart';
import '../widgets/agent_attachments.dart';
import '../widgets/agent_quick_actions.dart';
import '../widgets/agent_chats_drawer.dart';
import '../widgets/agent_message_bubble.dart';

const _suggestedPrompts = [
  'Plan something for Saturday with 3 friends under ₹4,000',
  'Find me something creative to do this weekend',
  'Suggest a budget-friendly evening out',
];

class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  /// Files picked with "+", uploading or ready to go with the next message.
  final List<AgentPendingAttachment> _pending = [];

  bool get _uploading => _pending.any((p) => p.uploading);

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? presetText]) async {
    final text = (presetText ?? _inputController.text).trim();
    final ready = [
      for (final p in _pending)
        if (p.uploaded != null) p.uploaded!,
    ];
    if (_isSending || _uploading) return;
    if (text.isEmpty && ready.isEmpty) return;

    final sentPending = List.of(_pending.where((p) => p.uploaded != null));
    _inputController.clear();
    setState(() {
      _isSending = true;
      _pending.removeWhere((p) => p.uploaded != null);
    });
    _scrollToBottom();

    final result = await ref
        .read(agentControllerProvider.notifier)
        .sendMessage(text, attachments: ready);
    if (!mounted) return;
    result.when(
      success: (_) => _scrollToBottom(),
      failure: (failure) {
        // Put the files back so nothing is lost.
        setState(() => _pending.insertAll(0, sentPending));
        showErrorSnackBar(context, failure);
      },
    );
    setState(() => _isSending = false);
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// Clears the screen for a fresh conversation; the current one is
  /// already kept in Chats.
  void _newChat() {
    ref.read(agentControllerProvider.notifier).newChat();
    _inputController.clear();
    setState(_pending.clear);
  }

  Future<void> _attach() async {
    FocusScope.of(context).unfocus();
    final room = maxAgentAttachments - _pending.length;
    final hasChat =
        (ref.read(agentControllerProvider).valueOrNull ?? const []).isNotEmpty;
    final paths = await showAgentAttachSheet(context,
        max: room, onNewChat: hasChat ? _newChat : null);
    if (room <= 0 && paths.isEmpty) {
      if (mounted && !hasChat) {
        _toast('You can attach up to $maxAgentAttachments files at a time.');
      }
      return;
    }
    if (!mounted || paths.isEmpty) return;
    for (final path in paths.take(room)) {
      final item = AgentPendingAttachment(path);
      final size = await File(path).length().catchError((_) => 0);
      final limit = agentAttachmentLimits[item.kind]!;
      if (size > limit) {
        _toast('${item.name} is too big — ${item.kind.name}s must be '
            '${limit ~/ 1000000} MB or smaller.');
        continue;
      }
      if (!mounted) return;
      setState(() => _pending.add(item));
      _upload(item);
    }
  }

  Future<void> _upload(AgentPendingAttachment item) async {
    setState(() {
      item.error = null;
      item.progress = 0;
    });
    final result = await ref.read(agentControllerProvider.notifier).uploadFiles(
      [item.path],
      onProgress: (v) {
        if (mounted && _pending.contains(item)) setState(() => item.progress = v);
      },
    );
    if (!mounted || !_pending.contains(item)) return;
    result.when(
      success: (files) => setState(() => item.uploaded = files.first),
      failure: (failure) {
        setState(() => item.error = failure.message);
        showErrorSnackBar(context, failure);
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(agentControllerProvider);
    // Keep the newest message in view (also for sends from the nav wheel).
    ref.listen(agentControllerProvider, (_, __) => _scrollToBottom());
    ref.listen(agentBusyProvider, (_, __) => _scrollToBottom());

    final hasChat = (messagesAsync.valueOrNull ?? const []).isNotEmpty;
    return Scaffold(
      drawer: const AgentChatsDrawer(),
      onDrawerChanged: (open) {
        if (open) FocusScope.of(context).unfocus();
      },
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Chats',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: hasChat ? _newChat : null,
            icon: const Icon(Icons.edit_square),
          ),
          const PhlioNotificationsButton(),
        ],
        title: Row(
          children: [
            const FoxyAvatar(size: 34),
            const SizedBox(width: PhlioSpacing.sm),
            Text('Foxy', style: PhlioTypography.title),
            const SizedBox(width: PhlioSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: PhlioSpacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: PhlioColors.brandOrange.withValues(alpha: 0.18),
                borderRadius: PhlioRadii.pillRadius,
              ),
              child: Text('BETA',
                  style: PhlioTypography.caption
                      .copyWith(color: PhlioColors.brandOrange)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('Something went wrong.')),
              data: (messages) =>
                  messages.isEmpty && !ref.watch(agentBusyProvider)
                      ? _buildEmptyState()
                      : _buildTranscript(messages),
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('agent-welcome-scroll'),
        padding: const EdgeInsets.all(PhlioSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhlioFox(size: 104, pose: PhlioFoxPose.happy),
            const SizedBox(height: PhlioSpacing.lg),
            Text('Your plan, my priority.',
                textAlign: TextAlign.center, style: PhlioTypography.headline),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              "I'm Foxy — I can help you plan, book, shop and pay.",
              textAlign: TextAlign.center,
              style: PhlioTypography.body,
            ),
            const SizedBox(height: PhlioSpacing.xxl),
            for (final prompt in _suggestedPrompts) ...[
              _SuggestionChip(text: prompt, onTap: () => _send(prompt)),
              const SizedBox(height: PhlioSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTranscript(List<AgentMessageEntity> messages) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(PhlioSpacing.lg),
      itemCount: messages.length +
          (_isSending || ref.watch(agentBusyProvider) ? 1 : 0),
      itemBuilder: (context, index) => index < messages.length
          ? AgentMessageBubble(message: messages[index])
          : const _FoxyThinking(),
    );
  }

  Widget _buildComposer() {
    final canSend = !_isSending &&
        !_uploading &&
        (_inputController.text.trim().isNotEmpty ||
            _pending.any((p) => p.uploaded != null));
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _pending.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: PhlioSpacing.sm),
                    child: AgentPendingTray(
                      items: _pending,
                      onRemove: (item) => setState(() => _pending.remove(item)),
                      onRetry: _upload,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(PhlioSpacing.lg),
            child: Row(
              children: [
                // "+": photos, clips, audio and documents.
                Material(
                  color: PhlioColors.surfaceInput,
                  shape: const CircleBorder(
                      side: BorderSide(color: PhlioColors.border)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _isSending ? null : _attach,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.add_rounded,
                          size: 26, color: PhlioColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: PhlioSpacing.sm),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
                    decoration: BoxDecoration(
                      color: PhlioColors.surfaceInput,
                      borderRadius: PhlioRadii.pillRadius,
                      border: Border.all(color: PhlioColors.border),
                    ),
                    child: TextField(
                      controller: _inputController,
                      style: PhlioTypography.bodyLarge,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          hintText: _pending.isEmpty
                              ? 'Ask Foxy anything...'
                              : 'Add a message (optional)',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: PhlioSpacing.sm),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: canSend || _isSending ? 1 : 0.45,
                  child: Container(
                    decoration: const BoxDecoration(
                        gradient: PhlioColors.brandGradient,
                        shape: BoxShape.circle),
                    child: IconButton(
                      icon: _isSending || _uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: PhlioColors.textOnBrand),
                            )
                          : const Icon(Icons.arrow_upward_rounded,
                              color: PhlioColors.textOnBrand),
                      onPressed: canSend ? () => _send() : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live Foxy, glasses on, while the agent works on a reply.
class _FoxyThinking extends StatelessWidget {
  const _FoxyThinking();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const FoxyPuppet(act: FoxyAct.think, size: 72, entrance: true),
          const SizedBox(width: PhlioSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.md),
              decoration: BoxDecoration(
                color: PhlioColors.surfaceElevated,
                borderRadius: PhlioRadii.lgRadius,
              ),
              child: Text('Foxy is thinking…',
                  style: PhlioTypography.body
                      .copyWith(color: PhlioColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: PhlioRadii.lgRadius,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(PhlioSpacing.md),
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: PhlioRadii.lgRadius,
          border: Border.all(color: PhlioColors.borderSubtle),
        ),
        child: Text(text,
            style: PhlioTypography.body, textAlign: TextAlign.center),
      ),
    );
  }
}
