import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../controllers/avatar_controller.dart';

String profileInviteLink(String username) =>
    'phlio://app/creator/${Uri.encodeComponent(username)}';

class InviteFriendsScreen extends ConsumerStatefulWidget {
  const InviteFriendsScreen({super.key});
  @override
  ConsumerState<InviteFriendsScreen> createState() => _InviteFriendsState();
}

class _InviteFriendsState extends ConsumerState<InviteFriendsScreen> {
  final search = TextEditingController();
  Timer? debounce;
  List<Map> matches = [], results = [], friends = [];
  List<Contact> contacts = [];
  final hidden = <String>{}, busy = <String>{};
  bool loading = false, searching = false;
  String? error;
  int generation = 0, visible = 5;
  final api = getIt<ApiClient>().dio;
  @override
  void initState() {
    super.initState();
    loadConnections();
  }

  Future<void> loadConnections() async {
    try {
      final response = await api.get('/social/connections');
      if (mounted) {
        setState(
          () => friends = (response.data['friends'] as List).cast<Map>(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load requests. Pull down to retry.');
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void find(String query) {
    debounce?.cancel();
    final request = ++generation;
    if (query.trim().length < 2) {
      setState(() {
        results = [];
        searching = false;
      });
      return;
    }
    setState(() => searching = true);
    debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final response = await api
            .get('/social/find-friends', queryParameters: {'q': query.trim()});
        if (mounted && request == generation) {
          setState(() {
            results = (response.data as List).cast<Map>();
            error = null;
          });
        }
      } catch (_) {
        if (mounted && request == generation) {
          setState(() => error = 'Search could not connect. Please try again.');
        }
      } finally {
        if (mounted && request == generation) setState(() => searching = false);
      }
    });
  }

  Future<void> syncContacts() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        if (mounted) {
          setState(
            () => error =
                'Contacts access is off. You can still search by username or share your QR. Enable Contacts in phone settings to match friends.',
          );
        }
        return;
      }
      final local = await FlutterContacts.getContacts(withProperties: true);
      final phones = local
          .expand((c) => c.phones.map((p) => p.number))
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();
      final found = <String, Map>{};
      final region =
          WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? 'IN';
      for (var start = 0; start < phones.length; start += 300) {
        final response = await api.post(
          '/social/contacts/match',
          data: {
            'phones':
                phones.sublist(start, (start + 300).clamp(0, phones.length)),
            'region': region,
          },
        );
        for (final peer in response.data as List) {
          found[peer['id'] as String] = peer as Map;
        }
      }
      if (mounted) {
        setState(() {
          contacts = local;
          matches = found.values.toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not load contacts. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> add(Map peer, {bool accept = false}) async {
    final id = peer['id'] as String;
    if (!busy.add(id)) return;
    setState(() {});
    try {
      if (accept) {
        await api.post('/social/friendships/$id/accept');
      } else {
        await api.post('/social/friendships', data: {'target_user_id': id});
      }
      await loadConnections();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept ? 'Friend request accepted.' : 'Friend request sent.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not update this request. Refresh and try again.',
        );
      }
    } finally {
      busy.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> inviteContact(Contact contact) async {
    final me = ref.read(authControllerProvider).valueOrNull;
    if (me == null) return;
    final body = 'Join me on Phlio: ${profileInviteLink(me.username)}';
    try {
      final uri = Uri(
        scheme: 'sms',
        path: contact.phones.first.number,
        queryParameters: {'body': body},
      );
      if (!await launchUrl(uri)) throw StateError('No SMS app');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No messaging app available. Share your profile QR instead.',
            ),
          ),
        );
      }
    }
  }

