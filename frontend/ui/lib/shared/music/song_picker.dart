import 'package:audioplayers/audioplayers.dart';
import '../../app/config/app_config.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';

final musicApiProvider = Provider<Dio>((ref) => getIt<ApiClient>().dio);
final selectedSongProvider =
    FutureProvider.autoDispose.family<Map?, String>((ref, context) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  return (await ref
          .watch(musicApiProvider)
          .get('/music/selection', queryParameters: {'context': context}))
      .data as Map?;
});

String musicError(Object e) {
  if (e is DioException && e.response?.data is Map) {
    final data = e.response!.data as Map;
    if (data['detail'] is String) return data['detail'] as String;
  }
  return 'Music could not be loaded. Please try again.';
}

Future<Map?> showSongPicker(BuildContext context) => showModalBottomSheet<Map>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const SongPicker(),
    );

class SongPicker extends ConsumerStatefulWidget {
  const SongPicker({super.key});
  @override
  ConsumerState<SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends ConsumerState<SongPicker>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  Timer? debounce;
  final items = <Map>[];
  String tab = 'for_you';
  String? error;
  bool reconnectRequired = false;
  bool loading = true, connecting = false, connected = false, more = false;
  int generation = 0;
  final saving = <String>{};
  Dio get api => ref.read(musicApiProvider);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load({bool next = false}) async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (!next) items.clear();
    });
    try {
      final status = (await api.get('/music/status')).data as Map;
      if (!mounted || request != generation) return;
      connected = status['connected'] == true;
      if (!connected && (search.text.isNotEmpty || tab == 'for_you')) {
        setState(() => loading = false);
        return;
      }
      final result = (await api.get('/music/tracks', queryParameters: {
        'q': search.text.trim(),
        'tab': tab,
        'offset': next ? items.length : 0
      }))
          .data as Map;
      if (!mounted || request != generation) return;
      setState(() {
        items.addAll((result['items'] as List).cast<Map>());
        more = result['has_more'] == true;
        loading = false;
      });
    } catch (e) {
      if (mounted && request == generation)
        setState(() {
          error = musicError(e);
          reconnectRequired =
              e is DioException && e.response?.statusCode == 409;
          loading = false;
        });
    }
  }

  Future<void> connect() async {
    setState(() => connecting = true);
    try {
      final result = (await api.post('/music/connect')).data as Map;
      if (!await launchUrl(Uri.parse(result['url'] as String),
          mode: LaunchMode.externalApplication))
        throw StateError('Browser unavailable');
    } catch (e) {
      if (mounted) setState(() => error = musicError(e));
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> save(Map song) async {
    final id = song['id'] as String;
    if (!saving.add(id)) return;
    setState(() {});
    try {
      if (song['saved'] == true) {
        await api.delete('/music/saved/$id');
      } else {
        await api.put('/music/saved', data: {'id': id});
      }
      if (mounted) setState(() => song['saved'] = song['saved'] != true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(musicError(e))));
    } finally {
      saving.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: SafeArea(
            top: false,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(8))),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                      controller: search,
                      onChanged: (_) {
                        debounce?.cancel();
                        debounce = Timer(
                            const Duration(milliseconds: 350), () => load());
                      },
                      decoration: InputDecoration(
                          hintText: 'Search songs or artists',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: PhlioColors.surfaceInput,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none)))),
              SizedBox(
                  height: 48,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final entry in const {
                          'for_you': 'For you',
                          'trending': 'Trending',
                          'saved': 'Saved',
                          'original': 'Original audio'
                        }.entries)
                          Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: ChoiceChip(
                                  label: Text(entry.value),
                                  selected: tab == entry.key,
                                  onSelected: (_) {
                                    tab = entry.key;
                                    search.clear();
                                    load();
                                  },
                                  showCheckmark: false,
                                  selectedColor: Colors.white,
                                  labelStyle: TextStyle(
                                      color: tab == entry.key
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.w700))),
                      ])),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            tab == 'trending'
                                ? 'Most saved on Phlio'
                                : tab == 'saved'
                                    ? 'Your saved songs on Phlio'
                                    : 'Music from Spotify',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12))),
                    if (connected)
                      TextButton(
                          onPressed: () async {
                            await api.delete('/music/connection');
                            if (mounted) load();
                          },
                          child: const Text('Disconnect'))
                  ])),
              Expanded(
                  child: error != null
                      ? Center(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(error!, textAlign: TextAlign.center),
                                    TextButton(
                                        onPressed: () => load(),
                                        child: const Text('Try again')),
                                    if (reconnectRequired)
                                      TextButton(
                                          onPressed:
                                              connecting ? null : connect,
                                          child: const Text('Connect Spotify'))
                                  ])))
                      : tab == 'original'
                          ? const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                      'Original audio comes from your uploaded video or audio file. Spotify selections attach a song link.',
                                      textAlign: TextAlign.center)))
                          : !connected &&
                                  (tab == 'for_you' || search.text.isNotEmpty)
                              ? Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                      const Icon(Icons.library_music_outlined,
                                          size: 40),
                                      const SizedBox(height: 16),
                                      const Text('Find your music on Spotify'),
                                      const SizedBox(height: 12),
                                      FilledButton(
                                          onPressed:
                                              connecting ? null : connect,
                                          child: Text(connecting
                                              ? 'Opening Spotify…'
                                              : 'Connect Spotify')),
                                      TextButton(
                                          onPressed: () => load(),
                                          child: const Text(
                                              'I have connected — refresh'))
                                    ]))
                              : loading && items.isEmpty
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : items.isEmpty
                                      ? const Center(
                                          child: Text(
                                              'No songs here yet. Try searching for an artist.'))
                                      : ListView.builder(
                                          itemCount:
                                              items.length + (more ? 1 : 0),
                                          itemBuilder: (context, index) {
                                            if (index == items.length)
                                              return TextButton(
                                                  onPressed: loading
                                                      ? null
                                                      : () => load(next: true),
                                                  child: Text(loading
                                                      ? 'Loading…'
                                                      : 'Load more'));
                                            final song = items[index];
                                            final duration = Duration(
                                                milliseconds:
                                                    (song['duration_ms']
                                                                as num?)
                                                            ?.toInt() ??
                                                        0);
                                            return ListTile(
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 4),
                                                leading: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    child: SizedBox(
                                                        width: 52,
                                                        height: 52,
                                                        child: song['image_url'] == null
                                                            ? const Icon(Icons
                                                                .music_note)
                                                            : Image.network(
                                                                song['image_url']
                                                                    as String,
                                                                fit: BoxFit
                                                                    .cover,
                                                                errorBuilder: (_,
                                                                        __,
                                                                        ___) =>
                                                                    const Icon(Icons.music_note)))),
                                                title: Text('${song['title']}${song['explicit'] == true ? '  E' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                                subtitle: Text('${song['artist']} · ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                                onTap: () => Navigator.pop(context, song),
                                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  IconButton(
                                                      tooltip:
                                                          'Listen on Spotify',
                                                      onPressed: () => launchUrl(
                                                          Uri.parse(song['url']
                                                              as String),
                                                          mode: LaunchMode
                                                              .externalApplication),
                                                      icon: const Icon(
                                                          Icons.open_in_new,
                                                          size: 19)),
                                                  IconButton(
                                                      tooltip:
                                                          song['saved'] == true
                                                              ? 'Unsave song'
                                                              : 'Save song',
                                                      onPressed: saving
                                                              .contains(
                                                                  song['id'])
                                                          ? null
                                                          : () => save(song),
                                                      icon: Icon(song[
                                                                  'saved'] ==
                                                              true
                                                          ? Icons.bookmark
                                                          : Icons
                                                              .bookmark_border))
                                                ]));
                                          })),
            ])));
  }
}

