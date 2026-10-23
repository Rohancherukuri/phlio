// Social Explore → Clips: a 3-column thumbnail grid with view counts, a
// full-screen player that starts on the tapped clip, and the "Saved" screen
// (collections on top — saved audio plus the user's Social playlists — and
// a grid of saved clips and posts below).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../../shared/content/playlists_screen.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../controllers/video_library.dart';
import 'social_clips_view.dart';
import 'video_thumbnail.dart';

// -- Data ---------------------------------------------------------------------

/// Saved Social items (clips, videos and posts), newest first.
final savedSocialProvider = FutureProvider.autoDispose<List<Map>>((ref) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final items = ((await getIt<ApiClient>().dio.get('/library/saved')).data
          as Map)['items'] as List;
  return items
      .whereType<Map>()
      .where((item) => item['platform'] == 'social')
      .toList();
});

/// Songs the viewer saved from the music picker.
final savedAudioProvider = FutureProvider.autoDispose<List<Map>>((ref) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  try {
    final data = (await getIt<ApiClient>()
            .dio
            .get('/music/tracks', queryParameters: {'tab': 'saved'}))
        .data as Map;
    return (data['items'] as List).whereType<Map>().toList();
  } catch (_) {
    return const []; // Music not connected: the Audio collection stays empty.
  }
});

bool _isClip(Map item) => item['kind'] == 'clip' || item['kind'] == 'video';

// -- Explore grid --------------------------------------------------------------

class SocialClipsGrid extends ConsumerWidget {
  const SocialClipsGrid({this.query = '', super.key});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(socialVideoCatalogProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
                child: TextButton(
                    onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                    child: const Text('Could not load clips. Retry'))),
            data: (videos) {
              final clips = videos
                  .where((v) =>
                      v.kind == 'clip' &&
                      v.title.toLowerCase().contains(query.trim().toLowerCase()))
                  .toList();
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(socialVideoCatalogProvider);
                  await ref.read(socialVideoCatalogProvider.future);
                },
                child: clips.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                            Padding(
                                padding: const EdgeInsets.all(PhlioSpacing.xxl),
                                child: Text(
                                    query.isEmpty
                                        ? 'No clips yet.'
                                        : 'No clips match your search.',
                                    textAlign: TextAlign.center,
                                    style: PhlioTypography.body))
                          ])
                    : GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate: _clipGrid,
                        itemCount: clips.length,
                        itemBuilder: (_, i) => ClipTile(
                          thumbnailUrl: clips[i].thumbnailUrl,
                          viewsPath: 'social/${clips[i].id}',
                          onTap: () => openClipsPlayer(context,
                              initialClipId: clips[i].id, query: query),
                        ),
                      ),
              );
            },
          );
}

const _clipGrid = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  mainAxisSpacing: 2,
  crossAxisSpacing: 2,
  childAspectRatio: 0.66, // portrait, close to a 9:16 clip once cropped
);

/// One grid cell: cover-cropped thumbnail, a soft bottom scrim and the view
/// count (eye + number) pinned bottom-left. [showPlayBadge] adds the
/// top-right play glyph used on the Saved grid.
class ClipTile extends ConsumerWidget {
  const ClipTile(
      {required this.thumbnailUrl,
      required this.onTap,
      this.viewsPath,
      this.showPlayBadge = false,
      this.caption,
      super.key});
  final String? thumbnailUrl;
  final String? viewsPath;
  final VoidCallback onTap;
  final bool showPlayBadge;
  final String? caption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = viewsPath == null
        ? null
        : ref.watch(engagementProvider(viewsPath!)).valueOrNull?['views_count']
            as num?;
    return InkWell(
      onTap: onTap,
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(
          color: PhlioColors.surfaceElevated,
          child: thumbnailUrl == null || thumbnailUrl!.isEmpty
              ? Center(
                  child: caption == null
                      ? const Icon(Icons.movie_outlined,
                          color: PhlioColors.textMuted)
                      : Padding(
                          padding: const EdgeInsets.all(PhlioSpacing.sm),
                          child: Text(caption!,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: PhlioTypography.caption)))
              : VideoThumbnail(url: thumbnailUrl),
        ),
        if (views != null)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 56,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xAA000000)]),
                ),
              ),
            ),
          ),
        if (views != null)
          Positioned(
            left: 8,
            bottom: 7,
            child: Row(children: [
              const Icon(Icons.visibility_outlined,
                  size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(formatEngagementCount(views),
                  style: PhlioTypography.label.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 4)
                      ])),
            ]),
          ),
        if (showPlayBadge)
          const Positioned(
            top: 8,
            right: 8,
            child: Icon(Icons.smart_display_rounded,
                size: 20,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
          ),
      ]),
    );
  }
}

