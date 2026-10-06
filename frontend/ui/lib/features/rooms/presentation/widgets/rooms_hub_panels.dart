import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../data/datasources/messaging_api.dart';
import '../../domain/entities/room_message_entity.dart';
import 'attachment_preview.dart';

final friendsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(messagingApiProvider).friends());
final roomsSearchProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String, String)>((ref, filter) =>
        ref.watch(messagingApiProvider).search(filter.$1, filter.$2));

Future<void> showRoomsSearch(BuildContext context) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: PhlioColors.roomsSidebar,
        builder: (_) => const FractionallySizedBox(
            heightFactor: .94, child: RoomsSearchPanel()));
Future<void> showRoomsFriends(BuildContext context, {String username = ''}) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: PhlioColors.roomsSidebar,
        builder: (_) => FractionallySizedBox(
            heightFactor: .90, child: RoomsFriendsPanel(username: username)));

class RoomsFriendsPanel extends ConsumerStatefulWidget {
  const RoomsFriendsPanel({this.username = '', super.key});
  final String username;
  @override
  ConsumerState<RoomsFriendsPanel> createState() => _RoomsFriendsPanelState();
}

class _RoomsFriendsPanelState extends ConsumerState<RoomsFriendsPanel> {
  late final _username = TextEditingController(text: widget.username);
  bool _busy = false;
  String? _notice;
  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _act(
      Future<void> Function(MessagingApi) action, String notice) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action(ref.read(messagingApiProvider));
      if (!mounted) return;
      ref.invalidate(friendsProvider);
      setState(() => _notice = notice);
    } catch (_) {
      if (mounted)
        setState(() => _notice =
            'Could not update friends. Check the username; a request may already be pending.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          ListTile(
              title: const Text('Add Friends',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close))),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                const Text(
                    'Find your people. Send a request with their Phlio username.'),
                const SizedBox(height: 16),
                TextField(
                    controller: _username,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.alternate_email),
                        hintText: 'Username'),
                    textInputAction: TextInputAction.done),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_username.text.trim().isEmpty) return;
                            _act((api) => api.addFriend(_username.text.trim()),
                                'Friend request sent.');
                          },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(_busy ? 'Updating…' : 'Send friend request')),
                if (_notice != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_notice!)),
                const SizedBox(height: 24),
                friends.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => TextButton(
                        onPressed: () => ref.invalidate(friendsProvider),
                        child: const Text('Could not load friends. Retry')),
                    data: (items) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (items.isEmpty)
                                const Text(
                                    'Your friends and pending requests will appear here.'),
                              for (final group in [
                                'Requests',
                                'Pending',
                                'Friends'
                              ]) ...[
                                if (items.any((item) => _group(item) == group))
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: Text(group,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700))),
                                for (final item in items
                                    .where((item) => _group(item) == group))
                                  _friend(item),
                              ],
                            ])),
              ])),
        ]));
  }

  String _group(Map item) => item['status'] == 'accepted'
      ? 'Friends'
      : item['incoming'] == true
          ? 'Requests'
          : 'Pending';
  Widget _friend(Map item) {
    final peer = item['peer'] as Map;
    final incoming = item['incoming'] == true && item['status'] == 'pending';
    final accepted = item['status'] == 'accepted';
    return Card(
        color: PhlioColors.roomsInput,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                PhlioAvatar(name: peer['full_name'] as String, size: 36),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(peer['full_name'] as String,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('@${peer['username']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ]))
              ]),
              Wrap(spacing: 8, children: [
                if (incoming)
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              (api) => api.friendAction(
                                  peer['id'] as String, 'accept'),
                              'Friend added.'),
                      child: const Text('Accept')),
                if (accepted)
                  TextButton(
                      onPressed: () {
                        final router = GoRouter.of(context);
                        Navigator.pop(context);
                        router.push(
                            '/dm/${Uri.encodeComponent(peer['id'] as String)}');
                      },
                      child: const Text('Message')),
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            (api) => api.friendAction(
                                peer['id'] as String, 'remove'),
                            'Updated.'),
                    child: Text(accepted
                        ? 'Remove friend'
                        : incoming
                            ? 'Decline'
                            : 'Cancel request')),
              ]),
            ])));
  }
}

