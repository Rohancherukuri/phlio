import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/social/presentation/controllers/video_library.dart';
import '../../features/social/presentation/controllers/video_playback_controller.dart';

final engagementProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, path) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/content/$path/engagement')).data
      as Map;
});
final contentProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, path) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final result = (await getIt<ApiClient>().dio.get('/content/$path')).data as Map;
  try {
    await getIt<ApiClient>().dio.put('/content/$path/actions/viewed');
  } catch (_) {}
  ref.invalidate(engagementProvider(path));
  return result;
});
final catalogProvider =
    FutureProvider.autoDispose.family<List, String>((ref, platform) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return ((await getIt<ApiClient>().dio.get('/content/$platform')).data
      as Map)['items'] as List;
});
final groupsProvider = FutureProvider.autoDispose<List>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/messaging/groups')).data as List;
});

class ContentSurface extends StatelessWidget {
  const ContentSurface(
      {required this.platform,
      required this.contentId,
      required this.child,
      super.key,
      this.showEngagement = true});
  final String platform, contentId;
  final Widget child;
  final bool showEngagement;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onLongPress: () => showContentShare(context, '$platform/$contentId'),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              child,
              if (showEngagement) EngagementRow(path: '$platform/$contentId'),
            ]),
      );
}

class EngagementRow extends ConsumerStatefulWidget {
  const EngagementRow({required this.path, super.key});
  final String path;
  @override
  ConsumerState<EngagementRow> createState() => _EngagementRowState();
}

class _EngagementRowState extends ConsumerState<EngagementRow> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(engagementProvider(widget.path));
    final data = state.valueOrNull;
    final people = (data?['avatars'] as List?) ?? [];
    final count = (data?['count'] as int?) ?? 0;
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: LayoutBuilder(builder: (context, constraints) {
          final children = <Widget>[
            SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: 'Like content',
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              await getIt<ApiClient>()
                                  .dio
                                  .put('/content/${widget.path}/like');
                              ref.invalidate(engagementProvider(widget.path));
                              ref.invalidate(contentLibraryProvider);
                            } catch (_) {
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Could not update like. Try again.')));
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: Icon(
                        data?['liked_by_me'] == true
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: data?['liked_by_me'] == true
                            ? Colors.pinkAccent
                            : null))),
            if (people.isNotEmpty)
              SizedBox(
                  width: 24 + (people.length - 1) * 14,
                  height: 28,
                  child: Stack(children: [
                    for (var i = 0; i < people.length; i++)
                      Positioned(
                          left: i * 14.0,
                          top: 2,
                          child: PhlioAvatar(
                              name: people[i]['display_name'] as String? ?? '',
                              imageUrl: people[i]['avatar_url'] as String?,
                              profileId: people[i]['id'] as String,
                              size: 24))
                  ])),
            const SizedBox(width: 5),
            Expanded(
                child: GestureDetector(
                    onTap: data == null
                        ? null
                        : () => showModalBottomSheet(
                            context: context,
                            builder: (_) => SafeArea(
                                    child:
                                        ListView(shrinkWrap: true, children: [
                                  const ListTile(title: Text('Likes')),
                                  for (final person in data['people'] as List)
                                    ListTile(
                                        leading: PhlioAvatar(
                                            name: person['display_name']
                                                as String,
                                            imageUrl:
                                                person['avatar_url'] as String?,
                                            profileId: person['id'] as String,
                                            size: 36),
                                        title: Text(
                                            person['display_name'] as String),
                                        onTap: () {
                                          Navigator.pop(context);
                                          context
                                              .push('/creator/${person['id']}');
                                        }),
                                  if (count > (data['people'] as List).length)
                                    const ListTile(
                                        title: Text(
                                            'Some people chose to stay anonymous.')),
                                ]))),
                    child: Text(
                        state.isLoading
                            ? 'Loading likes…'
                            : state.hasError
                                ? 'Likes unavailable'
                                : count == 0
                                    ? 'Be the first to like'
                                    : people.isNotEmpty && count > people.length
                                        ? '${count - people.length} more liked'
                                        : '$count liked',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)))),
            SizedBox(
                width: 28,
                height: 32,
                child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 17,
                    tooltip: 'Share content',
                    onPressed: () => showContentShare(context, widget.path),
                    icon: const Icon(Icons.ios_share))),
          ];
          if (constraints.maxWidth < 220) {
            final label = (children[children.length - 2] as Expanded).child;
            return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    ...children.take(children.length - 2),
                    const Spacer(),
                    children.last
                  ]),
                  label,
                ]);
          }
          final likes = Row(children: children);
          if (!widget.path.startsWith('social/') &&
              !widget.path.startsWith('news/')) return likes;
          Widget action(
                  String verb, String label, IconData icon, String countKey) =>
              TextButton.icon(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(40, 36)),
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await getIt<ApiClient>()
                              .dio
                              .put('/content/${widget.path}/actions/$verb');
                          ref.invalidate(engagementProvider(widget.path));
                          ref.invalidate(contentLibraryProvider);
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Could not update content. Try again.')));
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: Icon(icon,
                    size: 17,
                    color: data?['${verb}_by_me'] == true
                        ? const Color(0xFF8D78FF)
                        : null),
                label: Text('${data?[countKey] ?? 0}',
                    semanticsLabel: '$label ${data?[countKey] ?? 0}'),
              );
          return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                likes,
                Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      action(
                          'saved',
                          'Bookmarks',
                          data?['saved_by_me'] == true
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          'bookmarks_count'),
                      action(
                          'reposted', 'Reposts', Icons.repeat, 'reposts_count'),
                      Text('${data?['shares_count'] ?? 0} shares',
                          style: const TextStyle(fontSize: 11)),
                      const Icon(Icons.visibility_outlined, size: 15),
                      Text('${data?['views_count'] ?? 0}',
                          style: const TextStyle(fontSize: 11)),
                    ]),
              ]);
        }));
  }
}