// -- Full-screen player --------------------------------------------------------

Future<void> openClipsPlayer(BuildContext context,
        {String? initialClipId, String query = '', List<String>? onlyIds}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Row(children: [
              const BackButton(color: Colors.white),
              Text('Clips',
                  style: PhlioTypography.title.copyWith(color: Colors.white)),
            ]),
            Expanded(
              child: SocialClipsView(
                  query: query,
                  initialClipId: initialClipId,
                  onlyIds: onlyIds),
            ),
          ]),
        ),
      ),
    ));

// -- Saved -------------------------------------------------------------------

void openSavedClips(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const SavedClipsScreen()));

enum _SavedFilter { all, collections, clips, posts }

class SavedClipsScreen extends ConsumerStatefulWidget {
  const SavedClipsScreen({super.key});
  @override
  ConsumerState<SavedClipsScreen> createState() => _SavedClipsScreenState();
}

class _SavedClipsScreenState extends ConsumerState<SavedClipsScreen> {
  _SavedFilter filter = _SavedFilter.all;

  Future<void> _newCollection() async {
    final name = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('New collection'),
                content: TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 80,
                    decoration:
                        const InputDecoration(hintText: 'Collection name')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (name.text.trim().isNotEmpty) {
                          Navigator.pop(c, name.text.trim());
                        }
                      },
                      child: const Text('Create')),
                ]));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    if (value == null) return;
    try {
      await getIt<ApiClient>()
          .dio
          .post('/playlists', data: {'platform': 'social', 'name': value});
      ref.invalidate(playlistsProvider('social'));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not create collection. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedSocialProvider);
    final playlists = ref.watch(playlistsProvider('social'));
    final audio = ref.watch(savedAudioProvider);

    final items = saved.valueOrNull ?? const <Map>[];
    final gridItems = switch (filter) {
      _SavedFilter.clips => items.where(_isClip).toList(),
      _SavedFilter.posts => items.where((i) => !_isClip(i)).toList(),
      _SavedFilter.collections => const <Map>[],
      _SavedFilter.all => items,
    };
    final clipIds = [
      for (final item in items.where(_isClip)) item['ref'].toString()
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Saved', style: PhlioTypography.headline),
        actions: [
          IconButton(
              tooltip: 'New collection',
              icon: const Icon(Icons.add_rounded),
              onPressed: _newCollection),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(savedSocialProvider);
          ref.invalidate(playlistsProvider('social'));
          ref.invalidate(savedAudioProvider);
          await ref.read(savedSocialProvider.future);
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                    PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.lg, 0),
                children: [
                  for (final (f, label) in const [
                    (_SavedFilter.all, 'All'),
                    (_SavedFilter.collections, 'Collections'),
                    (_SavedFilter.clips, 'Clips & videos'),
                    (_SavedFilter.posts, 'Posts'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: PhlioSpacing.sm),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: filter == f,
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        onSelected: (_) => setState(() => filter = f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (filter == _SavedFilter.all ||
              filter == _SavedFilter.collections) ...[
            _header('Collections'),
            SliverToBoxAdapter(
              child: _Collections(
                audio: audio.valueOrNull ?? const [],
                playlists:
                    (playlists.valueOrNull ?? const []).whereType<Map>().toList(),
                hasSaved: items.isNotEmpty,
                vertical: filter == _SavedFilter.collections,
              ),
            ),
          ],
          if (filter != _SavedFilter.collections) ...[
            _header(filter == _SavedFilter.posts
                ? 'Posts'
                : filter == _SavedFilter.clips
                    ? 'Clips & videos'
                    : 'Clips and posts'),
            if (saved.isLoading && items.isEmpty)
              const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.all(PhlioSpacing.xxl),
                      child: Center(child: CircularProgressIndicator())))
            else if (saved.hasError)
              SliverToBoxAdapter(
                  child: TextButton(
                      onPressed: () => ref.invalidate(savedSocialProvider),
                      child: const Text('Could not load saved items. Retry')))
            else if (gridItems.isEmpty)
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.all(PhlioSpacing.xxl),
                      child: Text(
                          'Tap the bookmark on any clip or post to save it here.',
                          textAlign: TextAlign.center,
                          style: PhlioTypography.body)))
            else
              _savedGrid(context, gridItems, clipIds),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: PhlioSpacing.xxxl)),
        ]),
      ),
    );
  }

  Widget _header(String title) => SliverToBoxAdapter(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg, PhlioSpacing.lg,
              PhlioSpacing.lg, PhlioSpacing.md),
          child: Text(title, style: PhlioTypography.title)));
}

