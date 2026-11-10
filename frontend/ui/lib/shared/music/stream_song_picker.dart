// Pick a song from the Phlio Stream catalog (for the profile song):
// search, artwork, a tap-to-preview play button, and select.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../content/content_surface.dart' show catalogProvider;
import '../content/stream_screen.dart' show streamCategory;

/// Returns `{title, artist, url, image_url, ref}` or null.
Future<Map<String, dynamic>?> showStreamSongPicker(BuildContext context) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _StreamSongPicker(),
    );

class _StreamSongPicker extends ConsumerStatefulWidget {
  const _StreamSongPicker();

  @override
  ConsumerState<_StreamSongPicker> createState() => _StreamSongPickerState();
}

class _StreamSongPickerState extends ConsumerState<_StreamSongPicker> {
  final _player = AudioPlayer();
  String _query = '';
  String? _playing;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _preview(Map item) async {
    final ref = '${item['ref']}';
    if (_playing == ref) {
      await _player.stop();
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = ref);
    try {
      await _player.play(UrlSource(AppConfig.mediaUrl('${item['media_url']}')));
    } catch (_) {
      if (mounted) setState(() => _playing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider('stream'));
    final songs = [
      for (final item in (catalog.valueOrNull ?? const []).cast<Map>())
        if (streamCategory(item) == 'Music' &&
            (item['media_url'] as String?)?.isNotEmpty == true &&
            (_query.isEmpty ||
                '${item['title']} ${item['publisher'] ?? item['artist'] ?? ''}'
                    .toLowerCase()
                    .contains(_query)))
          item,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: PhlioColors.border, borderRadius: BorderRadius.circular(4)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(children: [
            const Icon(Icons.graphic_eq_rounded, color: PhlioColors.brandOrange),
            const SizedBox(width: 8),
            Text('Phlio Stream', style: PhlioTypography.title),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search songs and artists'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: catalog.isLoading && !catalog.hasValue
              ? const Center(child: CircularProgressIndicator())
              : catalog.hasError && !catalog.hasValue
                  ? Center(
                      child: TextButton(
                        onPressed: () =>
                            ref.invalidate(catalogProvider('stream')),
                        child: const Text('Could not load songs. Retry'),
                      ),
                    )
                  : songs.isEmpty
                      ? const Center(child: Text('No songs found'))
                      : ListView.builder(
                          itemCount: songs.length,
                          itemBuilder: (context, i) {
                            final item = songs[i];
                            final art = item['image_url'] as String?;
                            final playing = _playing == '${item['ref']}';
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox.square(
                                  dimension: 48,
                                  child: art == null
                                      ? const ColoredBox(
                                          color: PhlioColors.surfaceElevated,
                                          child: Icon(Icons.music_note_rounded))
                                      : Image.network(AppConfig.mediaUrl(art),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                  Icons.music_note_rounded)),
                                ),
                              ),
                              title: Text('${item['title'] ?? 'Untitled'}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${item['publisher'] ?? item['artist'] ?? 'Phlio Stream'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                tooltip: playing ? 'Stop preview' : 'Preview',
                                icon: Icon(playing
                                    ? Icons.stop_circle_rounded
                                    : Icons.play_circle_rounded),
                                color: PhlioColors.brandOrange,
                                onPressed: () => _preview(item),
                              ),
                              onTap: () => Navigator.pop(context, {
                                'title': '${item['title'] ?? 'Untitled'}',
                                'artist':
                                    '${item['publisher'] ?? item['artist'] ?? 'Phlio Stream'}',
                                'url': '${item['media_url']}',
                                'image_url': art,
                                'ref': '${item['ref']}',
                              }),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

/// Where the profile song comes from: 'device', 'stream', 'spotify' or
/// 'default'. A light sheet, so it opens instantly.
Future<String?> showSongSourceSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (id, icon, color, title, subtitle) in const [
            ('device', Icons.library_music_rounded, PhlioColors.brandOrange,
                'From your phone', 'Pick an audio file and choose a section'),
            ('stream', Icons.graphic_eq_rounded, PhlioColors.domainStream,
                'Phlio Stream', 'Pick a song from Phlio Stream'),
            ('spotify', Icons.album_rounded, PhlioColors.brandViolet,
                'Spotify', 'Connect your account'),
            ('default', Icons.restart_alt_rounded, PhlioColors.textSecondary,
                'Phlio default', 'Ambient Sketch — Phlio Original'),
          ])
            ListTile(
              leading: Icon(icon, color: color),
              title: Text(title),
              subtitle: Text(subtitle),
              onTap: () => Navigator.of(sheet).pop(id),
            ),
        ]),
      ),
    );
