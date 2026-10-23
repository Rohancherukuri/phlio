import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/widgets/phlio_card.dart';
class SnapAudience {
  const SnapAudience({this.mode = 'friends', this.recipients = const []});
  final String mode;
  final List<String> recipients;
  String get label => mode == 'everyone' ? 'Everyone' : mode == 'close_friends' ? 'Close Friends (${recipients.length})' : 'Friends';
}
Future<SnapAudience?> pickSnapAudience(BuildContext context, SnapAudience selected) => showModalBottomSheet<SnapAudience>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => _AudiencePicker(selected));
class _AudiencePicker extends StatefulWidget {
  const _AudiencePicker(this.initial);
  final SnapAudience initial;
  @override State<_AudiencePicker> createState() => _AudienceState();
}
class _AudienceState extends State<_AudiencePicker> {
  late String mode = widget.initial.mode;
  late Set<String> selected = widget.initial.recipients.toSet();
  late final Future<List> followers = getIt<ApiClient>().dio.get('/social/connections').then((r) => r.data['followers'] as List);
  String search = '';
  @override Widget build(BuildContext context) => SizedBox(height: MediaQuery.sizeOf(context).height * .8, child: Column(children: [
    const Text('Who can view this?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    for (final option in [('friends','Friends'),('everyone','Everyone on Phlio'),('close_friends','Close Friends')]) RadioListTile<String>(value: option.$1, groupValue: mode, onChanged: (value) => setState(() => mode = value!), title: Text(option.$2)),
    if (mode == 'close_friends') Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(onChanged: (v) => setState(() => search = v.toLowerCase()), decoration: const InputDecoration(hintText: 'Search your followers', prefixIcon: Icon(Icons.search)))),
    Expanded(child: mode != 'close_friends' ? Center(child: Text(mode == 'everyone' ? 'Anyone signed in to Phlio can view this.' : 'Your accepted friends can view this.')) : FutureBuilder<List>(future: followers, builder: (_, state) {
      if (state.hasError) return const Center(child: Text('Could not load followers. Close and try again.'));
      if (!state.hasData) return const Center(child: CircularProgressIndicator());
      final people = state.data!.where((p) => '${p['username']} ${p['display_name']}'.toLowerCase().contains(search)).toList();
      if (people.isEmpty) return const Center(child: Text('No matching followers.'));
      return ListView(children: [for (final p in people) CheckboxListTile(value: selected.contains(p['id']), onChanged: (v) => setState(() { if (v == true) { selected.add(p['id'] as String); } else { selected.remove(p['id']); } }), secondary: PhlioAvatar(name: p['display_name'] as String, imageUrl: p['avatar_url'] as String?, size: 40), title: Text(p['display_name'] as String), subtitle: Text('@${p['username']}'))]);
    })),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: mode == 'close_friends' && selected.isEmpty ? null : () => Navigator.pop(context, SnapAudience(mode: mode, recipients: mode == 'close_friends' ? selected.toList() : [])), child: const Text('Done')))),
  ]));
}
