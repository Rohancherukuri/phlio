// Full-screen doodle pad for Messages ("+" → Draw). Returns the path of a
// PNG in the temp directory, ready to stage as an image attachment.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> openDrawScreen(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<String>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const DrawScreen()));

class _Stroke {
  _Stroke(this.color, this.width);
  final Color color;
  final double width;
  final points = <Offset>[];
}

class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key});
  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  final _canvasKey = GlobalKey();
  final _strokes = <_Stroke>[];
  Color _color = Colors.white;
  double _width = 6;
  bool _saving = false;

  static const _palette = [
    Colors.white,
    Color(0xFFFF4F79),
    Color(0xFFFFB58F),
    Color(0xFFF6D365),
    Color(0xFF68D7CD),
    Color(0xFF72A7FF),
    Color(0xFF8D78FF),
    Colors.black,
  ];

  Future<void> _done() async {
    if (_strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(
          pixelRatio: MediaQuery.devicePixelRatioOf(context));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      if (mounted) Navigator.pop(context, file.path);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save the drawing.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF111317),
        appBar: AppBar(
          backgroundColor: const Color(0xFF111317),
          leading: IconButton(
              tooltip: 'Discard',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Draw'),
          actions: [
            IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo_rounded),
                onPressed: _strokes.isEmpty
                    ? null
                    : () => setState(() => _strokes.removeLast())),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                  onPressed: _saving ? null : _done,
                  child: Text(_saving ? 'Saving…' : 'Done')),
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                onPanStart: (d) => setState(() =>
                    _strokes.add(_Stroke(_color, _width)..points.add(d.localPosition))),
                onPanUpdate: (d) =>
                    setState(() => _strokes.last.points.add(d.localPosition)),
                child: CustomPaint(
                  painter: _DrawPainter(_strokes),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.line_weight_rounded,
                      size: 20, color: Colors.white70),
                  Expanded(
                    child: Slider(
                        min: 2,
                        max: 24,
                        value: _width,
                        onChanged: (v) => setState(() => _width = v)),
                  ),
                ]),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final color in _palette)
                      GestureDetector(
                        onTap: () => setState(() => _color = color),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _color == color
                                    ? Colors.white
                                    : Colors.white24,
                                width: _color == color ? 3 : 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ]),
            ),
          ),
        ]),
      );
}

class _DrawPainter extends CustomPainter {
  _DrawPainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF111317));
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2,
            paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter oldDelegate) => true;
}
