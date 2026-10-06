import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../data/datasources/messaging_api.dart';
import '../controllers/messaging_controller.dart';
import '../widgets/dm_thread.dart';

/// Pushed 1:1 conversation: peer header with voice/video calls and search,
/// over the shared [DmThread] (the same thread the creator profile's Chat
/// tab embeds — reactions, attachments and voice all live there).
class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({required this.username, super.key});
  final String username;
  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  bool _calling = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _call(bool video, String name) async {
    if (_calling || ref.read(activeCallProvider)) return;
    setState(() => _calling = true);
    final api = ref.read(messagingApiProvider);
    try {
      final call = await api.startCall(widget.username, video);
      if (!mounted) {
        await api.action(call['id'] as String, 'end');
        return;
      }
      await context.push('/call/${call['id']}',
          extra: {'name': name, 'video': video, 'incoming': false});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not start the call. They may be in another call. Please try again.')));
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerAsync = ref.watch(dmPeerProvider(widget.username));
    final peer = peerAsync.valueOrNull;
    final name = peer?['full_name'] as String? ?? widget.username;
    return Scaffold(
      backgroundColor: PhlioColors.roomsSidebar,
      appBar: AppBar(
        backgroundColor: PhlioColors.roomsSidebar,
        titleSpacing: 0,
        title: GestureDetector(
          // Peer profile from the header avatar/name.
          onTap: () => context.push('/creator/${widget.username}'),
          child: Row(children: [
            PhlioAvatar(name: name, size: 32),
            const SizedBox(width: 10),
            Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.title)),
          ]),
        ),
        actions: [
          IconButton(
              tooltip: 'Voice call',
              icon: const Icon(Icons.call_outlined),
              onPressed:
                  peer == null || _calling ? null : () => _call(false, name)),
          IconButton(
              tooltip: 'Video call',
              icon: const Icon(Icons.videocam_outlined),
              onPressed:
                  peer == null || _calling ? null : () => _call(true, name)),
          IconButton(
              tooltip: 'Search messages',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() => _searching = !_searching)),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          if (_searching)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        hintText: 'Search this conversation',
                        prefixIcon: Icon(Icons.search)))),
          Expanded(
            child: DmThread(
              username: widget.username,
              searchQuery: _searching ? _search.text : null,
            ),
          ),
        ]),
      ),
    );
  }
}
