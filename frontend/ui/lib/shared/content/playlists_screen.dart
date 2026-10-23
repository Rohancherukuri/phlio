import 'stream_screen.dart' show streamCategory;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import 'content_surface.dart';

final playlistsProvider =
    FutureProvider.autoDispose.family<List, String>((ref, platform) async {
  ref.watch(authControllerProvider.select((a) => a.valueOrNull?.id));
  return ((await getIt<ApiClient>()
          .dio
          .get('/playlists', queryParameters: {'platform': platform}))
      .data as Map)['items'] as List;
});
final playlistItemsProvider =
    FutureProvider.autoDispose.family<List, String>((ref, id) async {
  ref.watch(authControllerProvider.select((a) => a.valueOrNull?.id));
  return ((await getIt<ApiClient>().dio.get('/playlists/$id/items')).data
      as Map)['items'] as List;
});

Future<void> showPlaylists(BuildContext context, String platform,
        {String? mediaMode}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) =>
            PlaylistsScreen(platform: platform, mediaMode: mediaMode)));

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({required this.platform, this.mediaMode, super.key});
  final String platform;
  final String? mediaMode;
  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  final name = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (busy || name.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await getIt<ApiClient>().dio.post('/playlists', data: {
        'name': name.text.trim(),
        'platform': widget.platform,
        if (widget.mediaMode != null) 'media_mode': widget.mediaMode
      });
      if (!mounted) return;
      name.clear();
      ref.invalidate(playlistsProvider(widget.platform));
      if (mounted)
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PlaylistScreen(
                playlist: Map<String, dynamic>.from(response.data as Map))));
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not create playlist. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(
              '${widget.platform == 'news' ? 'News' : widget.mediaMode == 'audio' ? 'Audio' : widget.mediaMode == 'video' ? 'Movies & shows' : widget.platform} playlists')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Organize your bookmarks',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        TextField(
            controller: name,
            maxLength: 80,
            decoration: const InputDecoration(
                labelText: 'Playlist name',
                hintText: 'For example, Weekend reading'),
            onSubmitted: (_) => create()),
        FilledButton.icon(
            onPressed: busy ? null : create,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Create playlist')),
        if (error != null) Text(error!),
        const SizedBox(height: 24),
        ref.watch(playlistsProvider(widget.platform)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => TextButton(
                onPressed: () =>
                    ref.invalidate(playlistsProvider(widget.platform)),
                child: const Text('Could not load playlists. Retry')),
            data: (rows) => Column(children: [
                  if (rows.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Create your first playlist above.')),
                  for (final row in rows.where((row) =>
                      widget.mediaMode == null ||
                      row['media_mode'] == widget.mediaMode))
                    ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: Text(row['name'] as String),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => PlaylistScreen(
                                    playlist: Map<String, dynamic>.from(
                                        row as Map))))),
                ])),
      ]));
}

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({required this.playlist, super.key});
  final Map<String, dynamic> playlist;
  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  bool busy = false;
  String? error;
  late String title = widget.playlist['name'] as String;
  String get id => widget.playlist['id'] as String;
  String get platform => widget.playlist['platform'] as String;
  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) {
        ref.invalidate(playlistItemsProvider(id));
        ref.invalidate(playlistsProvider(platform));
      }
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not update playlist. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> rename() async {
    final controller = TextEditingController(text: title);
    final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Rename playlist'),
                content: TextField(controller: controller, maxLength: 80),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Save'))
                ]));
    // Dialog text fields dispose after their closing transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (result != null && result.isNotEmpty && mounted)
      await change(() async {
        await getIt<ApiClient>()
            .dio
            .patch('/playlists/$id', data: {'name': result});
        if (mounted) setState(() => title = result);
      });
  }

  Future<void> removePlaylist() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete playlist?'),
                content: const Text('Your bookmarks will remain saved.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ]));
    if (confirmed == true && mounted)
      await change(() async {
        await getIt<ApiClient>().dio.delete('/playlists/$id');
        if (mounted) {
          ref.invalidate(playlistsProvider(platform));
          Navigator.pop(context);
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(playlistItemsProvider(id));
    final saved = ref.watch(contentLibraryProvider('saved'));
    return Scaffold(
        appBar: AppBar(title: Text(title), actions: [
          IconButton(
              tooltip: 'Rename playlist',
              onPressed: busy ? null : rename,
              icon: const Icon(Icons.edit_outlined)),
          IconButton(
              tooltip: 'Delete playlist',
              onPressed: busy ? null : removePlaylist,
              icon: const Icon(Icons.delete_outline))
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (error != null) Text(error!),
          if (busy) const LinearProgressIndicator(),
          const Text('In this playlist',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => TextButton(
                  onPressed: () => ref.invalidate(playlistItemsProvider(id)),
                  child: const Text('Could not load items. Retry')),
              data: (rows) => Column(children: [
                    if (rows.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Add saved items from the list below.')),
                    for (final row in rows) tile(row as Map, false)
                  ])),
          const Divider(),
          const Text('Add from bookmarks',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          saved.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => TextButton(
                  onPressed: () =>
                      ref.invalidate(contentLibraryProvider('saved')),
                  child: const Text('Could not load bookmarks. Retry')),
              data: (rows) {
                final available = rows
                    .where((row) =>
                        row['platform'] == platform &&
                        (widget.playlist['media_mode'] == null ||
                            (['Music', 'Podcasts']
                                        .contains(streamCategory(row as Map))
                                    ? 'audio'
                                    : 'video') ==
                                widget.playlist['media_mode']) &&
                        !(items.valueOrNull ?? []).any(
                            (item) => item['object_id'] == row['object_id']))
                    .toList();
                return Column(children: [
                  if (available.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            'Bookmark content in this platform to add it here.')),
                  for (final row in available) tile(row as Map, true)
                ]);
              }),
        ]));
  }

  Widget tile(Map row, bool add) => ListTile(
      onLongPress: () => saveContentToPlaylist(
          context, ref, '${row['platform']}/${row['ref']}'),
      leading: row['image_url'] == null
          ? const Icon(Icons.bookmark_outline)
          : SizedBox(
              width: 48,
              height: 48,
              child: Image.network(
                  AppConfig.mediaUrl(row['image_url'] as String),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image_not_supported_outlined))),
      title: Text(row['title'] as String,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              ContentDetailScreen(path: '${row['platform']}/${row['ref']}'))),
      trailing: IconButton(
          tooltip: add ? 'Add to playlist' : 'Remove from playlist',
          onPressed: busy
              ? null
              : () => change(() async {
                    if (add)
                      await getIt<ApiClient>().dio.put('/playlists/$id/items',
                          data: {'object_id': row['object_id']});
                    else
                      await getIt<ApiClient>().dio.delete(
                          '/playlists/$id/items/${Uri.encodeComponent(row['object_id'] as String)}');
                  }),
          icon: Icon(
              add ? Icons.add_circle_outline : Icons.remove_circle_outline)));
}
