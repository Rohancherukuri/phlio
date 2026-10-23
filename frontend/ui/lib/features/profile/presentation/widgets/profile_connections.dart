import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';

final profileConnectionsProvider = FutureProvider.autoDispose<Map>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/social/connections')).data as Map;
});

Future<void> showProfileConnections(BuildContext context, String kind) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileConnectionsScreen(initialKind: kind)));

class ProfileConnectionsScreen extends ConsumerStatefulWidget {
  const ProfileConnectionsScreen({super.key, this.initialKind = 'followers'});
  final String initialKind;
  @override
  ConsumerState<ProfileConnectionsScreen> createState() => _ConnectionsState();
}

class _ConnectionsState extends ConsumerState<ProfileConnectionsScreen> {
  String query = '';
  bool alphabetical = false;
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final state = ref.watch(profileConnectionsProvider);
    return DefaultTabController(
        length: 2,
        initialIndex: widget.initialKind == 'following' ? 1 : 0,
        child: Scaffold(
            appBar: AppBar(
                centerTitle: true,
                title: Text(me?.username ?? 'Connections'),
                bottom: TabBar(tabs: [
                  Tab(
                      text:
                          '${(state.valueOrNull?['followers'] as List?)?.length ?? 0} followers'),
                  Tab(
                      text:
                          '${(state.valueOrNull?['following'] as List?)?.length ?? 0} following'),
                ])),
            body: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                      onChanged: (value) => setState(() => query = value
                          .trim()
                          .toLowerCase()
                          .replaceFirst(RegExp(r'^@'), '')),
                      decoration: const InputDecoration(
                          hintText: 'Search by username',
                          prefixIcon: Icon(Icons.search)))),
              ListTile(
                  title: Text(
                      'Sorted by ${alphabetical ? 'Username' : 'Default'}'),
                  trailing: IconButton(
                      tooltip: 'Change sort order',
                      icon: const Icon(Icons.swap_vert),
                      onPressed: () =>
                          setState(() => alphabetical = !alphabetical))),
              Expanded(
                  child: state.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => Center(
                          child: TextButton(
                              onPressed: () =>
                                  ref.invalidate(profileConnectionsProvider),
                              child:
                                  const Text('Could not load people. Retry'))),
                      data: (data) => TabBarView(children: [
                            for (final kind in ['followers', 'following'])
                              people(data[kind] as List? ?? []),
                          ]))),
            ])));
  }

  Widget people(List source) {
    final rows = source
        .where((p) => (p['username'] as String).toLowerCase().contains(query))
        .toList();
    if (alphabetical)
      rows.sort((a, b) =>
          (a['username'] as String).compareTo(b['username'] as String));
    if (rows.isEmpty)
      return Center(
          child:
              Text(query.isEmpty ? 'No people yet' : 'No matching usernames'));
    return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileConnectionsProvider);
          await ref.read(profileConnectionsProvider.future);
        },
        child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final p = rows[index] as Map;
              return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: PhlioAvatar(
                      name: p['display_name'] as String,
                      imageUrl: p['avatar_url'] as String?,
                      size: 56),
                  title: Text(p['username'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p['display_name'] as String,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: FilledButton.tonal(
                      onPressed: () => context.push(
                          '/dm/${Uri.encodeComponent(p['id'] as String)}'),
                      child: const Text('Message')),
                  onTap: () => context.push(
                      '/creator/${Uri.encodeComponent(p['id'] as String)}'));
            }));
  }
}
