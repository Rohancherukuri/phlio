// Moment drawing — Draw in the composer: pen, arrow, marker, neon and
// eraser; a size slider on the left; colours along the bottom (three
// pages). Strokes are stored as a `drawing` sticker (normalised points), so
// photos flatten them and videos replay them as an overlay.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const drawTools = ['pen', 'arrow', 'marker', 'neon', 'eraser'];
const _toolIcons = {
  'pen': Icons.edit_rounded,
  'arrow': Icons.north_east_rounded,
  'marker': Icons.border_color_rounded,
  'neon': Icons.auto_awesome_rounded,
  'eraser': Icons.cleaning_services_rounded,
};

const drawPalettes = <List<Color>>[
  [Colors.white, Colors.black, Color(0xFF2196F3), Color(0xFF43C54A), Color(0xFFFBC02D), Color(0xFFFF8F00), Color(0xFFF5435B), Color(0xFFE91E63), Color(0xFF9C27B0)],
  [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F), Color(0xFF68D7CD), Color(0xFF72A7FF), Color(0xFFF6B93B), Color(0xFFF5636B), Color(0xFF7BD88F), Color(0xFFC8A2FF)],
  [Color(0xFF3E2723), Color(0xFF795548), Color(0xFFBCAAA4), Color(0xFF607D8B), Color(0xFF9E9E9E), Color(0xFF263238), Color(0xFF004D40), Color(0xFF1A237E), Color(0xFF880E4F)],
];

class DrawStroke {
  DrawStroke(this.tool, this.color, this.width, [List<Offset>? points]) : points = points ?? [];
  final String tool;
  final Color color;
  final double width; // as a fraction of the canvas width
  final List<Offset> points; // 0..1 of the canvas

  Map<String, dynamic> toJson() => {
        't': tool,
        'c': '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        'w': double.parse(width.toStringAsFixed(4)),
        // Every point, rounded to keep the overlay small.
        'p': [for (final p in points) [double.parse(p.dx.toStringAsFixed(3)), double.parse(p.dy.toStringAsFixed(3))]],
      };

  static DrawStroke? fromJson(dynamic j) {
    if (j is! Map) return null;
    final c = int.tryParse('${j['c']}'.replaceFirst('#', ''), radix: 16) ?? 0xFFFFFF;
    return DrawStroke(
      '${j['t'] ?? 'pen'}',
      Color(0xFF000000 | c),
      (j['w'] as num? ?? .012).toDouble(),
      [for (final p in (j['p'] as List? ?? const [])) if (p is List && p.length == 2) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
    );
  }
}

List<DrawStroke> strokesFrom(dynamic list) =>
    [for (final s in (list is List ? list : const [])) DrawStroke.fromJson(s)].whereType<DrawStroke>().toList();

class DrawingPainter extends CustomPainter {
  DrawingPainter(this.strokes);
  final List<DrawStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final w = s.width * size.width;
      final pts = [for (final p in s.points) Offset(p.dx * size.width, p.dy * size.height)];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final mid = Offset((pts[i - 1].dx + pts[i].dx) / 2, (pts[i - 1].dy + pts[i].dy) / 2);
        path.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
      }
      if (pts.length > 1) path.lineTo(pts.last.dx, pts.last.dy);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w
        ..color = s.color;
      switch (s.tool) {
        case 'eraser':
          paint
            ..blendMode = BlendMode.clear
            ..strokeWidth = w * 2.2;
          canvas.drawPath(path, paint);
        case 'marker':
          paint
            ..strokeCap = StrokeCap.square
            ..strokeWidth = w * 2.4
            ..color = s.color.withValues(alpha: .45);
          canvas.drawPath(path, paint);
        case 'neon':
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = w * 2.2
                ..color = s.color
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
          canvas.drawPath(path, paint..color = Colors.white..strokeWidth = w * .7);
        case 'arrow':
          canvas.drawPath(path, paint);
          if (pts.length > 1) {
            final end = pts.last;
            final from = pts[math.max(0, pts.length - 6)];
            final a = math.atan2(end.dy - from.dy, end.dx - from.dx);
            final head = w * 4;
            final arrow = Path()
              ..moveTo(end.dx - head * math.cos(a - .5), end.dy - head * math.sin(a - .5))
              ..lineTo(end.dx, end.dy)
              ..lineTo(end.dx - head * math.cos(a + .5), end.dy - head * math.sin(a + .5));
            canvas.drawPath(arrow, paint);
          }
        default:
          canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DrawingPainter old) => true;
}

