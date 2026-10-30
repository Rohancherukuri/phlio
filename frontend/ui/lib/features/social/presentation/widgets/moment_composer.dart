// New moment editor, laid out like Instagram's story editor: the photo or
// video fills a rounded 9:16 canvas, a column of labelled tools runs down
// the right (Text, Stickers, Music, Restyle, Label AI, Effects, Save,
// Mention, Draw, Save, Partnership, More), "Add a caption…" sits at the
// bottom, and the bottom bar shares to Your moment or Close Friends.
//
// Photos are flattened with their text/stickers/filter into one PNG before
// upload; videos upload as-is with their layers and filter as data.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_stickers.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/moments/moments.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../../../profile/presentation/widgets/snap_audience.dart';
import 'moment_camera.dart';

Future<void> openMomentComposer(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<void>(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const MomentComposerScreen()));

class _Layer {
  _Layer.text(this.text, this.color, {this.type = 'text'}) : sticker = null;
  _Layer.sticker(this.sticker)
      : type = 'sticker',
        text = '',
        color = Colors.white;

  final String type; // text | mention | sticker
  String text;
  Color color;
  final String? sticker;
  Offset position = const Offset(.5, .42);
  double scale = 1;

  Map<String, dynamic> toJson() => {
        'type': type,
        'text': text,
        if (sticker != null) 'sticker': sticker,
        'x': position.dx,
        'y': position.dy,
        'size': 26 * scale,
        'color':
            '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        if (type == 'mention') 'style': 'pill',
      };
}

class MomentComposerScreen extends ConsumerStatefulWidget {
  const MomentComposerScreen(
      {super.key, this.initialPath, this.initialVideo = false});
  final String? initialPath;
  final bool initialVideo;
  @override
  ConsumerState<MomentComposerScreen> createState() =>
      _MomentComposerScreenState();
}

class _MomentComposerScreenState extends ConsumerState<MomentComposerScreen> {
  static const _gradients = [
    [Color(0xFF8D78FF), Color(0xFFE795D7)],
    [Color(0xFFE795D7), Color(0xFFFFB58F)],
    [Color(0xFF72A7FF), Color(0xFF8D78FF)],
    [Color(0xFF111925), Color(0xFF3A2A5C)],
    [Color(0xFF68D7CD), Color(0xFF72A7FF)],
  ];
  static const _textColors = [
    Colors.white,
    Colors.black,
    Color(0xFFFFB58F),
    Color(0xFFE795D7),
    Color(0xFF8D78FF),
    Color(0xFF68D7CD),
    Color(0xFFF6D365),
    Color(0xFFF5636B),
  ];

