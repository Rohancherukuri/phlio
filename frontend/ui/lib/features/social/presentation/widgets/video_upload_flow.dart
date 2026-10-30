// Social video upload, three steps:
//
//   1. Upload from gallery — 3-column grid of on-device videos with
//      durations and an album switcher ("Videos ⌄"). Videos only — long-form
//      uploads. Hold a tile to preview it playing; tap to choose.
//   2. Preview — the video over a blurred backdrop with Add sound, mute,
//      a right-side tool rail (Aa · effects · filters · stickers · captions)
//      and Edit / Next.
//   3. Add details — caption, visibility, audience, description, location,
//      related video, playlists and paid promotion, then Upload.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/content/playlists_screen.dart';
import '../../../../shared/music/song_picker.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../controllers/video_library.dart';

/// Entry point used by the Create sheet ("New video" / "New clip").
Future<void> openVideoUpload(BuildContext context, {String kind = 'video'}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => GalleryVideoPicker(initialKind: kind)));

enum UploadMode { video, short }

extension on UploadMode {
  String get label => switch (this) {
        UploadMode.video => 'Video',
        UploadMode.short => 'Short',
      };

  /// Backend `kind` for uploads.
  String get kind => this == UploadMode.short ? 'clip' : 'video';

  (int, int) get limits => this == UploadMode.short ? (15, 120) : (60, 300);
}

String _clock(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${(m % 60).toString().padLeft(2, '0')}:$s'
      : '$m:$s';
}

bool get _galleryAvailable =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

const _sheetColor = Color(0xFF1C1F24);

// =============================================================================
// 1. Upload from gallery
// =============================================================================

class GalleryVideoPicker extends ConsumerStatefulWidget {
  const GalleryVideoPicker({this.initialKind = 'video', super.key});
  final String initialKind;
  @override
  ConsumerState<GalleryVideoPicker> createState() => _GalleryVideoPickerState();
}

