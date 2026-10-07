import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';
import '../../../../design_system/widgets/foxy_pack.dart';
import 'chat_composer.dart';
import 'chat_policy.dart';
import 'message_sticker_canvas.dart';

class MessageMediaEditor extends StatefulWidget {
  const MessageMediaEditor({required this.attachment, super.key});
  final StagedAttachment attachment;
  @override
  State<MessageMediaEditor> createState() => _MessageMediaEditorState();
}

class _MessageMediaEditorState extends State<MessageMediaEditor> {
  final canvas = GlobalKey();
  ui.Image? image;
  VideoPlayerController? video;
  bool ready = false,
      busy = false,
      square = false,
      monochrome = false,
      mute = false;
  int turns = 0;
  double duration = 1;
  RangeValues range = const RangeValues(0, 1);
  String? error;
  List<Map<String, dynamic>> stickers = [];
  bool get isVideo => widget.attachment.kind == 'video';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (isVideo) {
        final player =
            VideoPlayerController.file(File(widget.attachment.path!));
        video = player;
        await player.initialize();
        if (!mounted) return;
        duration = player.value.duration.inMilliseconds / 1000;
        if (duration <= 0) throw const FormatException('Empty video');
        final edits = widget.attachment.videoEdits;
        range = RangeValues(
          (edits?['start'] as num?)?.toDouble() ?? 0,
          (edits?['end'] as num?)?.toDouble() ?? duration,
        );
        mute = edits?['mute'] == true;
        turns = (edits?['turns'] as int?) ?? 0;
        await player.setVolume(mute ? 0 : 1);
        player.addListener(_tick);
      } else {
        final codec = await ui.instantiateImageCodec(
          await File(widget.attachment.path!).readAsBytes(),
          targetWidth: 2048,
          allowUpscaling: false,
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        if (!mounted) {
          frame.image.dispose();
          return;
        }
        image = frame.image;
      }
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not open this media for editing.');
      }
    }
  }

  void _tick() {
    final p = video;
    if (p != null &&
        p.value.isPlaying &&
        p.value.position.inMilliseconds >= range.end * 1000) {
      p.pause();
      p.seekTo(Duration(milliseconds: (range.start * 1000).round()));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    video?.removeListener(_tick);
    video?.dispose();
    image?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (isVideo) {
        Navigator.pop(
          context,
          StagedAttachment(
            kind: 'video',
            name: widget.attachment.name,
            path: widget.attachment.path,
            size: widget.attachment.size,
            videoEdits: {
              'start': range.start,
              'end': range.end,
              'mute': mute,
              'turns': turns,
            },
          ),
        );
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          canvas.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await boundary.toImage(
        pixelRatio: math.min(3, 2048 / boundary.size.width),
      );
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (data == null) throw const FormatException('Image export failed');
      final bytes = data.buffer.asUint8List();
      final issue = dmMediaError('edited.png', bytes.length);
      if (issue != null) throw FormatException(issue);
      final dir = await Directory.systemTemp.createTemp('phlio_image_edit_');
      final output = File('${dir.path}/edited.png');
      await output.writeAsBytes(bytes);
      if (mounted) {
        Navigator.pop(
          context,
          StagedAttachment(
            kind: 'image',
            name: 'edited.png',
            path: output.path,
            size: bytes.length,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Could not save edits. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final originalRatio = isVideo
        ? video?.value.aspectRatio ?? 1
        : image == null
            ? 1.0
            : image!.width / image!.height;
    final ratio = square
        ? 1.0
        : turns.isOdd
            ? 1 / originalRatio
            : originalRatio;
    return Scaffold(
      appBar: AppBar(
        title: Text(isVideo ? 'Edit video' : 'Edit image'),
        actions: [
          TextButton(
            onPressed: !ready || busy ? null : _save,
            child: Text(busy ? 'Saving…' : 'Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            Expanded(
              child: Center(
                child: !ready
                    ? error != null
                        ? const Icon(Icons.broken_image_outlined)
                        : const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: ratio,
                          child: RepaintBoundary(
                            key: canvas,
                            child: MessageStickerCanvas(
                              overlays: stickers,
                              onChanged: (v) => setState(() => stickers = v),
                              child: AspectRatio(
                                aspectRatio: ratio,
                                child: ClipRect(
                                  child: ColorFiltered(
                                    colorFilter: monochrome
                                        ? const ColorFilter.matrix([
                                            .2126,
                                            .7152,
                                            .0722,
                                            0,
                                            0,
                                            .2126,
                                            .7152,
                                            .0722,
                                            0,
                                            0,
                                            .2126,
                                            .7152,
                                            .0722,
                                            0,
                                            0,
                                            0,
                                            0,
                                            0,
                                            1,
                                            0,
                                          ])
                                        : const ColorFilter.mode(
                                            Colors.transparent,
                                            BlendMode.dst,
                                          ),
                                    child: RotatedBox(
                                      quarterTurns: turns,
                                      child: isVideo
                                          ? VideoPlayer(video!)
                                          : RawImage(
                                              image: image,
                                              fit: BoxFit.cover,
                                              filterQuality: FilterQuality.high,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (ready)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => turns = (turns + 1) % 4),
                            icon: const Icon(Icons.rotate_right),
                            label: const Text('Rotate'),
                          ),
                          if (!isVideo) ...[
                            FilterChip(
                              label: const Text('Square crop'),
                              selected: square,
                              onSelected: (v) => setState(() => square = v),
                            ),
                            FilterChip(
                              label: const Text('Black & white'),
                              selected: monochrome,
                              onSelected: (v) => setState(() => monochrome = v),
                            ),
                            TextButton.icon(
                              onPressed: stickers.length >= 12
                                  ? null
                                  : () async {
                                      final item = await showFoxyPicker(
                                        context,
                                        initialTab: FoxyReactionKind.sticker,
                                        includeGifs: false,
                                        title: 'Add sticker',
                                      );
                                      if (mounted &&
                                          item != null &&
                                          item.kind != FoxyReactionKind.gif) {
                                        setState(
                                          () => stickers.add({
                                            'value': item.id,
                                            'x': .5,
                                            'y': .5,
                                            'scale': 1.0,
                                          }),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.add_reaction_outlined),
                              label: const Text('Sticker'),
                            ),
                          ],
                          if (isVideo) ...[
                            IconButton(
                              tooltip: 'Preview clip',
                              onPressed: () async {
                                if (video!.value.isPlaying) {
                                  await video!.pause();
                                } else {
                                  await video!.seekTo(
                                    Duration(
                                      milliseconds:
                                          (range.start * 1000).round(),
                                    ),
                                  );
                                  await video!.play();
                                }
                              },
                              icon: Icon(
                                video!.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                            FilterChip(
                              label: const Text('Mute audio'),
                              selected: mute,
                              onSelected: (v) {
                                setState(() => mute = v);
                                video!.setVolume(v ? 0 : 1);
                              },
                            ),
                          ],
                        ],
                      ),
                      if (isVideo) ...[
                        Text(
                          'Trim: ${range.start.toStringAsFixed(1)}s – ${range.end.toStringAsFixed(1)}s',
                        ),
                        RangeSlider(
                          values: range,
                          max: duration,
                          onChanged: (v) {
                            if (v.end - v.start < .1) return;
                            setState(() => range = v);
                            video!.pause();
                            video!.seekTo(
                              Duration(milliseconds: (v.start * 1000).round()),
                            );
                          },
                        ),
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                              'The edited clip is exported when you send.'),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Drag stickers to move • Double-tap to resize • Hold to remove',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