  Widget person(Map peer, {bool contact = false}) {
    final id = peer['id'] as String;
    final relations = friends.where((f) => f['peer']['id'] == id);
    final relation = relations.isEmpty ? null : relations.first;
    final accepted = relation?['status'] == 'accepted';
    final incoming =
        relation?['status'] == 'pending' && relation?['incoming'] == true;
    final pending = relation?['status'] == 'pending' && !incoming;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push('/creator/${peer['username']}'),
            child: PhlioAvatar(
              name: peer['display_name'] as String,
              imageUrl: peer['avatar_url'] as String?,
              size: 58,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer['display_name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '@${peer['username']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (contact)
                  Text(
                    'In your contacts',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: busy.contains(id) || pending || accepted
                ? null
                : () => add(peer, accept: incoming),
            child: Text(
              accepted
                  ? 'Friends'
                  : incoming
                      ? 'Accept'
                      : pending
                          ? 'Sent'
                          : 'Add',
            ),
          ),
          IconButton(
            tooltip: 'Dismiss suggestion',
            onPressed: () => setState(() => hidden.add(id)),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final query = search.text.trim().toLowerCase();
    final people = (query.isEmpty ? matches : results)
        .where((p) => !hidden.contains(p['id']))
        .toList();
    final matchedPhones = matches.map((p) => p['matched_phone']).toSet();
    final outsiders = contacts
        .where(
          (c) =>
              c.phones.isNotEmpty &&
              !c.phones.any((p) => matchedPhones.contains(p.number)) &&
              (query.isEmpty || c.displayName.toLowerCase().contains(query)),
        )
        .take(30);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Invite friends'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: loadConnections,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: search,
              onChanged: find,
              decoration: InputDecoration(
                hintText: 'Add or search friends',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: MeAvatar(name: me?.fullName ?? '', size: 48),
                title: const Text(
                  'Invite friends on Phlio',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('@${me?.username ?? ''}'),
                trailing: const Icon(Icons.qr_code),
                onTap: me == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileInviteQrScreen(),
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: loading ? null : syncContacts,
              icon: const Icon(Icons.contacts_outlined),
              label: Text(
                loading ? 'Finding friends...' : 'Find friends from contacts',
              ),
            ),
            const Text(
              'Phone numbers are used to find matching accounts. Contact names and photos stay on your phone.',
              style: TextStyle(fontSize: 12),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error!),
              ),
            if (loading || searching) const LinearProgressIndicator(),
            if (query.isEmpty) ...[
              for (final f in friends.where(
                (f) => f['status'] == 'pending' && f['incoming'] == true,
              ))
                person(f['peer'] as Map),
            ],
            const SizedBox(height: 24),
            Text(
              query.isEmpty ? 'RECOMMENDED FRIENDS' : 'SEARCH RESULTS',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (people.isEmpty && !loading && !searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Search a username or find friends from your contacts.',
                ),
              ),
            for (final peer in people.take(visible))
              person(peer, contact: query.isEmpty),
            if (people.length > visible)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => visible += 10),
                  child: const Text('Show more'),
                ),
              ),
            if (outsiders.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('INVITE YOUR CONTACTS'),
              for (final contact in outsiders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PhlioAvatar(name: contact.displayName, size: 48),
                  title: Text(contact.displayName),
                  trailing: TextButton(
                    onPressed: () => inviteContact(contact),
                    child: const Text('Invite'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileInviteQrScreen extends ConsumerWidget {
  const ProfileInviteQrScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to invite friends.')),
      );
    }
    final link = profileInviteLink(me.username);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Your Phlio QR'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 60),
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    children: [
                      Text(
                        me.fullName,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                      Text(
                        '@${me.username}',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      QrImageView(
                        data: link,
                        backgroundColor: Colors.white,
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Colors.black,
                        ),
                      ),
                      const Text(
                        'Phlio',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: MeAvatar(name: me.fullName, size: 112),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile link copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Copy link'),
                ),
                FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: 'Add me on Phlio: $link',
                      sharePositionOrigin:
                          const Rect.fromLTWH(24, 100, 100, 100),
                    ),
                  ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share invite'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Open this link on a phone with Phlio installed.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
