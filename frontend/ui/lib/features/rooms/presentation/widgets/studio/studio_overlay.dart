// Text and sticker overlays: one painter used for the live preview and for
// the PNGs uploaded at export, so they look identical in both.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_model.dart';

const _brandGradient = [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F)];

/// Lays out an overlay at a given canvas width. Sizes are relative to the
/// canvas so preview and export match at any resolution.
class OverlayLayout {
  OverlayLayout(this.o, this.canvasWidth, {this.image}) {
    if (o.isText) {
      final fontSize = o.size * canvasWidth;
      painter = TextPainter(
        text: TextSpan(text: o.text.isEmpty ? 'Text' : o.text, style: textStyle(fontSize)),
        textAlign: switch (o.align) {
          'left' => TextAlign.left,
          'right' => TextAlign.right,
          _ => TextAlign.center,
        },
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: canvasWidth * .9);
      final pad = o.style == 'box' || o.style == 'gradient'
          ? Offset(fontSize * .45, fontSize * .22)
          : Offset(fontSize * .12, fontSize * .12);
      padding = pad;
      size = Size(painter!.width + pad.dx * 2, painter!.height + pad.dy * 2);
    } else {
      final w = o.size * canvasWidth;
      final ratio = image == null ? 1.0 : image!.height / image!.width;
      size = Size(w, w * ratio);
      padding = Offset.zero;
    }
  }

  final StudioOverlay o;
  final double canvasWidth;
  final ui.Image? image;
  TextPainter? painter;
  late Size size;
  late Offset padding;

  TextStyle textStyle(double fontSize) {
    final family = o.font;
    final base = TextStyle(
      fontFamily: family,
      fontFamilyFallback: const ['Manrope', 'Roboto', 'sans-serif'],
      fontSize: fontSize,
      height: 1.15,
      fontWeight: o.bold ? FontWeight.w800 : FontWeight.w500,
      color: Color(o.color),
    );
    switch (o.style) {
      case 'shadow':
        return base.copyWith(shadows: [
          Shadow(
              color: Colors.black.withValues(alpha: .55),
              blurRadius: fontSize * .18,
              offset: Offset(0, fontSize * .05)),
        ]);
      case 'neon':
        final glow = Color(o.accent);
        return base.copyWith(shadows: [
          Shadow(color: glow, blurRadius: fontSize * .25),
          Shadow(color: glow, blurRadius: fontSize * .6),
          Shadow(color: glow.withValues(alpha: .6), blurRadius: fontSize * 1.1),
        ]);
      case 'box':
        final bg = Color(o.accent);
        final light = bg.computeLuminance() > .55;
        return base.copyWith(
            color: o.color == 0xFFFFFFFF && light ? const Color(0xFF0B0F17) : Color(o.color));
      default:
        return base;
    }
  }

  /// Paints the overlay with its centre at the origin (unrotated).
  void paint(Canvas canvas) {
    final rect = Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height);
    if (!o.isText) {
      if (image != null) {
        canvas.drawImageRect(
            image!,
            Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
            rect,
            Paint()..filterQuality = FilterQuality.high);
      } else if (o.sticker != null) {
        final tp = TextPainter(
          text: TextSpan(text: o.sticker, style: TextStyle(fontSize: size.width * .82)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      }
      return;
    }
    final fontSize = o.size * canvasWidth;
    final radius = Radius.circular(fontSize * .32);
    if (o.style == 'box') {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = Color(o.accent));
    } else if (o.style == 'gradient') {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, radius),
          Paint()
            ..shader = const LinearGradient(colors: _brandGradient)
                .createShader(rect));
    }
    final origin = Offset(rect.left + padding.dx, rect.top + padding.dy);
    if (o.style == 'outline') {
      final stroke = TextPainter(
        text: TextSpan(
          text: o.text.isEmpty ? 'Text' : o.text,
          // A fresh style: `foreground` can't be combined with `color`.
          style: TextStyle(
            fontFamily: o.font,
            fontFamilyFallback: const ['Manrope', 'Roboto', 'sans-serif'],
            fontSize: fontSize,
            height: 1.15,
            fontWeight: o.bold ? FontWeight.w800 : FontWeight.w500,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = fontSize * .14
              ..strokeJoin = StrokeJoin.round
              ..color = Color(o.accent),
          ),
        ),
        textAlign: painter!.textAlign,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: canvasWidth * .9);
      stroke.paint(canvas, origin);
    }
    painter!.paint(canvas, origin);
  }
}

/// Bundled sticker images (Foxy pack), decoded once.
class StickerImages {
  static final Map<String, ui.Image> _cache = {};
  static Future<ui.Image?> load(String? asset) async {
    if (asset == null) return null;
    final hit = _cache[asset];
    if (hit != null) return hit;
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      return _cache[asset] = image;
    } catch (_) {
      return null;
    }
  }

  static ui.Image? peek(String? asset) => asset == null ? null : _cache[asset];
}

/// Preview widget: the overlay at its canvas position, with optional
/// selection chrome and in/out animation driven by [t].
class OverlayView extends StatelessWidget {
  const OverlayView({
    required this.overlay,
    required this.canvas,
    required this.t,
    this.selected = false,
    this.animate = true,
    this.onTap,
    this.onDoubleTap,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.onDelete,
    this.onDuplicate,
    this.onHandle,
    super.key,
  });
  final StudioOverlay overlay;
  final Size canvas;
  final double t;
  final bool selected, animate;
  final VoidCallback? onTap, onDoubleTap, onDelete, onDuplicate;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  /// Corner handle drag: scale + rotate around the centre (one finger).
  final void Function(DragUpdateDetails details, Offset centre)? onHandle;

