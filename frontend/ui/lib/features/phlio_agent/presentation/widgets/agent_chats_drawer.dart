// The "Chats" panel for Foxy: search every previous conversation, start a
// new one, rename or delete, and long-press a chat to drag it up or down.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../controllers/agent_chats_controller.dart';
import '../controllers/agent_controller.dart';

class AgentChatsDrawer extends ConsumerStatefulWidget {
  const AgentChatsDrawer({super.key});

  @override
  ConsumerState<AgentChatsDrawer> createState() => _AgentChatsDrawerState();
}

class _AgentChatsDrawerState extends ConsumerState<AgentChatsDrawer> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _newChat() {
    ref.read(agentControllerProvider.notifier).newChat();
    Navigator.of(context).maybePop();
  }

  void _open(AgentChat chat) {
    ref.read(agentControllerProvider.notifier).openChat(chat);
    Navigator.of(context).maybePop();
  }

  Future<void> _rename(AgentChat chat) async {
    final field = TextEditingController(text: chat.title);
    final title = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: PhlioColors.surfaceElevated,
        title: const Text('Rename chat'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('Save')),
        ],
      ),
    );
    field.dispose();
    if (title != null) ref.read(agentChatsProvider.notifier).rename(chat.id, title);
  }

  Future<void> _delete(AgentChat chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: PhlioColors.surfaceElevated,
        title: const Text('Delete chat?'),
        content: Text('"${chat.title}" will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: PhlioColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(agentChatsProvider.notifier).delete(chat.id);
      ref.read(agentControllerProvider.notifier).forgetChat(chat.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentChatsProvider);
    // Rebuild the highlight when the open chat changes.
    ref.watch(agentControllerProvider);
    final activeId = ref.read(agentControllerProvider.notifier).activeChatId;
    final query = _search.text;
    final results = state.search(query);
    final width = math.min(340.0, MediaQuery.sizeOf(context).width * 0.86);

    Widget list;
    if (!state.loaded) {
      list = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (state.chats.isEmpty) {
      list = _Empty(
        title: 'No chats yet',
        subtitle: 'Your conversations with Foxy will show up here.',
      );
    } else if (results.isEmpty) {
      list = _Empty(title: 'No matches', subtitle: 'Nothing found for "$query".');
    } else if (query.trim().isNotEmpty) {
      list = ListView.builder(
        padding: const EdgeInsets.fromLTRB(PhlioSpacing.md, 0, PhlioSpacing.md, PhlioSpacing.lg),
        itemCount: results.length,
        itemBuilder: (context, i) => _ChatTile(
          chat: results[i],
          active: results[i].id == activeId,
          query: query,
          onTap: () => _open(results[i]),
          onRename: () => _rename(results[i]),
          onDelete: () => _delete(results[i]),
        ),
      );
    } else {
      list = ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(PhlioSpacing.md, 0, PhlioSpacing.md, PhlioSpacing.lg),
        buildDefaultDragHandles: false,
        itemCount: results.length,
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorder: ref.read(agentChatsProvider.notifier).reorder,
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = Curves.easeOut.transform(animation.value);
            return Transform.scale(
              scale: 1 + 0.03 * t,
              child: Material(
                color: Colors.transparent,
                elevation: 10 * t,
                shadowColor: Colors.black54,
                borderRadius: PhlioRadii.lgRadius,
                child: child,
              ),
            );
          },
          child: child,
        ),
        itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
          key: ValueKey(results[i].id),
          index: i,
          child: _ChatTile(
            chat: results[i],
            active: results[i].id == activeId,
            onTap: () => _open(results[i]),
            onRename: () => _rename(results[i]),
            onDelete: () => _delete(results[i]),
          ),
        ),
      );
    }

    return Drawer(
      width: width,
      backgroundColor: PhlioColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg, PhlioSpacing.md, PhlioSpacing.sm, 0),
              child: Row(
                children: [
                  const FoxyAvatar(size: 30),
                  const SizedBox(width: PhlioSpacing.sm),
                  Expanded(child: Text('Chats', style: PhlioTypography.title)),
                  IconButton(
                    tooltip: 'New chat',
                    onPressed: _newChat,
                    icon: const Icon(Icons.edit_square, color: PhlioColors.textPrimary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(PhlioSpacing.md),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.md),
                decoration: BoxDecoration(
                  color: PhlioColors.surfaceInput,
                  borderRadius: PhlioRadii.pillRadius,
                  border: Border.all(color: PhlioColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, size: 20, color: PhlioColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        style: PhlioTypography.body,
                        decoration: const InputDecoration(
                          hintText: 'Search chats',
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                    if (query.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(_search.clear),
                        child: const Icon(Icons.close_rounded, size: 18, color: PhlioColors.textMuted),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.md),
              child: _NewChatRow(onTap: _newChat),
            ),
            const SizedBox(height: PhlioSpacing.sm),
            if (state.chats.length > 1 && query.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg, 0, PhlioSpacing.lg, PhlioSpacing.xs),
                child: Text('Previous chats · hold one to move it',
                    style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
              ),
            Expanded(child: list),
          ],
        ),
      ),
    );
  }
}

class _NewChatRow extends StatelessWidget {
  const _NewChatRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: PhlioRadii.lgRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.md, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: PhlioRadii.lgRadius,
          border: Border.all(color: PhlioColors.brandOrange.withValues(alpha: 0.35)),
          color: PhlioColors.brandOrange.withValues(alpha: 0.08),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_comment_outlined, color: PhlioColors.brandOrange, size: 20),
            const SizedBox(width: 10),
            Text('New chat',
                style: PhlioTypography.body.copyWith(
                    color: PhlioColors.brandOrange, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.active,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.query = '',
  });

  final AgentChat chat;
  final bool active;
  final String query;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? PhlioColors.surfaceElevated : Colors.transparent,
        borderRadius: PhlioRadii.lgRadius,
        child: InkWell(
          borderRadius: PhlioRadii.lgRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(PhlioSpacing.md, 10, 0, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (active ? PhlioColors.brandOrange : PhlioColors.textMuted)
                        .withValues(alpha: 0.14),
                  ),
                  child: Icon(Icons.chat_bubble_outline_rounded,
                      size: 17, color: active ? PhlioColors.brandOrange : PhlioColors.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Highlighted(
                        chat.title,
                        query: query,
                        style: PhlioTypography.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${timeago.format(chat.updatedAt)} · ${chat.preview}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Chat options',
                  icon: const Icon(Icons.more_horiz_rounded, color: PhlioColors.textMuted),
                  color: PhlioColors.surfaceElevated,
                  onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: PhlioColors.danger))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The title with the search match picked out in the brand colour.
class _Highlighted extends StatelessWidget {
  const _Highlighted(this.text, {required this.query, required this.style});

  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final i = q.isEmpty ? -1 : text.toLowerCase().indexOf(q);
    if (i < 0) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(
          text: text.substring(i, i + q.length),
          style: const TextStyle(color: PhlioColors.brandOrange),
        ),
        TextSpan(text: text.substring(i + q.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PhlioSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhlioFox(size: 96, pose: PhlioFoxPose.sleepy),
          const SizedBox(height: PhlioSpacing.md),
          Text(title, style: PhlioTypography.title),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
        ],
      ),
    );
  }
}