class _GalleryVideoPickerState extends ConsumerState<GalleryVideoPicker> {
  // Long-form videos only; clips keep their own entry point.
  late final UploadMode mode =
      widget.initialKind == 'clip' ? UploadMode.short : UploadMode.video;
  List<AssetPathEntity> albums = [];
  AssetPathEntity? album;
  final assets = <AssetEntity>[];
  final _thumbs = <String, Future<Uint8List?>>{};
  bool loading = true, denied = false, hasMore = true, loadingMore = false;
  int page = 0;
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.pixels > scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    if (_galleryAvailable) {
      _init();
    } else {
      loading = false;
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// Set when the gallery plugin can't be used (e.g. it was just added and
  /// the app was only hot-restarted, so the native side isn't registered).
  String? galleryError;

  Future<void> _init() async {
    try {
      await _openGallery();
    } on MissingPluginException {
      _galleryFailed('The gallery needs a full app restart to finish '
          'installing. Stop the app and run it again — or browse your files '
          'for now.');
    } catch (_) {
      _galleryFailed('Could not open your gallery. You can browse your files '
          'instead.');
    }
  }

  void _galleryFailed(String message) {
    if (!mounted) return;
    setState(() {
      loading = false;
      galleryError = message;
    });
  }

  Future<void> _openGallery() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (!permission.hasAccess) {
      setState(() {
        loading = false;
        denied = true;
      });
      return;
    }
    final paths = await PhotoManager.getAssetPathList(type: RequestType.video);
    if (!mounted) return;
    setState(() {
      albums = paths;
      album = paths.isEmpty
          ? null
          : paths.firstWhere((p) => p.isAll, orElse: () => paths.first);
      denied = false;
    });
    await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      assets.clear();
      page = 0;
      hasMore = true;
      loading = true;
    });
    try {
      await _loadMore();
    } catch (_) {
      _galleryFailed('Could not load your videos. You can browse your files '
          'instead.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadMore() async {
    final current = album;
    if (current == null || !hasMore || loadingMore) return;
    loadingMore = true;
    try {
      final next = await current.getAssetListPaged(page: page, size: 60);
      if (!mounted || current != album) return;
      setState(() {
        assets.addAll(next);
        page++;
        hasMore = next.length == 60;
      });
    } finally {
      loadingMore = false;
    }
  }

  Future<Uint8List?> _thumb(AssetEntity asset) => _thumbs.putIfAbsent(
      asset.id,
      () => asset.thumbnailDataWithSize(const ThumbnailSize.square(320),
          quality: 85));

  Future<void> _chooseAlbum() async {
    if (albums.isEmpty) return;
    final counts = await Future.wait(albums.map((a) => a.assetCountAsync));
    if (!mounted) return;
    final chosen = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      showDragHandle: true,
      backgroundColor: _sheetColor,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (var i = 0; i < albums.length; i++)
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(albums[i].isAll ? 'Videos' : albums[i].name),
              trailing: Text('${counts[i]}',
                  style: const TextStyle(color: PhlioColors.textMuted)),
              selected: albums[i] == album,
              onTap: () => Navigator.pop(sheet, albums[i]),
            ),
        ]),
      ),
    );
    if (chosen != null && chosen != album) {
      setState(() => album = chosen);
      await _reload();
    }
  }

  Future<void> _preview(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null || !mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close preview',
      barrierColor: Colors.black.withValues(alpha: .6),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => _HoldPreview(file: file),
      transitionBuilder: (_, a, __, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: .94, end: 1.0)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
              child: child)),
    );
  }

  Future<void> _choose(File file) async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => VideoPreviewEditor(file: file, mode: mode)));
  }

  Future<void> _browseFiles() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) await _choose(File(path));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        size: 30, color: Colors.white)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              child: Row(children: [
                const Expanded(
                  child: Text('Upload from gallery',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: albums.length > 1 ? _chooseAlbum : null,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        album == null || album!.isAll
                            ? 'Videos'
                            : album!.name,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white, size: 26),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
                child: _grid(),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      );

  Widget _grid() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (!_galleryAvailable || galleryError != null || denied || album == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.video_library_outlined,
                size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
                galleryError ??
                    (denied
                        ? 'Allow Phlio to access your videos to upload from your gallery.'
                        : !_galleryAvailable
                            ? 'Choose a video from your files.'
                            : 'No videos found on this device.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 20),
            if (denied)
              FilledButton(
                  onPressed: () async {
                    await PhotoManager.openSetting();
                  },
                  child: const Text('Allow access')),
            TextButton(
                onPressed: _browseFiles, child: const Text('Browse files')),
          ]),
        ),
      );
    }
    if (assets.isEmpty) {
      return const Center(
          child: Text('No videos in this album.',
              style: TextStyle(color: Colors.white70)));
    }
    return GridView.builder(
      controller: scroll,
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
      itemCount: assets.length,
      itemBuilder: (_, i) {
        final asset = assets[i];
        return GestureDetector(
          onTap: () async {
            final file = await asset.file;
            if (file != null) await _choose(file);
          },
          onLongPress: () => _preview(asset),
          child: Stack(fit: StackFit.expand, children: [
            FutureBuilder<Uint8List?>(
              future: _thumb(asset),
              builder: (_, snap) => snap.data == null
                  ? const ColoredBox(color: Color(0xFF1A1A1A))
                  : Image.memory(snap.data!,
                      fit: BoxFit.cover, gaplessPlayback: true),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(_clock(Duration(seconds: asset.duration)),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Hold-to-preview: the clip plays in a rounded card with a close button.
class _HoldPreview extends StatefulWidget {
  const _HoldPreview({required this.file});
  final File file;
  @override
  State<_HoldPreview> createState() => _HoldPreviewState();
}

class _HoldPreviewState extends State<_HoldPreview> {
  late final VideoPlayerController controller =
      VideoPlayerController.file(widget.file);
  @override
  void initState() {
    super.initState();
    controller.initialize().then((_) {
      if (!mounted) return;
      controller
        ..setLooping(true)
        ..play();
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: size.width * .8, maxHeight: size.height * .66),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: Colors.black,
            child: Stack(children: [
              controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller))
                  : const SizedBox(
                      width: 240,
                      height: 400,
                      child: Center(child: CircularProgressIndicator())),
              Positioned(
                top: 12,
                left: 12,
                child: IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white,
                        size: 30,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 2. Preview + tools
// =============================================================================

class VideoPreviewEditor extends ConsumerStatefulWidget {
  const VideoPreviewEditor({required this.file, required this.mode, super.key});
  final File file;
  final UploadMode mode;
  @override
  ConsumerState<VideoPreviewEditor> createState() =>
      _VideoPreviewEditorState();
}

class _VideoPreviewEditorState extends ConsumerState<VideoPreviewEditor> {
  late final VideoPlayerController controller =
      VideoPlayerController.file(widget.file);
  bool muted = false, toolsOpen = true;
  String overlay = '';
  Offset overlayOffset = const Offset(0, .62); // fraction of the frame
  String? error;

  String get _songContext => widget.mode.kind;

  @override
  void initState() {
    super.initState();
    controller.initialize().then((_) {
      if (!mounted) return;
      controller
        ..setLooping(true)
        ..play();
      setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => error = 'This video can\'t be played.');
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _soon(String what) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$what is coming soon')));

  Future<void> _addSound() async {
    final chosen = await showSongPicker(context);
    if (chosen == null || !mounted) return;
    try {
      await ref.read(musicApiProvider).put('/music/selection',
          data: {'id': chosen['id'], 'context': _songContext});
      ref.invalidate(selectedSongProvider(_songContext));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(musicError(e))));
      }
    }
  }

  Future<void> _editText() async {
    final text = TextEditingController(text: overlay);
    final value = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Add text'),
              content: TextField(
                  controller: text,
                  autofocus: true,
                  maxLength: 80,
                  decoration:
                      const InputDecoration(hintText: 'Say something…')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, ''),
                    child: const Text('Remove')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, text.text.trim()),
                    child: const Text('Done')),
              ],
            ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (value != null && mounted) setState(() => overlay = value);
  }

  void _next() {
    final duration = controller.value.duration.inMilliseconds / 1000;
    final (minimum, maximum) = widget.mode.limits;
    if (controller.value.isInitialized &&
        (duration < minimum || duration > maximum + .2)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${widget.mode.label}s must be ${_clock(Duration(seconds: minimum))}–${_clock(Duration(seconds: maximum))} long.')));
      return;
    }
    controller.pause();
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
            builder: (_) => UploadDetailsScreen(
                file: widget.file,
                mode: widget.mode,
                duration: controller.value.duration,
                initialCaption: overlay)))
        .then((_) {
      if (mounted) controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(selectedSongProvider(_songContext)).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: LayoutBuilder(builder: (context, box) {
                return Stack(fit: StackFit.expand, children: [
                  // Blurred fill behind the letterboxed video.
                  if (controller.value.isInitialized)
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                            width: controller.value.size.width,
                            height: controller.value.size.height,
                            child: VideoPlayer(controller)),
                      ),
                    )
                  else
                    const ColoredBox(color: Color(0xFF202020)),
                  GestureDetector(
                    onTap: () => setState(() => controller.value.isPlaying
                        ? controller.pause()
                        : controller.play()),
                    child: Center(
                      child: controller.value.isInitialized
                          ? AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: VideoPlayer(controller))
                          : error != null
                              ? Text(error!,
                                  style: const TextStyle(color: Colors.white))
                              : const CircularProgressIndicator(),
                    ),
                  ),
                  if (overlay.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: box.maxHeight * overlayOffset.dy,
                      child: GestureDetector(
                        onTap: _editText,
                        onVerticalDragUpdate: (d) => setState(() =>
                            overlayOffset = Offset(
                                0,
                                (overlayOffset.dy +
                                        d.delta.dy / box.maxHeight)
                                    .clamp(.05, .9))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(overlay,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(color: Colors.black54, blurRadius: 12)
                                  ])),
                        ),
                      ),
                    ),
                  if (controller.value.isInitialized &&
                      !controller.value.isPlaying)
                    const IgnorePointer(
                      child: Center(
                          child: Icon(Icons.play_arrow_rounded,
                              size: 72, color: Colors.white70)),
                    ),
                  // Top controls.
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Row(children: [
                      _GlassCircle(
                          tooltip: 'Back',
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 28)),
                      const Spacer(),
                      Material(
                        color: Colors.black.withValues(alpha: .45),
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: _addSound,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.music_note_outlined,
                                  color: Colors.white, size: 24),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 150),
                                child: Text(
                                    song?['title'] as String? ?? 'Add sound',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                      const Spacer(),
                      _GlassCircle(
                          tooltip: muted ? 'Unmute' : 'Mute',
                          onTap: () {
                            setState(() => muted = !muted);
                            controller.setVolume(muted ? 0 : 1);
                          },
                          child: Icon(
                              muted
                                  ? Icons.volume_off_outlined
                                  : Icons.volume_up_outlined,
                              color: Colors.white,
                              size: 26)),
                    ]),
                  ),
                  // Right tool rail.
                  Positioned(
                    right: 12,
                    top: box.maxHeight * .27,
                    child: _ToolRail(
                      open: toolsOpen,
                      onToggle: () => setState(() => toolsOpen = !toolsOpen),
                      onText: _editText,
                      onEffects: () => _soon('Effects'),
                      onFilters: () => _soon('Filters'),
                      onStickers: () => _soon('Stickers'),
                      onCaptions: () => _soon('Auto captions'),
                    ),
                  ),
                ]);
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(children: [
              Expanded(
                child: _PillButton(
                  label: 'Edit',
                  icon: Icons.view_agenda_outlined,
                  dark: true,
                  onTap: () => _soon('Trimming'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: _PillButton(
                      label: 'Next', dark: false, onTap: _next)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle(
      {required this.child, required this.onTap, required this.tooltip});
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: .45),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 50, height: 50, child: Center(child: child)),
          ),
        ),
      );
}

class _ToolRail extends StatelessWidget {
  const _ToolRail(
      {required this.open,
      required this.onToggle,
      required this.onText,
      required this.onEffects,
      required this.onFilters,
      required this.onStickers,
      required this.onCaptions});
  final bool open;
  final VoidCallback onToggle,
      onText,
      onEffects,
      onFilters,
      onStickers,
      onCaptions;

  Widget _tool(String tip, Widget icon, VoidCallback tap) => IconButton(
      tooltip: tip,
      onPressed: tap,
      constraints: const BoxConstraints.tightFor(width: 56, height: 54),
      icon: icon);

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .38),
            borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (open) ...[
              _tool(
                  'Text',
                  const Text('Aa',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w500)),
                  onText),
              _tool('Effects',
                  const Icon(Icons.auto_awesome_outlined, color: Colors.white, size: 26),
                  onEffects),
              _tool(
                  'Filters',
                  SvgPicture.asset('assets/images/chat_icons/filters.svg',
                      width: 26,
                      height: 26,
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn)),
                  onFilters),
              _tool(
                  'Stickers',
                  SvgPicture.asset('assets/images/chat_icons/sticker.svg',
                      width: 26,
                      height: 26,
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn)),
                  onStickers),
              _tool(
                  'Captions',
                  const Icon(Icons.subtitles_outlined,
                      color: Colors.white, size: 26),
                  onCaptions),
            ],
            _tool(
                open ? 'Hide tools' : 'Show tools',
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .18)),
                  child: Icon(
                      open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: Colors.white,
                      size: 22),
                ),
                onToggle),
          ]),
        ),
      );
}