Widget _savedGrid(BuildContext context, List<Map> items, List<String> clipIds) =>
    SliverGrid.builder(
      gridDelegate: _clipGrid,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final clip = _isClip(item);
        final contentRef = item['ref'].toString();
        return ClipTile(
          thumbnailUrl: item['image_url'] as String?,
          caption: (item['description'] as String?)?.isNotEmpty == true
              ? item['description'] as String
              : item['title'] as String?,
          showPlayBadge: clip,
          viewsPath: clip ? 'social/$contentRef' : null,
          onTap: () => clip
              ? openClipsPlayer(context,
                  initialClipId: contentRef, onlyIds: clipIds)
              : Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      ContentDetailScreen(path: 'social/$contentRef'))),
        );
      },
    );

/// Collection cards: saved Audio first, then the user's Social playlists.
/// When the user has no playlist yet, a default "All saved" collection is
/// shown so the row is never empty.
class _Collections extends StatelessWidget {
  const _Collections(
      {required this.audio,
      required this.playlists,
      required this.hasSaved,
      required this.vertical});
  final List<Map> audio;
  final List<Map> playlists;
  final bool hasSaved, vertical;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _CollectionCard(
        title: 'Audio',
        subtitle: audio.isEmpty
            ? 'Private'
            : '${audio.length} ${audio.length == 1 ? 'song' : 'songs'} · Private',
        imageUrl: audio.isEmpty ? null : audio.first['image_url'] as String?,
        icon: Icons.music_note_rounded,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _AudioCollectionScreen(songs: audio))),
      ),
      if (playlists.isEmpty)
        _CollectionCard(
          title: 'All saved',
          subtitle: 'Default · Private',
          icon: Icons.bookmark_rounded,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const _PlaylistCollectionScreen(
                  playlist: {'name': 'All saved'}))),
        ),
      for (final playlist in playlists)
        _PlaylistCard(playlist: Map<String, dynamic>.from(playlist)),
    ];
    if (vertical) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
        child: Column(children: [
          for (final card in cards)
            Padding(
                padding: const EdgeInsets.only(bottom: PhlioSpacing.md),
                child: card),
        ]),
      );
    }
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: PhlioSpacing.xl),
        itemBuilder: (_, i) => SizedBox(width: 168, child: cards[i]),
      ),
    );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist});
  final Map<String, dynamic> playlist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(playlistItemsProvider(playlist['id'] as String)).valueOrNull;
    final cover = items
        ?.whereType<Map>()
        .map((i) => i['image_url'] as String?)
        .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);
    final count = items?.length;
    return _CollectionCard(
      title: playlist['name'] as String? ?? 'Collection',
      subtitle: count == null
          ? 'Private'
          : '$count ${count == 1 ? 'item' : 'items'} · Private',
      imageUrl: cover,
      icon: Icons.video_library_rounded,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _PlaylistCollectionScreen(playlist: playlist))),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.onTap,
      this.imageUrl});
  final String title, subtitle;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: PhlioRadii.mdRadius,
        child: Row(children: [
          ClipRRect(
            borderRadius: PhlioRadii.mdRadius,
            child: Container(
              width: 60,
              height: 60,
              color: PhlioColors.surfaceElevated,
              child: imageUrl == null
                  ? Icon(icon, color: PhlioColors.brandOrange, size: 26)
                  : Image.network(
                      imageUrl!.startsWith('http')
                          ? imageUrl!
                          : AppConfig.mediaUrl(imageUrl!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon, color: PhlioColors.brandOrange)),
            ),
          ),
          const SizedBox(width: PhlioSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.bodyStrong.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.lock_rounded,
                      size: 13, color: PhlioColors.textMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.caption
                            .copyWith(color: PhlioColors.textMuted)),
                  ),
                ]),
              ],
            ),
          ),
        ]),
      );
}

