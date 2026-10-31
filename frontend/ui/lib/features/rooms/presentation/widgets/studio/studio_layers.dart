// Overlay media (picture-in-picture) for Phlio Studio: the on-canvas layer
// with its keyframed placement, plus the mask shapes. One mask painter feeds
// both the live preview (as an alpha mask) and the PNG uploaded at export
// (as a grayscale matte the server alpha-merges), so the two always match.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../shared/media/phlio_look_view.dart';
import 'studio_model.dart';

/// Paints [pip]'s mask into [size]. [matte]: white-on-black for the server;
/// otherwise opaque-where-visible for the preview.
void paintStudioMask(Canvas canvas, Size size, StudioPip pip, {bool matte = false}) {
  final w = size.width, h = size.height;
  final full = Offset.zero & size;
  final on = matte ? Colors.white : Colors.black;
  final off = matte ? Colors.black : Colors.transparent;
  canvas.drawRect(full, Paint()..color = pip.maskInvert ? on : off);
  final feather = pip.maskFeather * math.min(w, h) * .25;
  final paint = Paint()
    ..color = pip.maskInvert ? off : on
    ..blendMode = pip.maskInvert && !matte ? BlendMode.clear : BlendMode.srcOver;
  if (feather > .5) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, feather);
  canvas.save();
  canvas.translate(w / 2, h / 2);
  canvas.rotate(pip.maskRotation);
  final m = math.min(w, h) * pip.maskSize;
  final big = (w + h) * 2;
  switch (pip.mask) {
    case 'linear':
      // Visible above the line (drag the size to move the line).
      final offset = (pip.maskSize - .5) * h;
      canvas.drawRect(Rect.fromLTRB(-big, -big, big, offset), paint);
    case 'mirror':
      final band = pip.maskSize * h / 2;
      canvas.drawRect(Rect.fromLTRB(-big, -band, big, band), paint);
    case 'circle':
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w * pip.maskSize, height: h * pip.maskSize),
          paint);
    case 'rect':
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: w * pip.maskSize, height: h * pip.maskSize),
              Radius.circular(m * .08)),
          paint);
    case 'heart':
      canvas.drawPath(_heart(m), paint);
    case 'star':
      canvas.drawPath(_star(m), paint);
    default:
      canvas.drawRect(Rect.fromLTRB(-big, -big, big, big), paint);
  }
  canvas.restore();
}

Path _heart(double s) {
  final r = s / 2;
  return Path()
    ..moveTo(0, r * .95)
    ..cubicTo(-r * 1.25, r * .1, -r * .95, -r * .95, 0, -r * .45)
    ..cubicTo(r * .95, -r * .95, r * 1.25, r * .1, 0, r * .95)
    ..close();
}

Path _star(double s) {
  final path = Path();
  final outer = s / 2, inner = outer * .45;
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / 5;
    final pt = Offset(math.cos(a) * r, math.sin(a) * r);
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  return path..close();
}

/// Grayscale matte PNG for the server (same aspect as the layer).
Future<File> rasterizeMask(StudioPip pip, Directory dir) async {
  const w = 512;
  final h = math.max(2, (w / pip.aspect).round());
  final recorder = ui.PictureRecorder();
  paintStudioMask(Canvas(recorder), Size(w.toDouble(), h.toDouble()), pip, matte: true);
  final img = await recorder.endRecording().toImage(w, h);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final file = File('${dir.path}/mask_${pip.id}.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  return file;
}

/// The overlay layer on the preview canvas.
class PipView extends StatelessWidget {
  const PipView({
    required this.pip,
    required this.canvas,
    required this.t,
    required this.media,
    this.selected = false,
    this.onTap,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    super.key,
  });

  final StudioPip pip;
  final Size canvas;
  final double t;
  final Widget media;
  final bool selected;
  final VoidCallback? onTap;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  @override
  Widget build(BuildContext context) {
    final at = pip.placeAt(t);
    final w = pip.w * canvas.width * at.scale;
    final h = w / pip.aspect;
    var opacity = at.opacity;
    final l = t - pip.at, left = pip.at + pip.length - t;
    final d = math.min(.35, math.max(.05, pip.length / 4));
    if (pip.animIn == 'fade') opacity *= (l / d).clamp(0.0, 1.0);
    if (pip.animOut == 'fade') opacity *= (left / d).clamp(0.0, 1.0);
    Widget layer = SizedBox(width: w, height: h, child: FittedBox(fit: BoxFit.fill, child: media));
    if (pip.flip) {
      layer = Transform(
          alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: layer);
    }
    layer = PhlioLook(grade: pip.grade, child: layer);
    if (pip.mask != 'none') {
      layer = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => _maskShader(rect.size),
        child: layer,
      );
    }
    return Positioned(
      left: at.x * canvas.width - w / 2,
      top: at.y * canvas.height - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: at.rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onScaleStart: onScaleStart,
          onScaleUpdate: onScaleUpdate,
          onScaleEnd: onScaleEnd,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: layer)),
            if (selected)
              Positioned(
                left: -3,
                top: -3,
                right: -3,
                bottom: -3,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            if (selected && pip.mask != 'none')
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _MaskOutline(pip))),
              ),
          ]),
        ),
      ),
    );
  }

  Shader _maskShader(Size size) {
    final recorder = ui.PictureRecorder();
    paintStudioMask(Canvas(recorder), size, pip);
    final image = recorder.endRecording().toImageSync(
        math.max(1, size.width.round()), math.max(1, size.height.round()));
    return ImageShader(image, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);
  }
}

class _MaskOutline extends CustomPainter {
  _MaskOutline(this.pip);
  final StudioPip pip;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFFFB58F);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(pip.maskRotation);
    final m = math.min(size.width, size.height) * pip.maskSize;
    final big = size.width + size.height;
    switch (pip.mask) {
      case 'linear':
        final y = (pip.maskSize - .5) * size.height;
        canvas.drawLine(Offset(-big, y), Offset(big, y), paint);
      case 'mirror':
        final band = pip.maskSize * size.height / 2;
        canvas.drawLine(Offset(-big, -band), Offset(big, -band), paint);
        canvas.drawLine(Offset(-big, band), Offset(big, band), paint);
      case 'circle':
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero, width: size.width * pip.maskSize, height: size.height * pip.maskSize),
            paint);
      case 'rect':
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset.zero, width: size.width * pip.maskSize, height: size.height * pip.maskSize),
            paint);
      case 'heart':
        canvas.drawPath(_heart(m), paint);
      case 'star':
        canvas.drawPath(_star(m), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MaskOutline old) => true;
}
