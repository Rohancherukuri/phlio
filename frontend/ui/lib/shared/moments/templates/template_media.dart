// Moment templates — using a template with your own photo or video.
//
// Like Instagram: pick a photo or video first, open Templates, and every
// design shows your media in its first frame; the editor opens with it in
// place.
//
//   * Photos are baked into the exported 1080 × 1920 PNG, as before.
//   * Videos can't be baked into a PNG, so the design exports as an
//     overlay with a transparent hole where the video frame is. The moment
//     uploads the video unchanged plus a `template` overlay:
//
//       {type: template, data: {url: /media/post_uploads/….png,
//                               slot: {x, y, w, h, rotation, shape, radius}}}
//
//     and [TemplateVideoFrame] plays the video inside the slot, under the
//     overlay, in the composer and in the moment viewer.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'template_canvas.dart' show slotPath;
import 'template_model.dart';

/// The photo or video a template is being used with.
class TemplateMedia {
  const TemplateMedia(this.path, {this.video = false});
  final String path;
  final bool video;
}

/// Hands the live video (or nothing, while exporting) to video slots.
class TemplateSlotMedia extends InheritedWidget {
  const TemplateSlotMedia({required this.media, required super.child, super.key});

  /// What a video slot shows: the playing video, or null for a hole.
  final Widget? media;

  static Widget? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TemplateSlotMedia>()?.media;

  @override
  bool updateShouldNotify(TemplateSlotMedia old) => old.media != media;
}

/// Where the video plays: the slot's photo area in design units (360 × 640).
class TemplateVideoSlot {
  const TemplateVideoSlot({
    required this.center,
    required this.size,
    this.rotation = 0,
    this.shape = SlotShape.rect,
    this.radius = 0,
  });

  /// The slot's photo area (inside a polaroid's white card).
  factory TemplateVideoSlot.of(TElement e) {
    var size = e.size;
    var center = e.center;
    if (e.shape == SlotShape.polaroid) {
      // Same margins the canvas draws: 6% sides / top, 20% bottom.
      final pad = e.size.width * .06, bottom = e.size.width * .2;
      size = Size(e.size.width - 2 * pad, e.size.height - pad - bottom);
      // Shift the centre up by half the extra bottom margin, then rotate it.
      final shift = Offset(0, (pad - bottom) / 2);
      final c = math.cos(e.rotation), s = math.sin(e.rotation);
      center = e.center + Offset(shift.dx * c - shift.dy * s, shift.dx * s + shift.dy * c);
    }
    return TemplateVideoSlot(
      center: center,
      size: size,
      rotation: e.rotation,
      shape: e.shape == SlotShape.polaroid ? SlotShape.rect : e.shape,
      radius: e.radius,
    );
  }

  final Offset center;
  final Size size;
  final double rotation;
  final SlotShape shape;
  final double radius;

  Map<String, dynamic> toJson() => {
        'x': center.dx,
        'y': center.dy,
        'w': size.width,
        'h': size.height,
        'rotation': rotation,
        'shape': shape.name,
        'radius': radius,
      };

  static TemplateVideoSlot? fromJson(Object? j) {
    if (j is! Map) return null;
    double d(String k, double fallback) => (j[k] as num? ?? fallback).toDouble();
    return TemplateVideoSlot(
      center: Offset(d('x', 180), d('y', 320)),
      size: Size(d('w', 360), d('h', 640)),
      rotation: d('rotation', 0),
      shape: SlotShape.values.where((s) => s.name == j['shape']).firstOrNull ?? SlotShape.rect,
      radius: d('radius', 0),
    );
  }

  /// The slot outline in design units (for punching the hole).
  Path path() {
    final local = slotPath(shape, radius, size).shift(Offset(-size.width / 2, -size.height / 2));
    final m = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..rotateZ(rotation);
    return local.transform(m.storage);
  }
}

/// A template overlay found in a moment's overlays: (overlay url, slot).
(String url, TemplateVideoSlot slot)? templateFrameOf(List? overlays) {
  for (final raw in overlays ?? const []) {
    if (raw is Map && raw['type'] == 'template' && raw['data'] is Map) {
      final data = raw['data'] as Map;
      final slot = TemplateVideoSlot.fromJson(data['slot']);
      if (data['url'] is String && slot != null) return ('${data['url']}', slot);
    }
  }
  return null;
}

/// Plays [media] inside [slot], under the template [overlay] (the PNG with
/// the hole). Fills its box like a 9:16 cover.
class TemplateVideoFrame extends StatelessWidget {
  const TemplateVideoFrame({required this.slot, required this.overlay, required this.media, super.key});
  final TemplateVideoSlot slot;
  final ImageProvider overlay;
  final Widget media;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox.fromSize(
            size: templateSize,
            child: Stack(children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              Positioned(
                left: slot.center.dx - slot.size.width / 2,
                top: slot.center.dy - slot.size.height / 2,
                width: slot.size.width,
                height: slot.size.height,
                child: Transform.rotate(
                  angle: slot.rotation,
                  child: ClipRect(child: SizedBox.expand(child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: media))),
                ),
              ),
              Positioned.fill(child: Image(image: overlay, fit: BoxFit.fill, gaplessPlayback: true)),
            ]),
          ),
        ),
      );
}

/// Erases [slot] from an exported design (rendered at [scale] px per
/// design unit) and writes the PNG to [file].
Future<File> punchVideoHole(ui.Image design, TemplateVideoSlot slot, double scale, File file) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Offset.zero & Size(design.width.toDouble(), design.height.toDouble());
  canvas.saveLayer(bounds, Paint());
  canvas.drawImage(design, Offset.zero, Paint());
  canvas.scale(scale);
  canvas.drawPath(slot.path(), Paint()..blendMode = BlendMode.clear);
  canvas.restore();
  final image = await recorder.endRecording().toImage(design.width, design.height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return file.writeAsBytes(png!.buffer.asUint8List());
}