class _AudioCollectionScreen extends StatelessWidget {
  const _AudioCollectionScreen({required this.songs});
  final List<Map> songs;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Audio')),
        body: songs.isEmpty
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(PhlioSpacing.xxl),
                    child: Text(
                        'Save songs from the music picker when you create a post or clip.',
                        textAlign: TextAlign.center,
                        style: PhlioTypography.body)))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: PhlioSpacing.sm),
                itemCount: songs.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 84,
                    color: PhlioColors.borderSubtle),
                itemBuilder: (_, i) {
                  final song = songs[i];
                  final image = song['image_url'] as String?;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: PhlioSpacing.lg, vertical: 4),
                    leading: ClipRRect(
                      borderRadius: PhlioRadii.smRadius,
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: image == null
                            ? const ColoredBox(
                                color: PhlioColors.surfaceElevated,
                                child: Icon(Icons.music_note_rounded))
                            : Image.network(image, fit: BoxFit.cover),
                      ),
                    ),
                    title: Text(song['title'] as String? ?? 'Untitled',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(song['artist'] as String? ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.open_in_new_rounded,
                        size: 18, color: PhlioColors.textMuted),
                    onTap: song['url'] == null
                        ? null
                        : () => launchUrl(Uri.parse(song['url'] as String),
                            mode: LaunchMode.externalApplication),
                  );
                },
              ),
      );
}

/// A playlist's items in the same 3-column grid. With no `id`, shows every
/// saved Social item (the default collection).
class _PlaylistCollectionScreen extends ConsumerWidget {
  const _PlaylistCollectionScreen({required this.playlist});
  final Map playlist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = playlist['id'] as String?;
    final state = id == null
        ? ref.watch(savedSocialProvider)
        : ref
            .watch(playlistItemsProvider(id))
            .whenData((rows) => rows.whereType<Map>().toList());
    return Scaffold(
      appBar: AppBar(title: Text(playlist['name'] as String? ?? 'Collection')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: TextButton(
                onPressed: () => id == null
                    ? ref.invalidate(savedSocialProvider)
                    : ref.invalidate(playlistItemsProvider(id)),
                child: const Text('Could not load. Retry'))),
        data: (items) {
          if (items.isEmpty) {
            return Center(
                child: Text('Nothing in this collection yet.',
                    style: PhlioTypography.body));
          }
          final clipIds = [
            for (final item in items.where(_isClip)) item['ref'].toString()
          ];
          return CustomScrollView(
              slivers: [_savedGrid(context, items, clipIds)]);
        },
      ),
    );
  }
}