class _PillButton extends StatelessWidget {
  const _PillButton(
      {required this.label,
      required this.dark,
      required this.onTap,
      this.icon,
      this.busy = false});
  final String label;
  final bool dark, busy;
  final IconData? icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : Colors.black;
    return Material(
      color: dark
          ? const Color(0xFF2E2F33)
          : (onTap == null ? Colors.white54 : const Color(0xFFF2F2F2)),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else if (icon != null)
              Icon(icon, color: fg, size: 24),
            if (busy || icon != null) const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
// 3. Add details
// =============================================================================

class UploadDetailsScreen extends ConsumerStatefulWidget {
  const UploadDetailsScreen(
      {required this.file,
      required this.mode,
      required this.duration,
      this.initialCaption = '',
      super.key});
  final File file;
  final UploadMode mode;
  final Duration duration;
  final String initialCaption;
  @override
  ConsumerState<UploadDetailsScreen> createState() =>
      _UploadDetailsScreenState();
}

class _UploadDetailsScreenState extends ConsumerState<UploadDetailsScreen> {
  late final caption = TextEditingController(text: widget.initialCaption);
  String visibility = 'public', audience = 'everyone', description = '';
  String? location;
  PlayableVideo? related;
  final playlists = <String, String>{}; // id → name
  bool paidPromotion = false, uploading = false;
  double progress = 0;

  @override
  void initState() {
    super.initState();
    caption.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  String get _noun => widget.mode == UploadMode.short ? 'Short' : 'video';

  Future<T?> _sheet<T>(Widget Function(BuildContext) builder) =>
      showModalBottomSheet<T>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          backgroundColor: _sheetColor,
          builder: (c) => SafeArea(child: builder(c)));

  Future<void> _pickVisibility() async {
    final value = await _sheet<String>((c) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (id, icon, title, sub) in const [
                ('public', Icons.public, 'Public',
                    'Everyone can watch and find your video'),
                ('unlisted', Icons.link_rounded, 'Unlisted',
                    'Anyone with the link can watch'),
                ('private', Icons.lock_outline_rounded, 'Private',
                    'Only you can watch'),
              ])
                RadioListTile<String>(
                  value: id,
                  groupValue: visibility,
                  onChanged: (v) => Navigator.pop(c, v),
                  secondary: Icon(icon),
                  title: Text(title),
                  subtitle: Text(sub),
                ),
              const SizedBox(height: 8),
            ]));
    if (value != null) setState(() => visibility = value);
  }

  Future<void> _pickAudience() async {
    final value = await _sheet<String>((c) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Who is this video for?',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              for (final (id, title, sub) in const [
                ('everyone', 'Everyone', 'Suitable for all audiences'),
                ('adults', 'Viewers 18+',
                    'Age-restrict this video to adult viewers'),
              ])
                RadioListTile<String>(
                  value: id,
                  groupValue: audience,
                  onChanged: (v) => Navigator.pop(c, v),
                  title: Text(title),
                  subtitle: Text(sub),
                ),
              const SizedBox(height: 8),
            ]));
    if (value != null) setState(() => audience = value);
  }

  Future<void> _editDescription() async {
    final value = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => _DescriptionPage(initial: description)));
    if (value != null) setState(() => description = value);
  }

  Future<void> _editLocation() async {
    final text = TextEditingController(text: location ?? '');
    final value = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Location'),
              content: TextField(
                  controller: text,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.location_on_outlined),
                      hintText: 'Search or type a place')),
              actions: [
                if (location != null)
                  TextButton(
                      onPressed: () => Navigator.pop(d, ''),
                      child: const Text('Remove')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, text.text.trim()),
                    child: const Text('Done')),
              ],
            ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (value != null) {
      setState(() => location = value.isEmpty ? null : value);
    }
  }

  Future<void> _pickRelated() async {
    final me = ref.read(authControllerProvider).valueOrNull;
    final mine = (await ref.read(socialVideoCatalogProvider.future))
        .where((v) => v.creator == me?.username)
        .toList();
    if (!mounted) return;
    final chosen = await _sheet<Object>((c) => ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .6),
          child: mine.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                      'Upload another video first to link it as a related video.',
                      textAlign: TextAlign.center))
              : ListView(shrinkWrap: true, children: [
                  if (related != null)
                    ListTile(
                        leading: const Icon(Icons.close_rounded),
                        title: const Text('Remove related video'),
                        onTap: () => Navigator.pop(c, false)),
                  for (final video in mine)
                    ListTile(
                      leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                              width: 72,
                              height: 44,
                              child: video.thumbnailUrl == null
                                  ? const ColoredBox(color: Colors.white10)
                                  : Image.network(
                                      AppConfig.mediaUrl(video.thumbnailUrl!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const ColoredBox(
                                              color: Colors.white10)))),
                      title: Text(video.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: related?.id == video.id
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(c, video),
                    ),
                ]),
        ));
    if (chosen == false) setState(() => related = null);
    if (chosen is PlayableVideo) setState(() => related = chosen);
  }

  Future<void> _pickPlaylists() async {
    List<Map> rows;
    try {
      rows = (await ref.read(playlistsProvider('social').future))
          .whereType<Map>()
          .toList();
    } catch (_) {
      rows = [];
    }
    if (!mounted) return;
    final selected = Map<String, String>.from(playlists);
    final result = await _sheet<Map<String, String>>((c) => StatefulBuilder(
          builder: (c, update) => Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Save to playlists',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700))),
            ),
            for (final row in rows)
              CheckboxListTile(
                value: selected.containsKey(row['id']),
                onChanged: (on) => update(() => on == true
                    ? selected[row['id'] as String] = row['name'] as String
                    : selected.remove(row['id'])),
                title: Text(row['name'] as String),
                secondary: const Icon(Icons.playlist_play_rounded),
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await _askName(c);
                if (name == null) return;
                try {
                  final created = (await getIt<ApiClient>().dio.post(
                          '/playlists',
                          data: {'platform': 'social', 'name': name}))
                      .data as Map;
                  ref.invalidate(playlistsProvider('social'));
                  update(() {
                    rows = [...rows, created];
                    selected[created['id'] as String] = name;
                  });
                } catch (_) {}
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => Navigator.pop(c, selected),
                      child: const Text('Done'))),
            ),
          ]),
        ));
    if (result != null) {
      setState(() => playlists
        ..clear()
        ..addAll(result));
    }
  }

  Future<String?> _askName(BuildContext c) async {
    final text = TextEditingController();
    final value = await showDialog<String>(
        context: c,
        builder: (d) => AlertDialog(
              title: const Text('New playlist'),
              content: TextField(
                  controller: text,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(hintText: 'Playlist name')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (text.text.trim().isNotEmpty) {
                        Navigator.pop(d, text.text.trim());
                      }
                    },
                    child: const Text('Create')),
              ],
            ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    return value;
  }

  Future<void> _paidPromotion() async {
    final value = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _PaidPromotionPage(initial: paidPromotion)));
    if (value != null) setState(() => paidPromotion = value);
  }

  Future<void> _upload() async {
    if (caption.text.trim().isEmpty) return;
    setState(() {
      uploading = true;
      progress = 0;
    });
    final kind = widget.mode.kind;
    try {
      await ref.read(socialVideoApiProvider).upload(
        widget.file.path,
        caption.text.trim(),
        kind: kind,
        musicId: ref.read(selectedSongProvider(kind)).valueOrNull?['id']
            as String?,
        details: {
          'description': description,
          'visibility': visibility,
          'audience': audience,
          if (location != null) 'location': location,
          if (related != null) 'related_video': related!.id,
          'paid_promotion': paidPromotion.toString(),
          if (playlists.isNotEmpty) 'playlist_ids': playlists.keys.join(','),
        },
        onProgress: (sent, total) {
          if (mounted) setState(() => progress = total > 0 ? sent / total : 0);
        },
      );
      ref.invalidate(socialVideoCatalogProvider);
      ref.invalidate(playlistsProvider('social'));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
      messenger.showSnackBar(SnackBar(
          content: Text(
              '${widget.mode == UploadMode.short ? 'Short' : 'Video'} uploaded')));
    } on DioException catch (e) {
      final data = e.response?.data;
      String? message;
      if (data is Map) {
        message = data['detail'] is String ? data['detail'] as String : null;
        if (data['error'] is Map) {
          message = data['error']['message'] as String?;
        }
      }
      _fail(message ?? 'Upload failed. Please try again.');
    } catch (_) {
      _fail('Upload failed. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => uploading = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _row(
          {required Widget icon,
          required String title,
          String? overline,
          String? subtitle,
          Widget? trailing,
          required VoidCallback onTap}) =>
      InkWell(
        onTap: uploading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            SizedBox(width: 32, child: Center(child: icon)),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (overline != null)
                      Text(overline,
                          style: const TextStyle(
                              fontSize: 13, color: PhlioColors.textMuted)),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18,
                            color: PhlioColors.textPrimary,
                            fontWeight: FontWeight.w500)),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, color: PhlioColors.textMuted)),
                      ),
                  ]),
            ),
            trailing ??
                const Icon(Icons.chevron_right_rounded,
                    size: 30, color: PhlioColors.textPrimary),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final visibilityIcon = switch (visibility) {
      'unlisted' => Icons.link_rounded,
      'private' => Icons.lock_outline_rounded,
      _ => Icons.public,
    };
    const iconColor = PhlioColors.textPrimary;
    return PopScope(
      canPop: !uploading,
      child: Scaffold(
        backgroundColor: PhlioColors.background,
        appBar: AppBar(
          backgroundColor: PhlioColors.background,
          titleSpacing: 4,
          title: const Text('Add details',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ),
        body: Column(children: [
          Expanded(
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _CoverThumb(
                      file: widget.file,
                      duration: widget.duration,
                      onEdit: uploading ? null : () => Navigator.pop(context)),
                  const SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      controller: caption,
                      enabled: !uploading,
                      maxLength: 160,
                      maxLines: 6,
                      minLines: 1,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                          hintText: 'Caption your $_noun',
                          hintStyle: const TextStyle(
                              fontSize: 18, color: PhlioColors.textMuted),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.only(top: 8)),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1, color: PhlioColors.borderSubtle),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  MeAvatar(name: me?.fullName ?? 'You', size: 46),
                  const SizedBox(width: 16),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me?.fullName ?? '',
                        style: const TextStyle(fontSize: 17)),
                    Text('@${me?.username ?? ''}',
                        style: const TextStyle(
                            fontSize: 16, color: PhlioColors.textSecondary)),
                  ]),
                ]),
              ),
              _row(
                  icon: Icon(visibilityIcon, size: 30, color: iconColor),
                  overline: 'Visibility',
                  title: switch (visibility) {
                    'unlisted' => 'Unlisted',
                    'private' => 'Private',
                    _ => 'Public',
                  },
                  onTap: _pickVisibility),
              _row(
                  icon: const Icon(Icons.people_outline_rounded,
                      size: 30, color: iconColor),
                  title: 'Select audience',
                  subtitle: audience == 'adults' ? 'Viewers 18+' : 'Everyone',
                  onTap: _pickAudience),
              _row(
                  icon: const Icon(Icons.notes_rounded,
                      size: 30, color: iconColor),
                  title: 'Add description',
                  subtitle: description.split('\n').first,
                  onTap: _editDescription),
              _row(
                  icon: const Icon(Icons.location_on_outlined,
                      size: 30, color: iconColor),
                  title: 'Location',
                  subtitle: location,
                  onTap: _editLocation),
              _row(
                  icon: const Icon(Icons.play_arrow_outlined,
                      size: 32, color: iconColor),
                  title: 'Related video',
                  subtitle: related?.title,
                  onTap: _pickRelated),
              _row(
                  icon: const Icon(Icons.playlist_add_rounded,
                      size: 32, color: iconColor),
                  title: 'Add to playlists',
                  subtitle: playlists.values.join(', '),
                  trailing: const Icon(Icons.add_rounded,
                      size: 30, color: iconColor),
                  onTap: _pickPlaylists),
              _row(
                  icon: const Icon(Icons.paid_outlined,
                      size: 30, color: iconColor),
                  title: 'Paid promotion & brands',
                  subtitle: paidPromotion ? 'Includes paid promotion' : null,
                  onTap: _paidPromotion),
              const SizedBox(height: 12),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (uploading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: progress == 0 ? null : progress, minHeight: 4),
                  ),
                  const SizedBox(height: 10),
                ],
                _PillButton(
                  label: uploading
                      ? 'Uploading ${(progress * 100).round()}%'
                      : 'Upload ${widget.mode == UploadMode.short ? 'Short' : 'video'}',
                  dark: false,
                  busy: uploading,
                  onTap: uploading || caption.text.trim().isEmpty
                      ? null
                      : _upload,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Video still with the pencil (back to preview) and duration badge.
class _CoverThumb extends StatefulWidget {
  const _CoverThumb(
      {required this.file, required this.duration, required this.onEdit});
  final File file;
  final Duration duration;
  final VoidCallback? onEdit;
  @override
  State<_CoverThumb> createState() => _CoverThumbState();
}

class _CoverThumbState extends State<_CoverThumb> {
  late final VideoPlayerController controller =
      VideoPlayerController.file(widget.file);
  @override
  void initState() {
    super.initState();
    controller.initialize().then((_) async {
      await controller.setVolume(0);
      await controller
          .seekTo(Duration(milliseconds: controller.value.duration.inMilliseconds ~/ 3));
      if (mounted) setState(() {});
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 124,
          height: 168,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFF26292F)),
            if (controller.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller)),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.black.withValues(alpha: .55),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onEdit,
                  child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.edit_outlined,
                          color: Colors.white, size: 22)),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(_clock(widget.duration),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      );
}