Future<void> showContentShare(BuildContext context, String path) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ShareSheet(path: path));

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.path});
  final String path;
  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  late Future<Map> destinations;
  String mode = 'dm', query = '';
  bool busy = false;
  final selected = <String>{};
  final name = TextEditingController(text: 'Shared plans');
  String? error;
  @override
  void initState() {
    super.initState();
    destinations = getIt<ApiClient>()
        .dio
        .get('/sharing/destinations')
        .then((r) => r.data as Map);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> send(String destination, String? target) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = (await getIt<ApiClient>()
              .dio
              .post('/content/${widget.path}/share', data: {
        'destination': destination,
        'target': target,
        'members': selected.toList(),
        'name': name.text.trim().isEmpty ? 'Shared plans' : name.text.trim()
      }))
          .data as Map;
      ref.invalidate(groupsProvider);
      ref.invalidate(engagementProvider(widget.path));
      ref.invalidate(contentLibraryProvider);
      if (!mounted) return;
      final parent = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      parent.pop();
      if (destination == 'group' || destination == 'new_group') {
        parent.push(MaterialPageRoute(
            builder: (_) =>
                GroupChatScreen(groupId: result['target'] as String)));
      } else
        messenger
            .showSnackBar(const SnackBar(content: Text('Content shared.')));
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Could not share. Check the recipients and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get link => 'phlio://app/shared/${widget.path}';
  Future<void> external(String action) async {
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: link));
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Link copied')));
      } else if (action == 'story') {
        await getIt<ApiClient>().dio.post('/content/${widget.path}/story');
        ref.invalidate(sharedStoriesProvider);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Added to your story for 24 hours')));
      } else if (action == 'whatsapp') {
        final opened = await launchUrl(Uri.https('wa.me', '/', {'text': link}),
            mode: LaunchMode.externalApplication);
        if (!opened) throw StateError('WhatsApp unavailable');
      } else {
        final box = context.findRenderObject() as RenderBox;
        await SharePlus.instance.share(ShareParams(
            text: link,
            subject: 'Shared on Phlio',
            sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size));
      }
    } catch (_) {
      if (mounted)
        setState(
            () => error = 'Could not complete this action. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(8))),
              Expanded(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        const Text('Share content',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.search),
                                      hintText: 'Search',
                                      filled: true,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          borderSide: BorderSide.none)),
                                  onChanged: (v) =>
                                      setState(() => query = v.toLowerCase()))),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                              tooltip: 'Create a group',
                              onPressed: busy
                                  ? null
                                  : () => setState(() => mode = 'new_group'),
                              icon: const Icon(Icons.group_add_outlined))
                        ]),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, children: [
                          for (final item in [
                            ('dm', 'Messages'),
                            ('new_group', 'New group'),
                            ('group', 'Groups'),
                            ('room', 'Rooms')
                          ])
                            ChoiceChip(
                                label: Text(item.$2),
                                selected: mode == item.$1,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() => mode = item.$1))
                        ]),
                        if (mode == 'new_group')
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextField(
                                  controller: name,
                                  maxLength: 80,
                                  decoration: const InputDecoration(
                                      labelText: 'Group name'))),
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(error!,
                                  style: const TextStyle(
                                      color: Colors.redAccent))),
                        const SizedBox(height: 20),
                        FutureBuilder<Map>(
                            future: destinations,
                            builder: (context, snapshot) {
                              if (snapshot.hasError)
                                return TextButton(
                                    onPressed: () => setState(() =>
                                        destinations = getIt<ApiClient>()
                                            .dio
                                            .get('/sharing/destinations')
                                            .then((r) => r.data as Map)),
                                    child: const Text(
                                        'Could not load recipients. Retry'));
                              if (!snapshot.hasData)
                                return const Center(
                                    child: CircularProgressIndicator());
                              final items = (snapshot.data![mode == 'room'
                                      ? 'rooms'
                                      : mode == 'group'
                                          ? 'groups'
                                          : 'people'] as List)
                                  .where((p) => (p['display_name'] ??
                                          p['name'] ??
                                          p['username'])
                                      .toString()
                                      .toLowerCase()
                                      .contains(query))
                                  .toList();
                              if (items.isEmpty)
                                return Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(mode == 'room'
                                        ? 'Join a room to share content there.'
                                        : 'No matching recipients.'));
                              return LayoutBuilder(
                                  builder: (context, bounds) =>
                                      GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: items.length,
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount:
                                                      bounds.maxWidth < 250
                                                          ? 2
                                                          : 3,
                                                  crossAxisSpacing: 12,
                                                  mainAxisSpacing: 12,
                                                  mainAxisExtent: 80 +
                                                      MediaQuery.textScalerOf(
                                                              context)
                                                          .scale(36)),
                                          itemBuilder: (context, index) {
                                            final p = items[index];
                                            final id = p['id'] as String;
                                            final label = (p['display_name'] ??
                                                p['name']) as String;
                                            return InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                onTap: busy
                                                    ? null
                                                    : () {
                                                        if (mode ==
                                                            'new_group') {
                                                          setState(() {
                                                            if (!selected
                                                                    .remove(
                                                                        id) &&
                                                                selected.length <
                                                                    20)
                                                              selected.add(id);
                                                          });
                                                        } else {
                                                          send(mode, id);
                                                        }
                                                      },
                                                child: Column(children: [
                                                  SizedBox(
                                                      height: 68,
                                                      width: 76,
                                                      child: Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            if (mode == 'dm' ||
                                                                mode ==
                                                                    'new_group')
                                                              PhlioAvatar(
                                                                  name: label,
                                                                  imageUrl: p[
                                                                          'avatar_url']
                                                                      as String?,
                                                                  size: 64)
                                                            else
                                                              CircleAvatar(
                                                                  radius: 32,
                                                                  child: Icon(
                                                                      mode == 'room'
                                                                          ? Icons
                                                                              .tag
                                                                          : Icons
                                                                              .group_outlined,
                                                                      size:
                                                                          30)),
                                                            if (selected
                                                                    .contains(
                                                                        id) &&
                                                                mode ==
                                                                    'new_group')
                                                              const Positioned(
                                                                  right: 0,
                                                                  bottom: 0,
                                                                  child: CircleAvatar(
                                                                      radius:
                                                                          12,
                                                                      child: Icon(
                                                                          Icons
                                                                              .check,
                                                                          size:
                                                                              16))),
                                                          ])),
                                                  const SizedBox(height: 8),
                                                  Text(label,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontSize: 13)),
                                                ]));
                                          }));
                            }),
                        if (mode == 'new_group')
                          FilledButton(
                              onPressed: busy || selected.length < 2
                                  ? null
                                  : () => send('new_group', null),
                              child: Text(
                                  'Create group & share (${selected.length})')),
                      ]))),
              if (busy) const LinearProgressIndicator(),
              const Divider(height: 1),
              SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Row(children: [
                        for (final item in [
                          ('story', 'Add to story', Icons.add_circle_outline),
                          ('whatsapp', 'WhatsApp', Icons.chat_outlined),
                          ('copy', 'Copy link', Icons.link),
                          ('share', 'Share', Icons.ios_share),
                          ('rooms', 'Rooms', Icons.tag),
                          ('saved', 'Bookmarks', Icons.bookmark_border),
                          ('reposted', 'Reposts', Icons.repeat)
                        ])
                          SizedBox(
                              width: 90,
                              child: Column(children: [
                                IconButton.filledTonal(
                                    iconSize: 26,
                                    padding: const EdgeInsets.all(16),
                                    onPressed: busy
                                        ? null
                                        : () {
                                            if (item.$1 == 'saved' ||
                                                item.$1 == 'reposted') {
                                              Navigator.of(context).push(
                                                  MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          ContentLibraryScreen(
                                                              verb: item.$1)));
                                            } else if (item.$1 == 'rooms') {
                                              setState(() => mode = 'room');
                                            } else {
                                              external(item.$1);
                                            }
                                          },
                                    icon: Icon(item.$3)),
                                const SizedBox(height: 7),
                                Text(item.$2,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12))
                              ])),
                      ]))),
            ])),
      );
}