class RoomsSearchPanel extends ConsumerStatefulWidget {
  const RoomsSearchPanel({super.key});
  @override
  ConsumerState<RoomsSearchPanel> createState() => _RoomsSearchPanelState();
}

class _RoomsSearchPanelState extends ConsumerState<RoomsSearchPanel> {
  String _query = '';
  String _kind = 'recent';
  Timer? _debounce;
  static const filters = [
    'Recent',
    'People',
    'Media',
    'Pins',
    'Links',
    'Files',
    'Images',
    'Videos',
    'Audio'
  ];
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(roomsSearchProvider((_query, _kind)));
    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          ListTile(
              title: const Text('Search Rooms',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search messages, people, files…'),
                  onChanged: (value) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) setState(() => _query = value.trim());
                    });
                  })),
          SizedBox(
              height: 58 + MediaQuery.textScalerOf(context).scale(12) - 12,
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final label in filters)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                              label: Text(label),
                              selected: _kind == label.toLowerCase(),
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setState(() => _kind = label.toLowerCase()))),
                  ])),
          if (_kind == 'pins')
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Pinned information from your joined rooms.')),
          Expanded(
              child: results.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => Center(
                      child: TextButton(
                          onPressed: () => ref
                              .invalidate(roomsSearchProvider((_query, _kind))),
                          child: const Text('Could not search. Retry'))),
                  data: (items) => items.isEmpty
                      ? const Center(
                          child: Text('No results yet. Try another search.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount:
                              items.length + (items.length == 100 ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == items.length)
                              return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                      'Showing 100 results. Refine your search to find more.'));
                            final item = items[i];
                            if (item['type'] == 'person') {
                              final peer = item['peer'] as Map;
                              return ListTile(
                                  leading: PhlioAvatar(
                                      name: peer['full_name'] as String,
                                      size: 40),
                                  title: Text(peer['full_name'] as String),
                                  subtitle: Text('@${peer['username']}'),
                                  trailing: IconButton(
                                      tooltip: 'Add friend',
                                      icon: const Icon(Icons.person_add_alt_1),
                                      onPressed: () => showRoomsFriends(context,
                                          username:
                                              peer['username'] as String)),
                                  onTap: () => _conversation(
                                      peer: peer['id'] as String));
                            }
                            final attachments =
                                item['attachments'] as List? ?? [];
                            return Card(
                                color: PhlioColors.roomsInput,
                                child: ListTile(
                                    leading: Icon(item['type'] == 'pin'
                                        ? Icons.push_pin_outlined
                                        : attachments.isNotEmpty
                                            ? Icons.attach_file
                                            : Icons.chat_bubble_outline),
                                    title: Text(item['title'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        [
                                          item['text'] as String? ?? '',
                                          ...attachments.map((a) => a['name'])
                                        ]
                                            .where(
                                                (v) => v.toString().isNotEmpty)
                                            .join(' · '),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis),
                                    onTap: () => _preview(item)));
                          }))),
        ]));
  }

  void _conversation({String? peer, String? room}) {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push(peer != null
        ? '/dm/${Uri.encodeComponent(peer)}'
        : '/rooms/${Uri.encodeComponent(room!)}');
  }

  void _preview(Map<String, dynamic> item) {
    final api = ref.read(messagingApiProvider);
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: PhlioColors.roomsSidebar,
        builder: (sheetContext) => FractionallySizedBox(
            heightFactor: .85,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(item['title'] as String,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SelectableText(item['text'] as String? ?? ''),
              for (final a in item['attachments'] as List? ?? [])
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: AttachmentPreview(
                        attachment: MessageAttachmentEntity(
                            id: a['id'] as String? ?? '',
                            kind: a['kind'] as String,
                            name: a['name'] as String,
                            size: (a['size'] as num?)?.toInt() ?? 0,
                            url: a['url'] as String? ?? '',
                            value: a['value'] as String? ?? ''),
                        loadPrivateFile: item['peer_id'] == null
                            ? null
                            : () => api.localFile(a['url'] as String))),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _conversation(
                        peer: item['peer_id'] as String?,
                        room: item['room_id'] as String?);
                  },
                  child: const Text('Open conversation')),
            ])));
  }
}