class _DescriptionPage extends StatefulWidget {
  const _DescriptionPage({required this.initial});
  final String initial;
  @override
  State<_DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<_DescriptionPage> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PhlioColors.background,
        appBar: AppBar(
          backgroundColor: PhlioColors.background,
          title: const Text('Add description'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, text.text.trim()),
                child: const Text('Save')),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: text,
            autofocus: true,
            maxLength: 5000,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 16, height: 1.45),
            decoration: const InputDecoration(
                hintText:
                    'Tell viewers about your video. Add #tags, @mentions and links.',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none),
          ),
        ),
      );
}

class _PaidPromotionPage extends StatefulWidget {
  const _PaidPromotionPage({required this.initial});
  final bool initial;
  @override
  State<_PaidPromotionPage> createState() => _PaidPromotionPageState();
}

class _PaidPromotionPageState extends State<_PaidPromotionPage> {
  late bool value = widget.initial;
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(context, value);
        },
        child: Scaffold(
          backgroundColor: PhlioColors.background,
          appBar: AppBar(
              backgroundColor: PhlioColors.background,
              title: const Text('Paid promotion & brands')),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: value,
              activeTrackColor: PhlioColors.brandViolet,
              onChanged: (v) => setState(() => value = v),
              title: const Text('My video contains paid promotion',
                  style: TextStyle(fontSize: 17)),
              subtitle: const Text(
                  'Product placements, sponsorships or endorsements. Viewers will see an "Includes paid promotion" label.'),
            ),
            const SizedBox(height: 16),
            Text(
                'You are responsible for following the advertising rules where you live, including disclosing paid promotions.',
                style: PhlioTypography.caption
                    .copyWith(color: PhlioColors.textMuted, fontSize: 13)),
          ]),
        ),
      );
}