class ContentDetailScreen extends ConsumerWidget {
  const ContentDetailScreen({required this.path, super.key});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: const Text('Shared content')),
      body: ref.watch(contentProvider(path)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) =>
              const Center(child: Text('Content is no longer available.')),
          data: (item) =>
              ListView(padding: const EdgeInsets.all(16), children: [
                if (item['image_url'] != null)
                  ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                          AppConfig.mediaUrl(item['image_url'] as String),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox(height: 120))),
                const SizedBox(height: 16),
                Text(item['title'] as String,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (item['demo'] == true)
                  const Text('Demo content', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Text(item['description'] as String? ?? ''),
                if (item['source_url'] != null)
                  TextButton.icon(
                      onPressed: () => launchUrl(
                          Uri.parse(item['source_url'] as String),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new),
                      label: Text('Read at ${item['publisher']}')),
                if ((item['media_url'] as String?)?.isNotEmpty == true)
                  FilledButton.icon(
                      onPressed: () => ref.read(videoPlaybackProvider).open(
                          PlayableVideo(
                              id: item['ref'] as String,
                              platform: item['platform'] as String,
                              title: item['title'] as String,
                              creator: '',
                              url: item['media_url'] as String)),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play')),
                EngagementRow(path: path),
              ])));
}

class SharedContentText extends StatelessWidget {
  const SharedContentText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'phlio://(?:content/|app/shared/)([a-z]+)/([^\s]+)')
        .firstMatch(text);
    if (match == null) return Text(text, style: style);
    String decoded;
    try {
      decoded = Uri.decodeComponent(match[2]!);
    } on ArgumentError {
      return Text(text, style: style);
    }
    final path = '${match[1]}/$decoded';
    return OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ContentDetailScreen(path: path))),
        icon: const Icon(Icons.link),
        label: Text(text.split('\n').first,
            maxLines: 3, overflow: TextOverflow.ellipsis));
  }
}

