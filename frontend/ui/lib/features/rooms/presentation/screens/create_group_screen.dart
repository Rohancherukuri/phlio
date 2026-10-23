import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/content/content_surface.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupState();
}

class _CreateGroupState extends ConsumerState<CreateGroupScreen> {
  final name = TextEditingController();
  final selected = <String>{};
  String query = '';
  bool busy = false;
  String? error;
  late Future<List> people;
  @override
  void initState() {
    super.initState();
    people = load();
  }

  Future<List> load() async =>
      ((await getIt<ApiClient>().dio.get('/sharing/destinations')).data
          as Map)['people'] as List;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = (await getIt<ApiClient>().dio.post('/messaging/groups',
              data: {'name': name.text.trim(), 'members': selected.toList()}))
          .data as Map;
      ref.invalidate(groupsProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => GroupChatScreen(groupId: result['id'] as String)));
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Could not create group. Check the members and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                controller: name,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Group name'))),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
                onChanged: (v) =>
                    setState(() => query = v.trim().toLowerCase()),
                decoration: const InputDecoration(
                    hintText: 'Search name or username',
                    prefixIcon: Icon(Icons.search)))),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Choose 2–20 people · ${selected.length} selected')),
        if (error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
        Expanded(
            child: FutureBuilder<List>(
                future: people,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Center(
                        child: TextButton(
                            onPressed: () => setState(() => people = load()),
                            child: const Text('Could not load people. Retry')));
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final rows = snapshot.data!
                      .where((p) => '${p['display_name']} ${p['username']}'
                          .toLowerCase()
                          .contains(query))
                      .toList();
                  if (rows.isEmpty)
                    return const Center(child: Text('No matching people'));
                  return ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final p = rows[index] as Map,
                            id = rows[index]['id'] as String;
                        return CheckboxListTile(
                            value: selected.contains(id),
                            secondary: PhlioAvatar(
                                name: p['display_name'] as String,
                                imageUrl: p['avatar_url'] as String?,
                                size: 44),
                            title: Text(p['display_name'] as String),
                            subtitle: Text('@${p['username']}'),
                            onChanged: busy
                                ? null
                                : (value) => setState(() {
                                      if (value == false) {
                                        selected.remove(id);
                                      } else if (selected.length < 20) {
                                        selected.add(id);
                                      }
                                    }));
                      });
                })),
        Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed:
                        busy || selected.length < 2 || name.text.trim().isEmpty
                            ? null
                            : create,
                    child: Text(busy ? 'Creating…' : 'Create group')))),
      ])));
}