class SongSelectionField extends ConsumerWidget {
  const SongSelectionField({super.key, required this.contextName});
  final String contextName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedSongProvider(contextName));
    final song = selected.valueOrNull;
    return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.music_note),
        title: Text(song?['title'] as String? ?? 'Add a song'),
        subtitle: Text(song?['artist'] as String? ?? 'Choose from Spotify'),
        trailing: song == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Remove song',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  try {
                    await ref.read(musicApiProvider).delete('/music/selection',
                        queryParameters: {'context': contextName});
                    ref.invalidate(selectedSongProvider(contextName));
                  } catch (e) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(musicError(e))));
                  }
                }),
        onTap: () async {
          final chosen = await showSongPicker(context);
          if (chosen == null || !context.mounted) return;
          try {
            await ref.read(musicApiProvider).put('/music/selection',
                data: {'id': chosen['id'], 'context': contextName});
            ref.invalidate(selectedSongProvider(contextName));
          } catch (e) {
            if (context.mounted)
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(musicError(e))));
          }
        });
  }
}

Future<void> showMusicDraft(BuildContext context, String kind) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${kind[0].toUpperCase()}${kind.substring(1)} music',
                      style: Theme.of(context).textTheme.headlineSmall),
                  SongSelectionField(contextName: kind),
                  const Text(
                      'Your song choice is saved as a draft. It is not published yet.'),
                  const SizedBox(height: 16)
                ])));

final contentSongProvider =
    FutureProvider.autoDispose.family<Map?, String>((ref, path) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  return (await ref.watch(musicApiProvider).get('/music/content/$path')).data
      as Map?;
});

class ContentSongBadge extends ConsumerWidget {
  const ContentSongBadge({super.key, required this.kind, required this.target});
  final String kind, target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(contentSongProvider('$kind/$target')).valueOrNull;
    if (song == null) return const SizedBox.shrink();
    if (song['source'] == 'local') return LocalPostSong(song: song);
    return InkWell(
        onTap: () => launchUrl(Uri.parse(song['url'] as String),
            mode: LaunchMode.externalApplication),
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const Icon(Icons.music_note, size: 16),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('${song['title']} · ${song['artist']} · Spotify',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12))),
              const Icon(Icons.open_in_new, size: 14)
            ])));
  }
}

class LocalPostSong extends StatefulWidget {
  const LocalPostSong({super.key, required this.song});
  final Map song;
  @override
  State<LocalPostSong> createState() => _LocalPostSongState();
}

class _LocalPostSongState extends State<LocalPostSong>
    with WidgetsBindingObserver {
  final player = AudioPlayer();
  bool playing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => playing = state == PlayerState.playing);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconButton(
          tooltip: playing ? 'Pause song' : 'Play song',
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: () async {
            try {
              if (playing) {
                await player.pause();
              } else {
                await player.play(UrlSource(
                    AppConfig.mediaUrl(widget.song['url'] as String)));
              }
            } catch (_) {
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Audio unavailable. Please try again.')));
            }
          }),
      title: Text('${widget.song['title']}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text('Original audio'));
}