class PlatformCatalogScreen extends ConsumerWidget {
  const PlatformCatalogScreen({required this.platform, super.key});
  final String platform;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(
          title: Text(
              'Phlio ${platform[0].toUpperCase()}${platform.substring(1)}')),
      body: ref.watch(catalogProvider(platform)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(catalogProvider(platform)),
                  child: const Text('Could not load content. Retry'))),
          data: (items) => ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final id = item['ref'] as String;
                return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ContentSurface(
                        platform: platform,
                        contentId: id,
                        child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                                onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => ContentDetailScreen(
                                            path: '$platform/$id'))),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (item['image_url'] != null)
                                        AspectRatio(
                                            aspectRatio: 16 / 9,
                                            child: Image.network(
                                                AppConfig.mediaUrl(
                                                    item['image_url']
                                                        as String),
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                        Icons.image_outlined))),
                                      Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(item['title'] as String,
                                                    style: const TextStyle(
                                                        fontSize: 19,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(height: 8),
                                                Text(
                                                    item['description']
                                                        as String,
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis)
                                              ])),
                                    ])))));
              })));
}

final groupMessagesProvider = FutureProvider.autoDispose.family<Map, String>(
    (ref, id) async =>
        (await getIt<ApiClient>().dio.get('/messaging/groups/$id/messages'))
            .data as Map);

class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({required this.groupId, super.key});
  final String groupId;
  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final text = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupMessagesProvider(widget.groupId));
    return Scaffold(
        appBar: AppBar(
            title:
                Text(state.valueOrNull?['name'] as String? ?? 'Group messages'),
            actions: [
              IconButton(
                  onPressed: () =>
                      ref.invalidate(groupMessagesProvider(widget.groupId)),
                  icon: const Icon(Icons.refresh))
            ]),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: state.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) =>
                      const Center(child: Text('Group unavailable.')),
                  data: (data) =>
                      ListView(padding: const EdgeInsets.all(16), children: [
                        for (final message in data['items'] as List)
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (message['author_profile'] != null)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Row(children: [
                                                PhlioAvatar(
                                                    name:
                                                        message['author_profile']
                                                                ['display_name']
                                                            as String,
                                                    imageUrl:
                                                        message['author_profile']
                                                                ['avatar_url']
                                                            as String?,
                                                    profileId: message['author']
                                                        as String,
                                                    size: 28),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                    child: Text(
                                                        message['author_profile']
                                                                ['display_name']
                                                            as String,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold))),
                                              ])),
                                        SharedContentText(
                                            message['text'] as String),
                                      ])))
                      ]))),
          Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        controller: text,
                        maxLines: null,
                        decoration:
                            const InputDecoration(hintText: 'Message group'))),
                IconButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (text.text.trim().isEmpty) return;
                            setState(() => busy = true);
                            try {
                              await getIt<ApiClient>().dio.post(
                                  '/messaging/groups/${widget.groupId}/messages',
                                  data: {'text': text.text.trim()});
                              text.clear();
                              ref.invalidate(
                                  groupMessagesProvider(widget.groupId));
                            } catch (_) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Message failed. Try again.')));
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.send))
              ]))
        ])));
  }
}

