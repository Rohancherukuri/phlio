import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../data/datasources/messaging_api.dart';
import '../controllers/messaging_controller.dart';

Future<void> showDirectMessagesPanel(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.roomsSidebar,
      builder: (_) => const _DirectMessagesPanel(),
    );

class _DirectMessagesPanel extends ConsumerStatefulWidget {
  const _DirectMessagesPanel();
  @override
  ConsumerState<_DirectMessagesPanel> createState() =>
      _DirectMessagesPanelState();
}

class _DirectMessagesPanelState extends ConsumerState<_DirectMessagesPanel> {
  final _username = TextEditingController();
  bool _opening = false;
  String? _error;
  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _open(String username) async {
    if (username.trim().isEmpty || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final peer = await ref.read(messagingApiProvider).peer(username.trim());
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/dm/${Uri.encodeComponent(peer['id'] as String)}');
    } catch (_) {
      if (mounted)
        setState(() {
          _opening = false;
          _error =
              'Could not find this person. Check the username and try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(dmConversationsProvider);
    return SafeArea(
        child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Messages', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(
              controller: _username,
              enabled: !_opening,
              onSubmitted: _open,
              decoration: InputDecoration(
                  hintText: 'Message someone by username',
                  prefixIcon: const Icon(Icons.alternate_email),
                  suffixIcon: IconButton(
                      tooltip: 'Start conversation',
                      onPressed: _opening ? null : () => _open(_username.text),
                      icon: const Icon(Icons.arrow_forward_rounded)))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(color: PhlioColors.danger))),
          const SizedBox(height: 16),
          Expanded(
              child: conversations.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
                child: TextButton(
                    onPressed: () => ref.invalidate(dmConversationsProvider),
                    child: const Text('Could not load messages. Retry'))),
            data: (items) => items.isEmpty
                ? const Center(child: Text('Your conversations start here.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final peer = item['peer'] as Map;
                      return ListTile(
                        leading: PhlioAvatar(
                            profileId: peer['id'] as String,
                            imageUrl: peer['avatar_url'] as String?,
                            name: peer['full_name'] as String,
                            size: 40),
                        title: Text(peer['full_name'] as String,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            (item['last_message'] as Map?)?['text']
                                    as String? ??
                                'Start a conversation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => _open(peer['id'] as String),
                      );
                    },
                  ),
          )),
        ]),
      ),
    ));
  }
}
