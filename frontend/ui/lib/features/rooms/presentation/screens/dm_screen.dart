import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../data/datasources/messaging_api.dart';
import '../controllers/messaging_controller.dart';
import '../widgets/dm_thread.dart';
import '../../../../shared/appearance/chat_theme_sheet.dart';
import '../../../../shared/blend/blend.dart';
import '../../../../shared/watch/watch_together.dart';

/// Private conversation with media, voice/video calls and message reactions.
/// Profile Chat uses its own public creator channel.
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
            PhlioAvatar(
                name: name, imageUrl: peer?['avatar_url'] as String?, size: 36),
            const SizedBox(width: 10),
            // Instagram header: bold name with a chevron, handle below.
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.title.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 20, color: PhlioColors.textMuted),
                  ]),
                  Text(peer?['username'] as String? ?? widget.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.caption),
                ])),
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
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              switch (v) {
                case 'watch':
                  openWatchTogether(context, WatchCtx('dm', widget.username, title: name));
                case 'blend':
                  startBlendWith(context, widget.username);
                case 'theme':
                  showChatThemeSheet(context, widget.username);
                case 'search':
                  setState(() => _searching = !_searching);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'watch', child: ListTile(leading: Icon(Icons.smart_display_outlined), title: Text('Watch together'))),
              PopupMenuItem(value: 'blend', child: ListTile(leading: Icon(Icons.join_inner_rounded), title: Text('Blend'))),
              PopupMenuItem(value: 'theme', child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('Chat theme'))),
              PopupMenuItem(value: 'search', child: ListTile(leading: Icon(Icons.search_rounded), title: Text('Search'))),
            ],
          ),
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
