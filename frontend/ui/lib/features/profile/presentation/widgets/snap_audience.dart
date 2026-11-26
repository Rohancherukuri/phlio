import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/widgets/phlio_card.dart';
class SnapAudience {
  const SnapAudience({this.mode = 'friends', this.recipients = const [], this.listName});
  final String mode;
  final List<String> recipients;

  /// Set when the audience is one of your lists (sent as close_friends
  /// with that list's members).
  final String? listName;
  String get label => listName != null
      ? '$listName (${recipients.length})'
      : mode == 'everyone' ? 'Everyone' : mode == 'close_friends' ? 'Close Friends (${recipients.length})' : 'Friends';
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
  // Your lists (Close friends first): /social/snap-lists.
  late final Future<List> lists = getIt<ApiClient>().dio.get('/social/snap-lists').then((r) => r.data as List);
  String? listId;
  String search = '';
  @override Widget build(BuildContext context) => SizedBox(height: MediaQuery.sizeOf(context).height * .8, child: Column(children: [
    const Text('Who can view this?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    for (final option in [('friends','Friends'),('everyone','Everyone on Phlio'),('close_friends','Close Friends'),('list','Lists')]) RadioListTile<String>(value: option.$1, groupValue: mode, onChanged: (value) => setState(() => mode = value!), title: Text(option.$2), subtitle: option.$1 == 'list' ? const Text('Share with one of your audience lists') : null),
    if (mode == 'list') Expanded(child: FutureBuilder<List>(future: lists, builder: (_, state) {
      if (state.hasError) return const Center(child: Text('Could not load your lists. Close and try again.'));
      if (!state.hasData) return const Center(child: CircularProgressIndicator());
      final usable = [for (final l in state.data!) if ((l['member_ids'] as List? ?? const []).isNotEmpty) l];
      if (usable.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Text('No lists with people yet. Make one with New list when you send a snap, then add people who follow you.', textAlign: TextAlign.center));
      return ListView(children: [for (final l in usable) RadioListTile<String>(value: '${l['id']}', groupValue: listId, onChanged: (v) => setState(() => listId = v), secondary: CircleAvatar(backgroundColor: l['close'] == true ? const Color(0xFF2BC25B) : const Color(0xFF8D78FF), child: Icon(l['close'] == true ? Icons.star_rounded : Icons.groups_2_outlined, color: Colors.white, size: 20)), title: Text('${l['name']}'), subtitle: Text('${(l['member_ids'] as List).length} people'))]);
    })),
    if (mode == 'close_friends') Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(onChanged: (v) => setState(() => search = v.toLowerCase()), decoration: const InputDecoration(hintText: 'Search your followers', prefixIcon: Icon(Icons.search)))),
    if (mode != 'list') Expanded(child: mode != 'close_friends' ? Center(child: Text(mode == 'everyone' ? 'Anyone signed in to Phlio can view this.' : 'Your accepted friends can view this.')) : FutureBuilder<List>(future: followers, builder: (_, state) {
      if (state.hasError) return const Center(child: Text('Could not load followers. Close and try again.'));
      if (!state.hasData) return const Center(child: CircularProgressIndicator());
      final people = state.data!.where((p) => '${p['username']} ${p['display_name']}'.toLowerCase().contains(search)).toList();
      if (people.isEmpty) return const Center(child: Text('No matching followers.'));
      return ListView(children: [for (final p in people) CheckboxListTile(value: selected.contains(p['id']), onChanged: (v) => setState(() { if (v == true) { selected.add(p['id'] as String); } else { selected.remove(p['id']); } }), secondary: PhlioAvatar(name: p['display_name'] as String, imageUrl: p['avatar_url'] as String?, size: 40), title: Text(p['display_name'] as String), subtitle: Text('@${p['username']}'))]);
    })),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: (mode == 'close_friends' && selected.isEmpty) || (mode == 'list' && listId == null) ? null : () async {
      if (mode == 'list') {
        final all = await lists;
        final picked = all.firstWhere((l) => '${l['id']}' == listId);
        if (!context.mounted) return;
        Navigator.pop(context, SnapAudience(mode: 'close_friends', recipients: [for (final id in picked['member_ids'] as List) '$id'], listName: '${picked['name']}'));
        return;
      }
      Navigator.pop(context, SnapAudience(mode: mode, recipients: mode == 'close_friends' ? selected.toList() : []));
    }, child: const Text('Done')))),
  ]));
}