/// A drawing as a sticker: a 360×640 box (the composer scales stickers by
/// canvas width / 360, so it covers the 9:16 canvas exactly).
class DrawingSticker extends StatelessWidget {
  const DrawingSticker(this.data, {super.key});
  final Map data;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: SizedBox(width: 360, height: 640, child: CustomPaint(painter: DrawingPainter(strokesFrom(data['strokes'])))),
      );
}

/// The drawing mode over the canvas. [strokes] is edited in place;
/// [onDone] closes it.
class DrawOverlay extends StatefulWidget {
  const DrawOverlay({required this.strokes, required this.onChanged, required this.onDone, super.key});
  final List<DrawStroke> strokes;
  final VoidCallback onChanged, onDone;

  @override
  State<DrawOverlay> createState() => _DrawOverlayState();
}

class _DrawOverlayState extends State<DrawOverlay> {
  String _tool = 'pen';
  Color _color = Colors.white;
  double _size = .5; // 0..1 → stroke width
  int _page = 0;
  final _pages = PageController();

  double get _width => .004 + _size * .03;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return Stack(children: [
        // Draw surface.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              widget.strokes.add(DrawStroke(_tool, _color, _width, [
                Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height),
              ]));
              setState(() {});
            },
            onPanUpdate: (d) {
              widget.strokes.last.points.add(Offset(
                (d.localPosition.dx / size.width).clamp(0.0, 1.0),
                (d.localPosition.dy / size.height).clamp(0.0, 1.0),
              ));
              setState(() {});
            },
            onPanEnd: (_) => widget.onChanged(),
            child: CustomPaint(painter: DrawingPainter(widget.strokes)),
          ),
        ),
        // Tools + Done.
        Positioned(
          top: 10,
          left: 0,
          right: 8,
          child: Row(children: [
            const Spacer(),
            IconButton(
              tooltip: 'Undo',
              onPressed: widget.strokes.isEmpty
                  ? null
                  : () {
                      setState(() => widget.strokes.removeLast());
                      widget.onChanged();
                    },
              icon: const Icon(Icons.undo_rounded, color: Colors.white),
            ),
            for (final t in drawTools)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tool = t);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _tool == t ? Colors.white : Colors.black38,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(_toolIcons[t], size: 19, color: _tool == t ? Colors.black : Colors.white),
                ),
              ),
            TextButton(
              onPressed: widget.onDone,
              child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        // Size slider (tapered, left).
        Positioned(
          left: 10,
          top: size.height * .22,
          height: size.height * .42,
          width: 36,
          child: GestureDetector(
            onVerticalDragUpdate: (d) => setState(() => _size = (_size - d.delta.dy / (size.height * .42)).clamp(0.0, 1.0)),
            child: CustomPaint(painter: _TaperPainter(_size)),
          ),
        ),
        // Colours.
        if (_tool != 'eraser')
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            height: 62,
            child: Column(children: [
              SizedBox(
                height: 46,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: drawPalettes.length,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (_, p) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    for (final c in drawPalettes[p])
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: _color == c ? 34 : 28,
                          height: _color == c ? 34 : 28,
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                        ),
                      ),
                  ]),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < drawPalettes.length; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? Colors.white : Colors.white38),
                  ),
              ]),
            ]),
          ),
      ]);
    });
  }
}

class _TaperPainter extends CustomPainter {
  _TaperPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .1, 0)
      ..lineTo(size.width * .9, 0)
      ..lineTo(size.width * .55, size.height)
      ..lineTo(size.width * .45, size.height)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [Colors.white.withValues(alpha: .85), Colors.white.withValues(alpha: .25)]));
    final y = size.height * (1 - value);
    canvas.drawCircle(Offset(size.width / 2, y), 13, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(size.width / 2, y),
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black26);
  }

  @override
  bool shouldRepaint(_TaperPainter old) => old.value != value;
}
