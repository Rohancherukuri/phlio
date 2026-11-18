// Where a note's song comes from: Phlio Stream, Spotify or a song file on
// the phone. Returns the `music` map the notes API takes:
// `{title, artist, url, image_url?, ref?, source}` with source
// `stream` | `spotify` | `local`.
//
// * Phlio Stream — the in-app catalogue; plays inside Phlio.
// * Spotify — search via the Spotify connection (shared/music/song_picker);
//   we keep only the track link and artwork, viewers open it in Spotify.
// * Your phone — an audio file uploaded to POST /social/notes/audio.

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../shared/music/song_picker.dart';
import '../../../../shared/music/stream_song_picker.dart';

const kSpotifyGreen = Color(0xFF1DB954);

Future<Map<String, dynamic>?> pickNoteMusic(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: PhlioColors.surface,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Add music', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _SourceTile(
          color: PhlioColors.brandPink,
          icon: Icons.graphic_eq_rounded,
          title: 'Phlio Stream',
          subtitle: 'Songs from the Phlio catalogue — play right in the app',
          onTap: () => Navigator.pop(sheet, 'stream'),
        ),
        _SourceTile(
          color: kSpotifyGreen,
          icon: Icons.album_rounded,
          title: 'Spotify',
          subtitle: 'Search Spotify — friends open the song in Spotify',
          onTap: () => Navigator.pop(sheet, 'spotify'),
        ),
        _SourceTile(
          color: const Color(0xFF4CC9F0),
          icon: Icons.phone_android_rounded,
          title: 'From your phone',
          subtitle: 'An MP3, M4A or other audio file (up to 15 MB)',
          onTap: () => Navigator.pop(sheet, 'local'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null || !context.mounted) return null;
  switch (source) {
    case 'stream':
      final song = await showStreamSongPicker(context);
      return song == null ? null : {...song, 'source': 'stream'};
    case 'spotify':
      final song = await showSongPicker(context);
      if (song == null) return null;
      final url = '${song['url'] ?? ''}';
      if (song['source'] != 'spotify' || !url.startsWith('https://open.spotify.com/track/')) {
        // The shared picker also offers original (uploaded) audio; for notes
        // we only accept Spotify tracks from this entry point.
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Pick a song from Spotify search.')));
        }
        return null;
      }
      return {
        'title': song['title'],
        'artist': song['artist'] ?? '',
        'url': url,
        if (song['image_url'] != null) 'image_url': song['image_url'],
        'ref': 'spotify:${song['id']}',
        'source': 'spotify',
      };
    default:
      return _uploadFromPhone(context);
  }
}

Future<Map<String, dynamic>?> _uploadFromPhone(BuildContext context) async {
  final picked = await FilePicker.pickFiles(type: FileType.audio, withData: false);
  final file = picked?.files.singleOrNull;
  if (file == null || !context.mounted) return null;
  if (file.size > 15 * 1024 * 1024) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a song under 15 MB.')));
    return null;
  }
  final progress = ValueNotifier<double>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  // Small blocking dialog while the file uploads.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => AlertDialog(
      backgroundColor: PhlioColors.surface,
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Uploading ${file.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          LinearProgressIndicator(value: value == 0 ? null : value),
        ]),
      ),
    ),
  );
  try {
    final multipart = file.path != null
        ? await MultipartFile.fromFile(file.path!, filename: file.name)
        : MultipartFile.fromBytes(file.bytes ?? const [], filename: file.name);
    final res = await getIt<ApiClient>().dio.post<dynamic>(
      '/social/notes/audio',
      data: FormData.fromMap({'file': multipart}),
      onSendProgress: (sent, total) => progress.value = total > 0 ? sent / total : 0,
    );
    navigator.pop();
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    navigator.pop();
    if (context.mounted) {
      final detail = e is DioException && e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(detail is String ? detail : 'Could not upload this song. Try another file.')));
    }
    return null;
  } finally {
    progress.dispose();
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.18), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: PhlioColors.textMuted, fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