  final _canvasKey = GlobalKey();
  final caption = TextEditingController();
  final layers = <_Layer>[];
  String? mediaPath;
  bool isVideo = false, createMode = false;
  int gradient = 0;
  String filter = 'normal';
  bool commentsOff = false, saveToHighlights = false, aiLabel = false;
  bool busy = false;
  double volume = .8;
  String? flash; // transient label (filter name)
  VideoPlayerController? video;
  Offset _scaleStartPosition = Offset.zero;
  double _scaleStartValue = 1;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setMedia(widget.initialPath!, widget.initialVideo);
      });
    }
  }

  @override
  void dispose() {
    caption.dispose();
    video?.dispose();
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  bool get hasContent => mediaPath != null || createMode;

  Future<void> _setMedia(String path, bool asVideo) async {
    final old = video;
    video = null;
    await old?.dispose();
    setState(() {
      mediaPath = path;
      isVideo = asVideo;
      createMode = false;
    });
    if (asVideo) {
      final controller = VideoPlayerController.file(File(path));
      video = controller;
      try {
        await controller.initialize();
        await controller.setLooping(true);
        await controller.setVolume(volume);
        await controller.play();
      } catch (_) {
        _say('Could not play this video.');
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> pickGallery() async {
    try {
      final picked = await ImagePicker().pickMedia();
      if (picked == null) return;
      final lower = picked.path.toLowerCase();
      await _setMedia(
          picked.path,
          ['.mp4', '.mov', '.m4v', '.webm', '.3gp']
              .any((ext) => lower.endsWith(ext)));
    } catch (_) {
      _say('Could not open your gallery.');
    }
  }

  Future<void> openCamera() async {
    final result = await openMomentCamera(context);
    if (result == null || !mounted) return;
    if (result.create) {
      await video?.dispose();
      setState(() {
        video = null;
        mediaPath = null;
        isVideo = false;
        createMode = true;
      });
      await addText();
      return;
    }
    if (result.path != null) await _setMedia(result.path!, result.video);
  }

  // -- Tools ----------------------------------------------------------------

  Future<({String text, Color color})?> _textDialog(
      {String initial = '',
      Color color = Colors.white,
      String hint = 'Type something…'}) {
    final controller = TextEditingController(text: initial);
    var selected = color;
    return showDialog<({String text, Color color})>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setInner) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: selected, fontSize: 28, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: InputBorder.none),
            ),
            const SizedBox(height: 18),
            Wrap(spacing: 10, children: [
              for (final c in _textColors)
                GestureDetector(
                  onTap: () => setInner(() => selected = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected == c ? Colors.white : Colors.white38,
                          width: selected == c ? 3 : 1),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(
                  dialog, (text: controller.text.trim(), color: selected)),
              child: const Text('Done'),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> addText() async {
    final result = await _textDialog();
    if (result == null || result.text.isEmpty) return;
    setState(() => layers.add(_Layer.text(result.text, result.color)));
  }

  Future<void> editText(_Layer layer) async {
    final result = await _textDialog(initial: layer.text, color: layer.color);
    if (result == null) return;
    setState(() {
      if (result.text.isEmpty) {
        layers.remove(layer);
      } else {
        layer
          ..text = result.text
          ..color = result.color;
      }
    });
  }

  Future<void> addMention() async {
    final result = await _textDialog(initial: '@', hint: '@username');
    final handle = result?.text.replaceAll(' ', '') ?? '';
    if (handle.length < 2) return;
    setState(() => layers.add(_Layer.text(
        handle.startsWith('@') ? handle : '@$handle', Colors.white,
        type: 'mention')));
  }

  Future<void> addSticker() async {
    final id = await showFoxyStickerSheet(context,
        includeGiphy: false, includeFaces: false);
    if (id != null) setState(() => layers.add(_Layer.sticker(id)));
  }

  void restyle() {
    final next = momentFilters[
        (momentFilters.indexOf(filter) + 1) % momentFilters.length];
    _setFilter(next);
  }

  void _setFilter(String next) {
    setState(() {
      filter = next;
      flash = next[0].toUpperCase() + next.substring(1);
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => flash = null);
    });
  }

  Future<void> effects() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final name in momentFilters)
                GestureDetector(
                  onTap: () => Navigator.pop(sheet, name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _filtered(
                          name,
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    colors: _gradients[gradient])),
                            child: mediaPath != null && !isVideo
                                ? Image.file(File(mediaPath!),
                                    fit: BoxFit.cover)
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(name[0].toUpperCase() + name.substring(1),
                          style: TextStyle(
                              color: name == filter
                                  ? PhlioColors.brandPeach
                                  : Colors.white)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _setFilter(picked);
  }

  Future<void> saveToDevice() async {
    if (!hasContent) return _say('Add a photo or video first.');
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) return _say('Allow photo access to save.');
      if (isVideo) {
        await PhotoManager.editor.saveVideo(File(mediaPath!),
            title: 'phlio_moment_${DateTime.now().millisecondsSinceEpoch}');
      } else {
        final file = await _flatten();
        await PhotoManager.editor.saveImageWithPath(file.path,
            title: 'phlio_moment_${DateTime.now().millisecondsSinceEpoch}');
      }
      _say('Saved to your gallery');
    } catch (_) {
      _say('Could not save to your gallery.');
    }
  }

  Future<void> more() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setInner) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              secondary: const Icon(Icons.comments_disabled_outlined),
              title: const Text('Turn off commenting'),
              subtitle:
                  const Text('People won\'t be able to reply to this moment'),
              value: commentsOff,
              onChanged: (value) {
                setInner(() {});
                setState(() => commentsOff = value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(sheet);
                openCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheet);
                pickGallery();
              },
            ),
            if (hasContent)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: PhlioColors.danger),
                title: const Text('Discard',
                    style: TextStyle(color: PhlioColors.danger)),
                onTap: () {
                  Navigator.pop(sheet);
                  video?.dispose();
                  setState(() {
                    video = null;
                    mediaPath = null;
                    createMode = false;
                    layers.clear();
                    filter = 'normal';
                  });
                },
              ),
          ]),
        ),
      ),
    );
  }

  void comingSoon(String feature) =>
      _say('$feature for moments is coming soon.');

  // -- Publishing -------------------------------------------------------------

  Future<File> _flatten() async {
    final boundary =
        _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ratio = 1080 / boundary.size.width;
    final image = await boundary.toImage(pixelRatio: ratio.clamp(1.0, 4.0));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/moment_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file;
  }

  Future<void> publish({bool closeFriends = false}) async {
    if (busy) return;
    if (!hasContent) {
      _say('Add a photo or video first.');
      return;
    }
    var audience = const SnapAudience(mode: 'everyone');
    if (closeFriends) {
      final picked = await pickSnapAudience(
          context, const SnapAudience(mode: 'close_friends'));
      if (picked == null || !mounted) return;
      audience = picked;
    }
    setState(() => busy = true);
    try {
      final MultipartFile upload;
      if (isVideo) {
        upload = await MultipartFile.fromFile(mediaPath!,
            filename: mediaPath!.split(Platform.pathSeparator).last,
            contentType: DioMediaType('video', 'mp4'));
      } else {
        final flat = await _flatten();
        upload = await MultipartFile.fromFile(flat.path,
            filename: 'moment.png', contentType: DioMediaType('image', 'png'));
      }
      await getIt<ApiClient>().dio.post(
            '/social/moments',
            data: FormData.fromMap({
              'file': upload,
              'caption': caption.text.trim(),
              'audience': audience.mode,
              'recipients': jsonEncode(audience.recipients),
              'allow_comments': (!commentsOff).toString(),
              'overlays': jsonEncode(
                  isVideo ? [for (final l in layers) l.toJson()] : const []),
              'filter': isVideo ? filter : 'normal',
              'highlight': saveToHighlights ? 'Highlights' : '',
              'ai_label': aiLabel.toString(),
            }),
            options: Options(
                sendTimeout: const Duration(minutes: 3),
                receiveTimeout: const Duration(minutes: 3)),
          );
      refreshMoments(ref);
      ref.invalidate(momentHighlightsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
          content: Text(closeFriends
              ? 'Shared with your close friends for 24 hours'
              : 'Your moment is live for 24 hours')));
    } catch (_) {
      if (mounted) _say('Could not share your moment. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // -- UI -----------------------------------------------------------------------

  Widget _filtered(String name, Widget child) {
    final matrix = momentFilter(name);
    return matrix == null
        ? child
        : ColorFiltered(colorFilter: matrix, child: child);
  }

  Widget _background() {
    if (createMode) {
      return GestureDetector(
        onTap: () =>
            setState(() => gradient = (gradient + 1) % _gradients.length),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _gradients[gradient]),
          ),
        ),
      );
    }
    if (mediaPath == null) {
      return Container(
        color: const Color(0xFF15181E),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome_motion_rounded,
              color: Colors.white38, size: 56),
          const SizedBox(height: 14),
          Text('Share a moment for 24 hours',
              style: PhlioTypography.bodyLarge.copyWith(color: Colors.white70)),
          const SizedBox(height: 18),
          Wrap(spacing: 12, children: [
            OutlinedButton.icon(
                onPressed: pickGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery')),
            FilledButton.icon(
                onPressed: openCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera')),
          ]),
        ]),
      );
    }
    if (isVideo) {
      final controller = video;
      if (controller == null || !controller.value.isInitialized) {
        return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator()));
      }
      return _filtered(
        filter,
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller)),
        ),
      );
    }
    return _filtered(filter, Image.file(File(mediaPath!), fit: BoxFit.cover));
  }

  Widget _layer(_Layer layer, Size canvas) {
    final content = layer.type == 'sticker'
        ? PhlioStickerView(
            stickerId: layer.sticker!,
            size: 110 * layer.scale,
            interactive: false)
        : Container(
            constraints: BoxConstraints(maxWidth: canvas.width * .86),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: layer.type == 'mention'
                  ? Colors.black.withValues(alpha: .45)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(layer.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: layer.color,
                    fontSize: 26 * layer.scale,
                    fontWeight: FontWeight.w700,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 6)
                    ])),
          );
    return Align(
      alignment:
          Alignment(layer.position.dx * 2 - 1, layer.position.dy * 2 - 1),
      child: GestureDetector(
        onTap: layer.type == 'sticker' ? null : () => editText(layer),
        onLongPress: () => setState(() => layers.remove(layer)),
        onScaleStart: (_) {
          _scaleStartPosition = layer.position;
          _scaleStartValue = layer.scale;
        },
        onScaleUpdate: (details) => setState(() {
          _scaleStartPosition += Offset(
              details.focalPointDelta.dx / canvas.width,
              details.focalPointDelta.dy / canvas.height);
          layer.position = Offset(_scaleStartPosition.dx.clamp(.05, .95),
              _scaleStartPosition.dy.clamp(.05, .95));
          layer.scale = (_scaleStartValue * details.scale).clamp(.5, 3.0);
        }),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final tools = <({String label, Widget icon, VoidCallback onTap, bool on})>[
      (
        label: 'Text',
        icon: const Text('Aa',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        onTap: addText,
        on: false
      ),
      (
        label: 'Stickers',
        icon: const Icon(Icons.sticky_note_2_outlined),
        onTap: addSticker,
        on: false
      ),
      (
        label: 'Music',
        icon: const Icon(Icons.music_note_outlined),
        onTap: () => comingSoon('Music'),
        on: false
      ),
      (
        label: 'Restyle',
        icon: const Icon(Icons.brush_outlined),
        onTap: restyle,
        on: filter != 'normal'
      ),
      (
        label: 'Label AI',
        icon: const Icon(Icons.auto_awesome_outlined),
        onTap: () {
          setState(() => aiLabel = !aiLabel);
          _say(aiLabel ? 'Labelled as made with AI' : 'AI label removed');
        },
        on: aiLabel
      ),
      (
        label: 'Effects',
        icon: const Icon(Icons.auto_fix_high_outlined),
        onTap: effects,
        on: false
      ),
      (
        label: 'Save',
        icon: Icon(saveToHighlights
            ? Icons.bookmark_rounded
            : Icons.bookmark_border_rounded),
        onTap: () {
          setState(() => saveToHighlights = !saveToHighlights);
          _say(saveToHighlights
              ? 'Will also be saved to your highlights'
              : 'Won\'t be added to highlights');
        },
        on: saveToHighlights
      ),
      (
        label: 'Mention',
        icon: const Icon(Icons.alternate_email_rounded),
        onTap: addMention,
        on: false
      ),
      (
        label: 'Draw',
        icon: const Icon(Icons.gesture_rounded),
        onTap: () => comingSoon('Drawing'),
        on: false
      ),
      (
        label: 'Save',
        icon: const Icon(Icons.download_rounded),
        onTap: saveToDevice,
        on: false
      ),
      (
        label: 'Partnership',
        icon: const Icon(Icons.handshake_outlined),
        onTap: () => comingSoon('Partnerships'),
        on: false
      ),
      (
        label: 'More',
        icon: const Icon(Icons.more_horiz_rounded),
        onTap: more,
        on: commentsOff
      ),
    ];

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: LayoutBuilder(builder: (context, box) {
                      final canvas = Size(box.maxWidth, box.maxHeight);
                      return Stack(fit: StackFit.expand, children: [
                        RepaintBoundary(
                          key: _canvasKey,
                          child: Stack(fit: StackFit.expand, children: [
                            _background(),
                            if (aiLabel && hasContent)
                              const Positioned(
                                left: 14,
                                bottom: 70,
                                child: _AiChip(),
                              ),
                            for (final layer in layers) _layer(layer, canvas),
                          ]),
                        ),
                        if (flash != null)
                          IgnorePointer(
                            child: Center(
                              child: Text(flash!,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 12)
                                      ])),
                            ),
                          ),
                        Positioned(
                          left: 10,
                          top: 10,
                          child: Material(
                            color: Colors.black38,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Back',
                              onPressed: busy
                                  ? null
                                  : () => Navigator.maybePop(context),
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                        // Right tool column.
                        Positioned(
                          right: 8,
                          top: 8,
                          bottom: 64,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final tool in tools)
                                  _ToolButton(
                                    label: tool.label,
                                    icon: tool.icon,
                                    on: tool.on,
                                    onTap: busy ? () {} : tool.onTap,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (isVideo && video != null)
                          Positioned(
                            left: 14,
                            top: canvas.height * .32,
                            child: _VolumeSlider(
                              value: volume,
                              onChanged: (v) {
                                setState(() => volume = v);
                                video?.setVolume(v);
                              },
                            ),
                          ),
                        Positioned(
                          left: 14,
                          right: 90,
                          bottom: 14,
                          child: TextField(
                            controller: caption,
                            maxLength: 500,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              counterText: '',
                              hintText: 'Add a caption…',
                              hintStyle: TextStyle(color: Colors.white70),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (busy)
                          const ColoredBox(
                              color: Colors.black45,
                              child:
                                  Center(child: CircularProgressIndicator())),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
            // Share bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(children: [
                Expanded(
                  child: _SharePill(
                    onTap: () => publish(),
                    leading: SizedBox(
                        width: 28,
                        height: 28,
                        child: MeAvatar(name: me?.fullName ?? 'You', size: 28)),
                    label: 'Your moment',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SharePill(
                    onTap: () => publish(closeFriends: true),
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                          color: Color(0xFF2BC25B), shape: BoxShape.circle),
                      child: const Icon(Icons.star_rounded,
                          color: Colors.white, size: 18),
                    ),
                    label: 'Close Friends',
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: PhlioColors.brandViolet,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : () => publish(),
                    child: const SizedBox(
                      width: 54,
                      height: 54,
                      child: Icon(Icons.arrow_forward_ios_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.on = false});
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool on;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 8)])),
            const SizedBox(width: 10),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on
                    ? PhlioColors.brandViolet.withValues(alpha: .85)
                    : const Color(0xCC1B1F27),
              ),
              alignment: Alignment.center,
              child: IconTheme(
                  data: const IconThemeData(color: Colors.white, size: 22),
                  child: icon),
            ),
          ]),
        ),
      );
}

class _SharePill extends StatelessWidget {
  const _SharePill(
      {required this.onTap, required this.leading, required this.label});
  final VoidCallback onTap;
  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF1E2229),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.bodyStrong
                        .copyWith(color: Colors.white)),
              ),
            ]),
          ),
        ),
      );
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 190,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(children: [
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: SliderComponentShape.noThumb,
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: Colors.black87,
                  inactiveTrackColor: Colors.black12,
                ),
                child: Slider(value: value, onChanged: onChanged),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Icon(
                value == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.black87),
          ),
        ]),
      );
}

class _AiChip extends StatelessWidget {
  const _AiChip();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: Colors.black45, borderRadius: BorderRadius.circular(12)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text('AI info', style: TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
}
