// Moment templates — drawing a template.
//
// [TemplateCanvas] lays a template out at its 360 × 640 design size and
// scales it to whatever box it's given (gallery thumbnails, the editor,
// the 1080 × 1920 export). The backdrop is a GPU shader
// (assets/shaders/moment_backdrop.frag) with a gradient fallback; photo
// slots use Phlio Looks; text supports fonts, highlight / outline / neon /
// gradient / sticker backgrounds.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../media/phlio_look_view.dart';
import 'template_model.dart';

// -- backdrop -------------------------------------------------------------------------

/// Loads the backdrop shader (assets/shaders/moment_backdrop.frag) once for
/// the whole app; also used to fill Phlio type stickers.
class BackdropShader {
  static ui.FragmentProgram? program;
  static Future<ui.FragmentProgram?>? _loading;

  static Future<ui.FragmentProgram?> load() => _loading ??= () async {
        try {
          return program = await ui.FragmentProgram.fromAsset('assets/shaders/moment_backdrop.frag');
        } catch (_) {
          return null; // gradient fallback
        }
      }();
}

/// The template background: the shader (animated when [animate]) or, before
/// it loads / where shaders aren't available, a matching gradient.
class TemplateBackdrop extends StatefulWidget {
  const TemplateBackdrop({required this.backdrop, this.animate = true, this.time, super.key});

  final TBackdrop backdrop;
  final bool animate;

  /// Fixed time (seconds) for a still frame; overrides the animation.
  final double? time;

  @override
  State<TemplateBackdrop> createState() => _TemplateBackdropState();
}

class _TemplateBackdropState extends State<TemplateBackdrop> with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader, _shaderB; // two instances, alternated so each frame repaints
  Ticker? _ticker;
  double _t = 2.5;
  bool _flip = false;

  @override
  void initState() {
    super.initState();
    BackdropShader.load().then((p) {
      if (p != null && mounted) {
        setState(() {
          _shader = p.fragmentShader();
          _shaderB = p.fragmentShader();
        });
      }
    });
    _sync();
  }

  @override
  void didUpdateWidget(TemplateBackdrop old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.animate && widget.backdrop.animate && widget.time == null;
    if (run && _ticker == null) {
      _ticker = createTicker((e) {
        _t = 2.5 + e.inMicroseconds / 1e6;
        _flip = !_flip;
        setState(() {});
      })
        ..start();
    } else if (!run && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _shader?.dispose();
    _shaderB?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.backdrop;
    final shader = _flip ? _shaderB : _shader;
    if (shader == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [b.colors[0], b.colors[1], b.colors[2]]),
        ),
      );
    }
    return CustomPaint(painter: _BackdropPainter(shader, b, widget.time ?? _t));
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.shader, this.b, this.t);
  final ui.FragmentShader shader;
  final TBackdrop b;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    var i = 0;
    void set(double v) => shader.setFloat(i++, v);
    set(size.width);
    set(size.height);
    set(t);
    set(b.style.index.toDouble());
    for (final c in b.colors.take(4)) {
      set(c.r);
      set(c.g);
      set(c.b);
    }
    set(b.grain);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => true;
}

// -- canvas ---------------------------------------------------------------------------

/// Draws [backdrop] + [elements] at the design size, scaled into its parent.
///
/// The editor passes [selected] / [onElement] for interaction; thumbnails
/// and the export leave them null.
class TemplateCanvas extends StatelessWidget {
  const TemplateCanvas({
    required this.backdrop,
    required this.elements,
    this.selected,
    this.animate = true,
    this.backdropTime,
    this.thumbnail = false,
    this.elementBuilder,
    super.key,
  });

  final TBackdrop backdrop;
  final List<TElement> elements;
  final TElement? selected;
  final bool animate;
  final double? backdropTime;

  /// Thumbnails skip loading photos / web fonts at full quality.
  final bool thumbnail;

  /// Wraps each element (the editor adds gestures and the selection box).
  final Widget Function(TElement element, Widget child)? elementBuilder;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(
          size: templateSize,
          child: ClipRect(
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: TemplateBackdrop(backdrop: backdrop, animate: animate, time: backdropTime)),
              for (final e in elements) _place(e, elementBuilder?.call(e, TemplateElement(e, thumbnail: thumbnail)) ??
                  TemplateElement(e, thumbnail: thumbnail)),
            ]),
          ),
        ),
      );

  Widget _place(TElement e, Widget child) {
    if (e.isText) {
      // Text sizes itself; centre it on e.center within its wrap width.
      return Positioned(
        left: e.center.dx - e.size.width / 2,
        top: e.center.dy - 200,
        width: e.size.width,
        height: 400,
        child: Center(child: Transform.rotate(angle: e.rotation, child: child)),
      );
    }
    return Positioned(
      left: e.center.dx - e.size.width / 2,
      top: e.center.dy - e.size.height / 2,
      width: e.size.width,
      height: e.size.height,
      child: Transform.rotate(angle: e.rotation, child: child),
    );
  }
}