class GroupInboxScreen extends ConsumerWidget {
  const GroupInboxScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: const Text('Group messages')),
      body: ref.watch(groupsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(groupsProvider),
                  child: const Text('Retry'))),
          data: (groups) => groups.isEmpty
              ? const Center(
                  child: Text(
                      'Long-press content to create a group and share it.'))
              : ListView(children: [
                  for (final group in groups)
                    ListTile(
                        leading: const Icon(Icons.group),
                        title: Text(group['name'] as String),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => GroupChatScreen(
                                    groupId: group['id'] as String))))
                ])));
}

final sharedStoriesProvider = FutureProvider.autoDispose<List>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/social/shared-stories')).data
      as List;
});

class SharedStoriesScreen extends ConsumerWidget {
  const SharedStoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: const Text('Stories')),
      body: ref.watch(sharedStoriesProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(sharedStoriesProvider),
                  child: const Text('Retry stories'))),
          data: (items) => items.isEmpty
              ? const Center(
                  child: Text(
                      'Hold content and choose Add to story to share it for 24 hours.'))
              : ListView(children: [
                  for (final item in items)
                    ListTile(
                        leading: PhlioAvatar(
                            name: item['author']['display_name'] as String,
                            imageUrl: item['author']['avatar_url'] as String?,
                            size: 44),
                        title: Text(item['author']['display_name'] as String),
                        subtitle: Text(item['content']['title'] as String),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ContentDetailScreen(
                                path:
                                    "${item['content']['platform']}/${item['content']['ref']}"))))
                ])));
}

final mutualsProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, target) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/social/creators/$target/mutuals'))
      .data as Map;
});

class MutualAvatars extends ConsumerWidget {
  const MutualAvatars({required this.target, super.key});
  final String target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(mutualsProvider(target)).valueOrNull;
    final known = data?['followed_by'] as Map?;
    final hasKnown = (known?['count'] as int? ?? 0) > 0;
    final people =
        (hasKnown ? known!['avatars'] : data?['avatars']) as List? ?? [];
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          SizedBox(
              width: 28 + (people.length - 1) * 18,
              height: 30,
              child: Stack(children: [
                for (var i = 0; i < people.length; i++)
                  Positioned(
                      left: i * 18.0,
                      child: PhlioAvatar(
                          name: people[i]['display_name'] as String,
                          imageUrl: people[i]['avatar_url'] as String?,
                          profileId: people[i]['id'] as String,
                          size: 28))
              ])),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  hasKnown
                      ? 'Followed by ${people.first['display_name']}${(known!['count'] as int) > 1 ? ' and ${(known['count'] as int) - 1} others' : ''}'
                      : '${data!['count']} mutual friends',
                  style: const TextStyle(fontSize: 13))),
        ]));
  }
}

final contentLibraryProvider =
    FutureProvider.autoDispose.family<List, String>((ref, verb) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  return ((await getIt<ApiClient>().dio.get('/library/$verb')).data
      as Map)['items'] as List;
});

class ContentLibraryScreen extends ConsumerWidget {
  const ContentLibraryScreen({super.key, required this.verb});
  final String verb;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(verb == 'saved' ? 'Bookmarks' : 'Reposts')),
        body: ref.watch(contentLibraryProvider(verb)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () =>
                          ref.invalidate(contentLibraryProvider(verb)),
                      child: const Text('Try again'))),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('Nothing here yet.'))
                  : ListView(children: [
                      for (final item in items)
                        ListTile(
                            title: Text(item['title'] as String),
                            subtitle: Text(item['platform'] as String),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => ContentDetailScreen(
                                        path:
                                            '${item['platform']}/${item['ref']}')))),
                    ]),
            ),
      );
}
