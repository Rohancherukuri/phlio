// Profile avatar state (Riverpod + a tiny persisted JSON file).
//
// Flow: pick from camera/gallery (image_picker) → crop to a circle-friendly
// 1:1 region (image_cropper, native UCrop) → choose a filter preset
// (ColorFiltered matrices, applied at display time so the original file
// stays intact) → save. The cropped file is copied into the app documents
// directory and its path (+ chosen filter) persisted to
// `profile_prefs.json`, so the avatar survives restarts and can be shown
// anywhere — including the bottom-nav Profile slot.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../design_system/widgets/phlio_card.dart';

/// Filter presets offered after cropping. Matrices are standard color
/// adjustments; index 0 = original.
@immutable
class AvatarFilter {
  const AvatarFilter(this.name, this.matrix);

  final String name;
  final ColorFilter matrix;
}

const List<AvatarFilter> kAvatarFilters = [
  AvatarFilter(
    'Original',
    ColorFilter.matrix(const [
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
  ),
  AvatarFilter(
    'Vivid',
    ColorFilter.matrix(const [
      1.2, 0, 0, 0, -0.03, //
      0, 1.15, 0, 0, -0.03, //
      0, 0, 1.1, 0, -0.03, //
      0, 0, 0, 1, 0,
    ]),
  ),
  AvatarFilter(
    'Warm',
    ColorFilter.matrix(const [
      1.1, 0.05, 0, 0, 0.02, //
      0.04, 1.02, 0, 0, 0.01, //
      0, 0, 0.9, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
  ),
  AvatarFilter(
    'Cool',
    ColorFilter.matrix(const [
      0.9, 0, 0.05, 0, 0, //
      0, 1.0, 0.04, 0, 0.01, //
      0.03, 0.05, 1.15, 0, 0.02, //
      0, 0, 0, 1, 0,
    ]),
  ),
  AvatarFilter(
    'Mono',
    ColorFilter.matrix(const [
      0.33, 0.59, 0.11, 0, 0, //
      0.33, 0.59, 0.11, 0, 0, //
      0.33, 0.59, 0.11, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
  ),
  AvatarFilter(
    'Noir',
    ColorFilter.matrix(const [
      0.45, 0.45, 0.1, 0, -0.12, //
      0.45, 0.45, 0.1, 0, -0.12, //
      0.45, 0.45, 0.1, 0, -0.12, //
      0, 0, 0, 1.1, 0,
    ]),
  ),
  AvatarFilter(
    'Dusk',
    ColorFilter.matrix(const [
      1.05, 0, 0.1, 0, 0.01, //
      0.05, 0.9, 0.12, 0, 0.01, //
      0.1, 0.15, 1.25, 0, 0.03, //
      0, 0, 0, 1, 0,
    ]),
  ),
];

@immutable
class AvatarState {
  const AvatarState({
    this.filePath,
    this.filterIndex = 0,
    this.songPath,
    this.songStart = 0,
    this.songEnd = 0,
  });

  final String? filePath;
  final int filterIndex;

  /// Custom profile song (local audio file copied into app storage) and the
  /// selected section of it — Instagram-style, up to 60 seconds.
  final String? songPath;
  final double songStart;
  final double songEnd;

  bool get hasAvatar => filePath != null;
  bool get hasSong => songPath != null;
  AvatarFilter get filter => kAvatarFilters[filterIndex.clamp(0, kAvatarFilters.length - 1)];

  AvatarState copyWith({
    String? filePath,
    int? filterIndex,
    bool clearFile = false,
    String? songPath,
    double? songStart,
    double? songEnd,
  }) =>
      AvatarState(
        filePath: clearFile ? null : (filePath ?? this.filePath),
        filterIndex: filterIndex ?? this.filterIndex,
        songPath: songPath ?? this.songPath,
        songStart: songStart ?? this.songStart,
        songEnd: songEnd ?? this.songEnd,
      );
}

class AvatarController extends Notifier<AvatarState> {
  File? _prefsFile;

  @override
  AvatarState build() {
    _load();
    return const AvatarState();
  }

  Future<File> _prefs() async {
    if (_prefsFile != null) return _prefsFile!;
    final dir = await getApplicationDocumentsDirectory();
    return _prefsFile = File('${dir.path}/profile_prefs.json');
  }

  Future<void> _load() async {
    try {
      final file = await _prefs();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final path = json['avatar_path'] as String?;
      final song = json['song_path'] as String?;
      state = AvatarState(
        filePath: (path != null && await File(path).exists()) ? path : null,
        filterIndex: (json['filter_index'] as int?) ?? 0,
        songPath: (song != null && await File(song).exists()) ? song : null,
        songStart: (json['song_start'] as num?)?.toDouble() ?? 0,
        songEnd: (json['song_end'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      // Corrupt/missing prefs: keep the empty avatar.
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _prefs();
      await file.writeAsString(jsonEncode({
        'avatar_path': state.filePath,
        'filter_index': state.filterIndex,
        'song_path': state.songPath,
        'song_start': state.songStart,
        'song_end': state.songEnd,
      }));
    } catch (_) {}
  }

  /// Picks from the camera (`camera: true`) or gallery, crops, and stages
  /// the result (the caller shows the filter picker, then [commit]s).
  ///
  /// Throws a friendly [Exception] when the picker plugin is unavailable —
  /// that always means the app needs one full restart after a new plugin
  /// was added (hot reload does not register native code).
  Future<File?> pickAndCrop({required bool camera}) async {
    late final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
      );
    } on PlatformException {
      throw Exception(
          'The photo picker needs one full app restart to install - stop and run again.');
    }
    if (picked == null) return null; // user cancelled

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop your photo',
          lockAspectRatio: true,
          activeControlsWidgetColor: const Color(0xFFFF8A4C),
        ),
      ],
    );
    if (cropped == null) return null;

    // Copy out of the cache dir so the file outlives the picker's temp
    // storage.
    final dir = await getApplicationDocumentsDirectory();
    final saved = File(
        '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(cropped.path).copy(saved.path);
    return saved;
  }

  /// Stages a cropped file (before the filter choice).
  void stage(File file) {
    state = AvatarState(filePath: file.path, filterIndex: state.filterIndex);
  }

  void setFilter(int index) {
    state = state.copyWith(filterIndex: index);
    _persist();
  }

  /// Chooses a profile song from local audio files (copied into app
  /// storage so it survives). Returns the new path, or null on cancel.
  Future<String?> pickSong() async {
    late final FilePickerResult? result;
    try {
      // FileType.custom over every audio extension: the system browser
      // then shows *all* matching files on the device instead of scoping
      // to one media folder.
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac', 'opus', 'wma', 'aiff',
        ],
        withData: false,
      );
    } on MissingPluginException {
      throw Exception(
          'The audio picker needs one full app restart to install - stop and run again.');
    }
    final file = result?.files.single;
    if (file == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final saved =
        File('${dir.path}/song_${DateTime.now().millisecondsSinceEpoch}_${file.name}');
    await File(file.path!).copy(saved.path);
    state = state.copyWith(songPath: saved.path);
    await _persist();
    // Swap any old song file out (best effort).
    return saved.path;
  }

  /// Saves the selected 60-second (or shorter) section of the profile song.
  Future<void> setSongSection(double start, double end) async {
    state = state.copyWith(songStart: start, songEnd: end);
    await _persist();
  }

  Future<void> clear() async {
    final old = state.filePath;
    state = const AvatarState();
    _persist();
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }
}

final avatarProvider = NotifierProvider<AvatarController, AvatarState>(
  AvatarController.new,
);

/// Renders the user's avatar: their photo with the chosen filter when set,
/// else the initials fallback.
class MeAvatar extends ConsumerWidget {
  const MeAvatar({required this.name, required this.size, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = ref.watch(avatarProvider);
    if (avatar.hasAvatar) {
      return ClipOval(
        child: ColorFiltered(
          colorFilter: avatar.filter.matrix,
          child: Image.file(
            File(avatar.filePath!),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => PhlioAvatar(name: name, size: size),
          ),
        ),
      );
    }
    return PhlioAvatar(name: name, size: size);
  }
}