  @override
  Widget build(BuildContext context) {
    final o = overlay;
    final layout = OverlayLayout(o, canvas.width, image: StickerImages.peek(o.asset));
    final size = layout.size;
    final m = overlayMotion(o, t, canvas, animate: animate);
    return Positioned(
      left: m.x * canvas.width - size.width / 2,
      top: m.y * canvas.height - size.height / 2,
      width: size.width,
      height: size.height,
      child: Opacity(
        opacity: m.opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: m.rotation,
          child: Transform.scale(
            scale: m.scale,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onScaleStart: onScaleStart,
            onScaleUpdate: onScaleUpdate,
            onScaleEnd: onScaleEnd,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: CustomPaint(painter: _OverlayPainter(layout))),
              if (selected) ...[
                Positioned(
                  left: -6,
                  top: -6,
                  right: -6,
                  bottom: -6,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                _Corner(left: -16, top: -16, icon: Icons.close_rounded, onTap: onDelete),
                _Corner(right: -16, top: -16, icon: Icons.copy_rounded, onTap: onDuplicate),
                Positioned(
                  right: -16,
                  bottom: -16,
                  child: Builder(builder: (context) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) {
                        final box = context.findAncestorRenderObjectOfType<RenderBox>();
                        final centre = box == null
                            ? Offset.zero
                            : box.localToGlobal(box.size.center(Offset.zero));
                        onHandle?.call(d, centre);
                      },
                      child: const _Knob(icon: Icons.open_in_full_rounded),
                    );
                  }),
                ),
              ],
            ]),
          ),
          ),
        ),
      ),
    );
  }
}

/// Where an overlay is at [t]: keyframes + in / out / loop animations
/// (the same curves the server renders). Scale is relative to [o.size].
({double x, double y, double scale, double rotation, double opacity}) overlayMotion(
    StudioOverlay o, double t, Size canvas,
    {bool animate = true}) {
  final k = o.at(t);
  var x = k.x, y = k.y, scale = k.size / o.size, rot = k.rotation, op = k.opacity;
  if (!animate) return (x: x, y: y, scale: scale, rotation: rot, opacity: op);
  final l = t - o.start, left = o.end - t;
  final d = math.min(.35, math.max(.05, (o.end - o.start) / 4));
  final ramp = 1 - (l / .35).clamp(0.0, 1.0);
  switch (o.animIn) {
    case 'fade':
      op *= (l / d).clamp(0.0, 1.0);
    case 'slide_up':
      y += ramp * .06;
    case 'slide_left':
      x += ramp * .12;
    case 'drop':
      y -= ramp * ramp * .15;
    case 'pop':
      final p = (l / .3).clamp(0.0, 1.0);
      scale *= 1 + .25 * (1 - p) * math.sin(p * math.pi) - .6 * (1 - (l / .15).clamp(0.0, 1.0));
  }
  switch (o.animOut) {
    case 'fade':
      op *= (left / d).clamp(0.0, 1.0);
    case 'slide_down':
      y += (1 - (left / .35).clamp(0.0, 1.0)) * .06;
    case 'shrink':
      scale *= (left / .3).clamp(0.0, 1.0);
  }
  switch (o.loop) {
    case 'bounce':
      y -= (math.sin(t * 4)).abs() * .025;
    case 'pulse':
      scale *= 1 + .07 * math.sin(t * 6);
    case 'wiggle':
      rot += .09 * math.sin(t * 9);
    case 'float':
      x += math.sin(t * 1.6) * .01;
      y += math.sin(t * 2.1) * .015;
    case 'blink':
      op *= .55 + .45 * math.sin(t * 5);
  }
  return (x: x, y: y, scale: math.max(0.0, scale), rotation: rot, opacity: op);
}

class _Corner extends StatelessWidget {
  const _Corner({this.left, this.right, this.top, required this.icon, this.onTap});
  final double? left, right, top;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Positioned(
        left: left,
        right: right,
        top: top,
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: _Knob(icon: icon)),
      );
}

class _Knob extends StatelessWidget {
  const _Knob({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 6)
          ],
        ),
        child: Icon(icon, size: 15, color: const Color(0xFF0B0F17)),
      );
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.layout);
  final OverlayLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    layout.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}

/// Renders an overlay to a PNG for the server compositor. Returns the file
/// plus where its (rotated) bounding box sits on the canvas.
Future<({File file, double x, double y, double w})> rasterizeOverlay(
    StudioOverlay o, double canvasWidth, double canvasHeight, Directory dir,
    {bool upright = false}) async {
  final angle = upright ? 0.0 : o.rotation;
  final image = await StickerImages.load(o.asset);
  final layout = OverlayLayout(o, canvasWidth, image: image);
  final w = layout.size.width, h = layout.size.height;
  final c = math.cos(angle).abs(), s = math.sin(angle).abs();
  // Glows/shadows spill outside the box: pad the bitmap.
  final spill = o.isText ? o.size * canvasWidth * .9 : 4.0;
  final bw = (w * c + h * s + spill * 2).ceil(), bh = (w * s + h * c + spill * 2).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(bw / 2, bh / 2);
  canvas.rotate(angle);
  layout.paint(canvas);
  final picture = recorder.endRecording();
  final img = await picture.toImage(bw, bh);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final file = File('${dir.path}/overlay_${o.id}.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  final cx = o.x * canvasWidth, cy = o.y * canvasHeight;
  return (
    file: file,
    x: (cx - bw / 2) / canvasWidth,
    y: (cy - bh / 2) / canvasHeight,
    w: bw / canvasWidth,
  );
}
