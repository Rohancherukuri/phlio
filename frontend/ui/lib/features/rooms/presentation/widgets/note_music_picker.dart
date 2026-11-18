// Where a note's song comes from: Phlio Stream, Spotify or a song file on
// the phone. Returns the `music` map the notes API takes:
// `{title, artist, url, image_url?, ref?, source}` with source
// `stream` | `spotify` | `local`.
//
// * Phlio Stream — the in-app catalogue; plays inside Phlio.
// * Spotify — search via the Spotify connection (shared/music/song_picker);
//   we keep only the track link and artwork, viewers open it in Spotify.
// * Your phone — a song file; uploaded to POST /social/notes/audio when the
//   note is shared (see uploadNoteSong).

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../shared/music/song_picker.dart';
import '../../../../shared/music/stream_song_picker.dart';

const kSpotifyGreen = Color(0xFF1DB954);

/// Song formats the server accepts (backend AUDIO_TYPES).
const kSongExtensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'opus'];

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
          subtitle: 'MP3, M4A, AAC, WAV, OGG, FLAC or OPUS (up to 15 MB)',
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

/// Picks a song file. Nothing is uploaded yet: the note keeps the file
/// (`path` / `bytes`) and [uploadNoteSong] sends it when you tap Share, so
/// picking works even offline and you can change your mind for free.
Future<Map<String, dynamic>?> _uploadFromPhone(BuildContext context) async {
  // Only song files show up in the picker.
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: kSongExtensions,
    withData: kIsWeb,
  );
  final file = picked?.files.singleOrNull;
  if (file == null || !context.mounted) return null;
  final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
  if (!kSongExtensions.contains(ext)) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Choose a song file: MP3, M4A, AAC, WAV, OGG, FLAC or OPUS.')));
    return null;
  }
  if (file.size > 15 * 1024 * 1024) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a song under 15 MB.')));
    return null;
  }
  final stem = file.name.substring(0, file.name.length - ext.length - 1).replaceAll('_', ' ').trim();
  return {
    'title': stem.isEmpty ? 'Original audio' : (stem.length > 120 ? stem.substring(0, 120) : stem),
    'artist': 'From your phone',
    'url': '',
    'source': 'local',
    'file_name': file.name,
    if (file.path != null) 'path': file.path,
    if (file.bytes != null) 'bytes': file.bytes,
  };
}

/// True when [music] is a phone song that hasn't been uploaded yet.
bool needsUpload(Map? music) => music != null && music['source'] == 'local' && '${music['url'] ?? ''}'.isEmpty;

/// Uploads a phone song picked with [pickNoteMusic]; returns the server's
/// music object, or throws a message to show.
Future<Map<String, dynamic>> uploadNoteSong(Map music, {void Function(double)? onProgress}) async {
  final name = '${music['file_name'] ?? 'song.mp3'}';
  final multipart = music['path'] != null
      ? await MultipartFile.fromFile('${music['path']}', filename: name)
      : MultipartFile.fromBytes((music['bytes'] as List<int>?) ?? const [], filename: name);
  try {
    final res = await getIt<ApiClient>().dio.post<dynamic>(
      '/social/notes/audio',
      data: FormData.fromMap({'file': multipart}),
      onSendProgress: (sent, total) => onProgress?.call(total > 0 ? sent / total : 0),
    );
    return {...Map<String, dynamic>.from(res.data as Map), 'title': music['title']};
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      throw 'Your Phlio server doesn\'t have Notes yet — deploy the latest backend, then share again.';
    }
    final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
    if (e.response == null) throw 'You seem to be offline. Try again.';
    throw detail is String ? detail : 'Could not upload this song. Try another file.';
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
