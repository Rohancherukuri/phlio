import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/shell/account_switcher.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../../../social/presentation/screens/social_graph_screen.dart';
import '../../data/datasources/messaging_api.dart';
import '../controllers/messaging_controller.dart';
import '../widgets/direct_messages_panel.dart';
import 'create_group_screen.dart';

class ChatsInboxScreen extends ConsumerStatefulWidget {
  const ChatsInboxScreen({super.key});
  @override
  ConsumerState<ChatsInboxScreen> createState() => _ChatsInboxScreenState();
}

class _ChatsInboxScreenState extends ConsumerState<ChatsInboxScreen> {
  String query = '', folder = 'primary';
  bool unreadOnly = false;
  Future<void> refresh() async {
    ref.invalidate(dmConversationsProvider);
    ref.invalidate(groupsProvider);
    await ref.read(dmConversationsProvider.future);
  }

  Future<void> open(Map peer) async {
    final api = ref.read(messagingApiProvider);
    try {
      await api.dio.patch('${api.peerPath(peer['id'] as String)}/inbox',
          data: {'read': true});
    } catch (_) {}
    if (!mounted) return;
    await context.push('/dm/${Uri.encodeComponent(peer['id'] as String)}');
    if (mounted) ref.invalidate(dmConversationsProvider);
  }

  Future<void> move(Map item) async {
    final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('Move conversation')),
              for (final value in ['primary', 'general', 'requests'])
                ListTile(
                    title: Text(label(value)),
                    trailing: value == item['folder']
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, value)),
            ])));
    if (selected == null || !mounted) return;
    try {
      final api = ref.read(messagingApiProvider);
      await api.dio.patch(
          '${api.peerPath((item['peer'] as Map)['id'] as String)}/inbox',
          data: {'folder': selected});
      ref.invalidate(dmConversationsProvider);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not move conversation. Try again.')));
    }
  }

  String label(String value) => value[0].toUpperCase() + value.substring(1);
  String preview(Map item) {
    final message = item['last_message'] as Map?;
    if (message == null) return 'Start a conversation';
    final text = message['text'] as String? ?? '';
    final content = text.isNotEmpty
        ? text
        : ((message['attachments'] as List?)?.isNotEmpty == true
            ? 'Sent an attachment'
            : 'Message');
    final date = DateTime.tryParse(message['created_at'] as String? ?? '');
    return '$content${date == null ? '' : ' · ${timeago.format(date, locale: 'en_short')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final conversations = ref.watch(dmConversationsProvider);
    final items = conversations.valueOrNull ?? [];
    final filtered = items.where((item) {
      final peer = item['peer'] as Map;
      return (item['folder'] ?? 'primary') == folder &&
          (!unreadOnly || (item['unread_count'] as int? ?? 0) > 0) &&
          '${peer['full_name']} ${peer['username']} ${preview(item)}'
              .toLowerCase()
              .contains(query);
    }).toList();
    return Scaffold(
        appBar: AppBar(
            centerTitle: true,
            title: InkWell(
                onTap: () => showAccountSwitcher(context),
                borderRadius: BorderRadius.circular(12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: Text(me?.username ?? 'Messages',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700))),
                  const Icon(Icons.keyboard_arrow_down, size: 20)
                ])),
            actions: [
              IconButton(
                  tooltip: 'Create group',
                  icon: const Icon(Icons.group_add_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const CreateGroupScreen()))),
              IconButton(
                  tooltip: 'New message',
                  icon: const Icon(Icons.edit_square),
                  onPressed: () async {
                    await showDirectMessagesPanel(context);
                    if (mounted) ref.invalidate(dmConversationsProvider);
                  })
            ]),
        body: RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      sliver: SliverToBoxAdapter(
                          child: TextField(
                              onChanged: (v) => setState(
                                  () => query = v.trim().toLowerCase()),
                              decoration: InputDecoration(
                                  hintText: 'Search messages',
                                  prefixIcon: const Icon(Icons.search),
                                  filled: true,
                                  fillColor: PhlioColors.surfaceInput,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(32),
                                      borderSide: BorderSide.none))))),
                  SliverToBoxAdapter(
                      child: SizedBox(
                          height: 128,
                          child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                contact(
                                    me?.username ?? 'You',
                                    me?.avatarUrl,
                                    () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const SocialGraphScreen(
                                                    initialTab: 1))),
                                    caption: 'Your notes',
                                    own: true),
                                for (final item in items.take(12))
                                  contact(
                                      (item['peer'] as Map)['full_name']
                                          as String,
                                      (item['peer'] as Map)['avatar_url']
                                          as String?,
                                      () => open(item['peer'] as Map)),
                              ]))),
                  SliverToBoxAdapter(
                      child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          child: Row(children: [
                            FilterChip(
                                label: const Text('Unread'),
                                avatar: const Icon(Icons.tune, size: 18),
                                selected: unreadOnly,
                                onSelected: (value) =>
                                    setState(() => unreadOnly = value)),
                            const SizedBox(width: 8),
                            for (final value in [
                              'primary',
                              'requests',
                              'general'
                            ])
                              Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                      label: Text(label(value)),
                                      selected: folder == value,
                                      onSelected: (_) =>
                                          setState(() => folder = value))),
                          ]))),
                  if (conversations.isLoading)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (conversations.hasError)
                    SliverToBoxAdapter(
                        child: TextButton(
                            onPressed: refresh,
                            child: const Text('Could not load chats. Retry'))),
                  if (!conversations.isLoading &&
                      !conversations.hasError &&
                      filtered.isEmpty)
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(children: [
                              const Icon(Icons.forum_outlined, size: 42),
                              const SizedBox(height: 12),
                              Text(
                                  query.isNotEmpty
                                      ? 'No matching conversations'
                                      : folder == 'requests'
                                          ? 'No message requests'
                                          : 'No ${label(folder).toLowerCase()} conversations yet',
                                  textAlign: TextAlign.center)
                            ]))),
                  SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                    final item = filtered[index], peer = item['peer'] as Map;
                    final unread = (item['unread_count'] as int? ?? 0) > 0;
                    return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        leading: PhlioAvatar(
                            name: peer['full_name'] as String,
                            imageUrl: peer['avatar_url'] as String?,
                            size: 58),
                        title: Text(peer['full_name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        subtitle: Text(preview(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: unread
                                    ? PhlioColors.textPrimary
                                    : PhlioColors.textMuted,
                                fontSize: 13)),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          if (unread)
                            const Icon(Icons.circle,
                                size: 8, color: PhlioColors.brandViolet),
                          IconButton(
                              tooltip: 'Conversation options',
                              onPressed: () => move(item),
                              icon: const Icon(Icons.more_horiz))
                        ]),
                        onTap: () => open(peer),
                        onLongPress: () => move(item));
                  }, childCount: filtered.length)),
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const GroupInboxScreen())),
                              icon: const Icon(Icons.group_outlined),
                              label: const Text('Group conversations')))),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ])));
  }

  Widget contact(String name, String? image, VoidCallback tap,
          {String? caption, bool own = false}) =>
      SizedBox(
          width: 94,
          child: InkWell(
              onTap: tap,
              borderRadius: BorderRadius.circular(18),
              child: Column(children: [
                const SizedBox(height: 4),
                Stack(children: [
                  if (own)
                    MeAvatar(name: name, size: 72)
                  else
                    PhlioAvatar(name: name, imageUrl: image, size: 72),
                  if (own)
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: PhlioColors.surfaceElevated,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.edit, size: 17)))
                ]),
                const SizedBox(height: 10),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(caption ?? name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
              ])));
}
