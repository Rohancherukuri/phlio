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
import 'note_song_picker.dart';

const kSpotifyGreen = Color(0xFF1DB954);

/// Song formats the server accepts (backend AUDIO_TYPES).
const kSongExtensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'opus'];

/// Opens the Instagram-style picker (Phlio Stream, Spotify, your phone),
/// then the "New song" clip picker. Returns the song with clip_start and
/// clip_length, or null.
Future<Map<String, dynamic>?> pickNoteMusic(BuildContext context) => showNoteSongPicker(context);

/// Picks a song file. Nothing is uploaded yet: the note keeps the file
/// (`path` / `bytes`) and [uploadNoteSong] sends it when you tap Share, so
/// picking works even offline and you can change your mind for free.
Future<Map<String, dynamic>?> pickSongFile(BuildContext context) async {
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
    final keep = {...music}..removeWhere((k, _) => k == 'path' || k == 'bytes' || k == 'file_name');
    // Server url/source + what was chosen here (title, clip).
    return {...keep, ...Map<String, dynamic>.from(res.data as Map), 'title': music['title']};
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      throw 'Your Phlio server doesn\'t have Notes yet — deploy the latest backend, then share again.';
    }
    final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
    if (e.response == null) throw 'You seem to be offline. Try again.';
    throw detail is String ? detail : 'Could not upload this song. Try another file.';
  }
}
