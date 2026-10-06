// Phlio Agent (Foxy) screen — mirrors the reference "4. PHLIO AGENT"
// screen: Foxy's header with a BETA badge and tagline, a scrolling chat
// transcript, and a message composer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../domain/entities/agent_message_entity.dart';
import '../controllers/agent_controller.dart';
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

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? presetText]) async {
    final text = (presetText ?? _inputController.text).trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();
    setState(() => _isSending = true);

    final result = await ref.read(agentControllerProvider.notifier).sendMessage(text);
    if (!mounted) return;
    result.when(
      success: (_) => _scrollToBottom(),
      failure: (failure) => showErrorSnackBar(context, failure),
    );
    setState(() => _isSending = false);
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const PhlioFox(size: 34, pose: PhlioFoxPose.hello, animate: false),
            const SizedBox(width: PhlioSpacing.sm),
            Text('Foxy', style: PhlioTypography.title),
            const SizedBox(width: PhlioSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: PhlioColors.brandOrange.withValues(alpha: 0.18),
                borderRadius: PhlioRadii.pillRadius,
              ),
              child: Text('BETA', style: PhlioTypography.caption.copyWith(color: PhlioColors.brandOrange)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Something went wrong.')),
              data: (messages) => messages.isEmpty ? _buildEmptyState() : _buildTranscript(messages),
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PhlioSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhlioFox(size: 104, pose: PhlioFoxPose.happy),
            const SizedBox(height: PhlioSpacing.lg),
            Text('Your plan, my priority.', style: PhlioTypography.headline),
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
      itemCount: messages.length,
      itemBuilder: (context, index) => AgentMessageBubble(message: messages[index]),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
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
                  borderRadius: PhlioRadii.pillRadius,
                  border: Border.all(color: PhlioColors.border),
                ),
                child: TextField(
                  controller: _inputController,
                  style: PhlioTypography.bodyLarge,
                  decoration: const InputDecoration(hintText: 'Ask me anything...', border: InputBorder.none),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: PhlioSpacing.sm),
            Container(
              decoration: const BoxDecoration(gradient: PhlioColors.brandGradient, shape: BoxShape.circle),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: PhlioColors.textOnBrand),
                      )
                    : const Icon(Icons.arrow_upward_rounded, color: PhlioColors.textOnBrand),
                onPressed: _isSending ? null : () => _send(),
              ),
            ),
          ],
        ),
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
        child: Text(text, style: PhlioTypography.body, textAlign: TextAlign.center),
      ),
    );
  }
}