/// One element, drawn at its design size.
class TemplateElement extends StatelessWidget {
  const TemplateElement(this.e, {this.thumbnail = false, super.key});
  final TElement e;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) => switch (e.kind) {
        ElementKind.slot => _Slot(e, thumbnail: thumbnail),
        ElementKind.text => TemplateText(e),
        ElementKind.deco => CustomPaint(painter: _DecoPainter(e), size: e.size),
      };
}

// -- photo slots ----------------------------------------------------------------------

class _Slot extends StatelessWidget {
  const _Slot(this.e, {required this.thumbnail});
  final TElement e;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final polaroid = e.shape == SlotShape.polaroid;
    Widget photo = e.photo == null ? _placeholder() : _image();
    photo = ClipPath(clipper: _SlotClipper(polaroid ? SlotShape.rect : e.shape, e.radius), child: photo);
    if (polaroid) {
      // White card with a deeper bottom margin, like an instant photo.
      photo = Container(
        padding: EdgeInsets.fromLTRB(e.size.width * .06, e.size.width * .06, e.size.width * .06, e.size.width * .2),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFBF7),
          borderRadius: BorderRadius.circular(2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: photo,
      );
    } else if (e.borderWidth > 0 || e.shadow) {
      photo = CustomPaint(
        foregroundPainter: e.borderWidth > 0 ? _SlotBorder(e) : null,
        child: e.shadow
            ? DecoratedBox(
                decoration: BoxDecoration(
                  shape: e.shape == SlotShape.circle ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: e.shape == SlotShape.circle ? null : BorderRadius.circular(e.radius),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: photo,
              )
            : photo,
      );
    }
    return photo;
  }

  Widget _image() => LayoutBuilder(builder: (_, box) {
        final img = Image.file(
          File(e.photo!),
          fit: BoxFit.cover,
          width: box.maxWidth,
          height: box.maxHeight,
          cacheWidth: thumbnail ? 240 : 1440,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
        return PhlioLook(
          look: e.look,
          child: ClipRect(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translate(e.photoOffset.dx, e.photoOffset.dy)
                ..scale(e.photoScale),
              child: img,
            ),
          ),
        );
      });

  Widget _placeholder() => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x668D78FF), Color(0x55E795D7)]),
        ),
        child: LayoutBuilder(
          builder: (_, box) => box.maxWidth < 70
              ? const Center(child: Icon(Icons.add_a_photo_outlined, color: Colors.white70, size: 18))
              : Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_a_photo_outlined, color: Colors.white, size: math.min(34, box.maxWidth * .22)),
                    if (box.maxHeight > 90) ...[
                      const SizedBox(height: 6),
                      Text(e.hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
        ),
      );
}

/// Clip path for a slot shape.
Path slotPath(SlotShape shape, double radius, Size size) {
  final r = Offset.zero & size;
  return switch (shape) {
    SlotShape.circle => Path()..addOval(r),
    SlotShape.rounded => Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius))),
    SlotShape.arch => Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.width / 2)
      ..arcToPoint(Offset(size.width, size.width / 2), radius: Radius.circular(size.width / 2))
      ..lineTo(size.width, size.height)
      ..close(),
    _ => Path()..addRect(r),
  };
}

class _SlotClipper extends CustomClipper<Path> {
  _SlotClipper(this.shape, this.radius);
  final SlotShape shape;
  final double radius;
  @override
  Path getClip(Size size) => slotPath(shape, radius, size);
  @override
  bool shouldReclip(_SlotClipper old) => old.shape != shape || old.radius != radius;
}

class _SlotBorder extends CustomPainter {
  _SlotBorder(this.e);
  final TElement e;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        slotPath(e.shape, e.radius, size),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.borderWidth
          ..color = e.border);
  }

  @override
  bool shouldRepaint(_SlotBorder old) => true;
}

// -- text -----------------------------------------------------------------------------

/// A font by name: bundled families directly, the rest via Google Fonts.
TextStyle templateFont(String family, TextStyle base) {
  if (family == 'Manrope' || family == 'Quicksand') return base.copyWith(fontFamily: family);
  try {
    return GoogleFonts.getFont(family, textStyle: base);
  } catch (_) {
    return base; // unknown name or offline before first download
  }
}

/// Text element with its background style.
class TemplateText extends StatelessWidget {
  const TemplateText(this.e, {super.key});
  final TElement e;

