import 'package:phlio/shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';

final graphActivityProvider = FutureProvider.autoDispose<List<dynamic>>(
    (ref) async => ((await getIt<ApiClient>().dio.get('/activity/friends')).data
        as Map)['items'] as List);
final graphNotesProvider = FutureProvider.autoDispose<List<dynamic>>(
    (ref) async => ((await getIt<ApiClient>().dio.get('/notes')).data
        as Map)['items'] as List);
final graphPoliciesProvider = FutureProvider.autoDispose<List<dynamic>>(
    (ref) async =>
        (await getIt<ApiClient>().dio.get('/privacy/activity')).data as List);

class SocialGraphScreen extends ConsumerStatefulWidget {
  const SocialGraphScreen({super.key});
  @override
  ConsumerState<SocialGraphScreen> createState() => _SocialGraphScreenState();
}

class _SocialGraphScreenState extends ConsumerState<SocialGraphScreen> {
  bool busy = false;
  Future<void> shareNote() async {
    final recipient = TextEditingController();
    final message = TextEditingController();
    final result = await showDialog<({String peer, String text})>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Send a Phlio Note'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: recipient,
                    decoration:
                        const InputDecoration(labelText: 'Recipient username')),
                const SizedBox(height: 12),
                TextField(
                    controller: message,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'Your note')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, (
                          peer: recipient.text.trim(),
                          text: message.text.trim()
                        )),
                    child: const Text('Send'))
              ],
            ));
    // Dispose after the dialog exit animation releases its fields.
    Future.delayed(const Duration(seconds: 1), () {
      recipient.dispose();
      message.dispose();
    });
    if (result == null || result.peer.isEmpty || result.text.isEmpty) return;
    try {
      await getIt<ApiClient>().dio.post('/notes', data: {
        'recipients': [result.peer],
        'text': result.text
      });
      ref.invalidate(graphNotesProvider);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not send note. Check the recipient and try again.')));
    }
  }

  Future<void> savePolicy(
      Map policy, String audience, String identity, String foxy) async {
    setState(() => busy = true);
    try {
      await getIt<ApiClient>().dio.put('/privacy/activity', data: {
        'platform': 'social',
        'object_type': '*',
        'verb': '*',
        'audience': audience,
        'identity_mode': identity,
        'foxy_access': foxy,
      });
      ref.invalidate(graphPoliciesProvider);
      ref.invalidate(graphActivityProvider);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save privacy settings. Try again.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
            actions: [
              IconButton(
                  tooltip: 'Group messages',
                  icon: const Icon(Icons.group_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const GroupInboxScreen())))
            ],
            title: const Text('Social activity'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Friends'),
              Tab(text: 'Notes'),
              Tab(text: 'Privacy')
            ])),
        body: TabBarView(children: [
          ref.watch(graphActivityProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(graphActivityProvider),
                      child: const Text('Retry activity'))),
              data: (items) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(graphActivityProvider);
                    await ref.read(graphActivityProvider.future);
                  },
                  child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (items.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                  'Activity appears when your friends choose to share it.')),
                        for (final item in items)
                          Card(
                              child: ListTile(
                                  leading: const Icon(Icons.people_outline),
                                  title: Text(item['label'] as String))),
                      ]))),
          Column(children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                    onPressed: shareNote,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Send a note'))),
            Expanded(
                child: ref.watch(graphNotesProvider).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => Center(
                        child: TextButton(
                            onPressed: () => ref.invalidate(graphNotesProvider),
                            child: const Text('Retry notes'))),
                    data: (items) =>
                        ListView(padding: const EdgeInsets.all(16), children: [
                          if (items.isEmpty) const Text('No notes yet.'),
                          for (final note in items)
                            Card(
                                child: ListTile(
                                    title: Text(note['text'] as String))),
                        ]))),
          ]),
          ref.watch(graphPoliciesProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(graphPoliciesProvider),
                      child: const Text('Retry privacy settings'))),
              data: (items) {
                final policy = items
                        .cast<Map>()
                        .where((p) =>
                            p['platform'] == 'social' &&
                            p['object_type'] == '*' &&
                            p['verb'] == '*')
                        .firstOrNull ??
                    {};
                final audience = policy['audience'] as String? ?? 'nobody';
                final identity = policy['identity_mode'] as String? ?? 'hidden';
                final foxy = policy['foxy_access'] as String? ?? 'none';
                return ListView(padding: const EdgeInsets.all(20), children: [
                  const Text('Your social activity',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text(
                      'Choose who can see your Social likes, saves and views. Foxy access is a separate choice. Payments remain private.'),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: ['nobody', 'friends', 'followers', 'public']
                              .contains(audience)
                          ? audience
                          : 'nobody',
                      decoration: const InputDecoration(
                          labelText: 'Share activity with'),
                      items: const [
                        DropdownMenuItem(
                            value: 'nobody', child: Text('Only me')),
                        DropdownMenuItem(
                            value: 'friends', child: Text('Friends')),
                        DropdownMenuItem(
                            value: 'followers', child: Text('Followers')),
                        DropdownMenuItem(
                            value: 'public', child: Text('Everyone'))
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v != null)
                                savePolicy(policy, v, identity, foxy);
                            }),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: identity,
                      decoration: const InputDecoration(
                          labelText: 'Identity on shared activity'),
                      items: const [
                        DropdownMenuItem(
                            value: 'hidden', child: Text('Hidden')),
                        DropdownMenuItem(
                            value: 'anonymous', child: Text('Anonymous')),
                        DropdownMenuItem(
                            value: 'identified', child: Text('Show my name'))
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v != null)
                                savePolicy(policy, audience, v, foxy);
                            }),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: foxy,
                      decoration: const InputDecoration(
                          labelText: 'Allow Foxy to use this activity'),
                      items: const [
                        DropdownMenuItem(
                            value: 'none', child: Text('No access')),
                        DropdownMenuItem(
                            value: 'personal',
                            child: Text('My personal context')),
                        DropdownMenuItem(
                            value: 'group',
                            child: Text('Authorized group context')),
                        DropdownMenuItem(
                            value: 'both',
                            child: Text('Personal and group context'))
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v != null)
                                savePolicy(policy, audience, identity, v);
                            }),
                  if (busy)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator()),
                ]);
              }),
        ]),
      ));
}