  @override
  Widget build(BuildContext context) {
    final base = templateFont(
      e.font,
      TextStyle(
        color: e.color,
        fontSize: e.fontSize,
        fontWeight: e.weight,
        fontStyle: e.italic ? FontStyle.italic : FontStyle.normal,
        letterSpacing: e.spacing,
        height: e.lineHeight,
      ),
    );
    final text = e.display.isEmpty ? ' ' : e.display;
    Widget plain(TextStyle s) => Text(text, textAlign: e.align, style: s);
    switch (e.bg) {
      case TextBg.none:
        return plain(base.copyWith(shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6)]));
      case TextBg.pill:
        return Container(
          padding: EdgeInsets.symmetric(horizontal: e.fontSize * .7, vertical: e.fontSize * .32),
          decoration: BoxDecoration(color: e.bgColor, borderRadius: BorderRadius.circular(e.fontSize * 2)),
          child: plain(base),
        );
      case TextBg.block:
        return Container(
          padding: EdgeInsets.symmetric(horizontal: e.fontSize * .5, vertical: e.fontSize * .25),
          color: e.bgColor,
          child: plain(base),
        );
      case TextBg.highlight:
        // Instagram-style: each line gets its own background.
        return plain(base.copyWith(
            background: Paint()
              ..color = e.bgColor
              ..style = PaintingStyle.fill
              ..strokeWidth = e.fontSize * .5
              ..strokeJoin = StrokeJoin.round));
      case TextBg.outline:
        return Stack(alignment: Alignment.center, children: [
          plain(base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(2, e.fontSize * .12)
                ..strokeJoin = StrokeJoin.round
                ..color = e.bgColor)),
          plain(base),
        ]);
      case TextBg.neon:
        return plain(base.copyWith(shadows: [
          Shadow(color: e.color, blurRadius: e.fontSize * .3),
          Shadow(color: e.bgColor, blurRadius: e.fontSize * .8),
          Shadow(color: e.bgColor.withValues(alpha: .8), blurRadius: e.fontSize * 1.6),
        ]));
      case TextBg.gradient:
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) =>
              LinearGradient(colors: [e.color, e.bgColor]).createShader(r),
          child: plain(base.copyWith(color: Colors.white)),
        );
      case TextBg.sticker:
        return Container(
          padding: EdgeInsets.symmetric(horizontal: e.fontSize * .6, vertical: e.fontSize * .35),
          decoration: BoxDecoration(
            color: e.bgColor,
            borderRadius: BorderRadius.circular(e.fontSize * .45),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (e.role != TextRole.text) ...[
              Icon(_roleIcon(e.role), size: e.fontSize * 1.05, color: e.color),
              SizedBox(width: e.fontSize * .25),
            ],
            Flexible(child: plain(base)),
          ]),
        );
    }
  }

  static IconData _roleIcon(TextRole r) => switch (r) {
        TextRole.location => Icons.place_rounded,
        TextRole.link => Icons.link_rounded,
        TextRole.tag => Icons.tag_rounded,
        TextRole.mention => Icons.alternate_email_rounded,
        TextRole.text => Icons.text_fields_rounded,
      };
}

// -- decorations ------------------------------------------------------------------------

class _DecoPainter extends CustomPainter {
  _DecoPainter(this.e);
  final TElement e;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = e.color;
    final r = Offset.zero & size;
    switch (e.deco) {
      case DecoKind.rect:
        if (e.color2.a > 0) {
          p.shader = LinearGradient(colors: [e.color, e.color2]).createShader(r);
        }
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(e.radius)), p);
      case DecoKind.line:
        canvas.drawRect(r, p);
      case DecoKind.circle:
        canvas.drawOval(r, p);
      case DecoKind.tape:
        // Semi-transparent washi tape with torn ends.
        final path = Path()..moveTo(0, 0);
        for (var y = 0.0; y <= size.height; y += size.height / 6) {
          path.lineTo((y / size.height * 6).round().isEven ? 0 : 3, y);
        }
        path.lineTo(size.width, size.height);
        for (var y = size.height; y >= 0; y -= size.height / 6) {
          path.lineTo(size.width - ((y / size.height * 6).round().isEven ? 0 : 3), y);
        }
        path.close();
        canvas.drawPath(path, p..color = e.color.withValues(alpha: e.color.a * .85));
      case DecoKind.sprockets:
        // Film strip: dark band with sprocket holes down both edges.
        canvas.drawRect(r, p);
        final hole = Paint()..color = e.color2.a > 0 ? e.color2 : Colors.white.withValues(alpha: .85);
        final w = size.width * .045, h = w * 1.4, gap = h * 1.2;
        for (var y = gap / 2; y < size.height - h; y += h + gap) {
          for (final x in [size.width * .03, size.width * .97 - w]) {
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(w * .25)), hole);
          }
        }
      case DecoKind.rating:
        // A rating bar: track, filled part and a knob.
        final track = RRect.fromRectAndRadius(r, Radius.circular(size.height / 2));
        canvas.drawRRect(track, Paint()..color = e.color2.a > 0 ? e.color2 : Colors.white24);
        final fill = Rect.fromLTWH(0, 0, size.width * e.value.clamp(0, 1), size.height);
        canvas.drawRRect(RRect.fromRectAndRadius(fill, Radius.circular(size.height / 2)),
            Paint()..shader = LinearGradient(colors: [e.color, e.color.withValues(alpha: .7)]).createShader(r));
        canvas.drawCircle(Offset(fill.right, size.height / 2), size.height * .9, Paint()..color = Colors.white);
      case DecoKind.recDot:
        canvas.drawCircle(size.center(Offset.zero), size.shortestSide / 2, p);
    }
  }

  @override
  bool shouldRepaint(_DecoPainter old) => true;
}
