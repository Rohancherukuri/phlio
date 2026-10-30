import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// One album per consecutive group; documents and voice messages keep order.
class DmMediaAlbum extends StatelessWidget {
  const DmMediaAlbum(
      {super.key, required this.attachments, required this.tileBuilder});
  final List<Map<String, dynamic>> attachments;
  final Widget Function(Map<String, dynamic>, double?) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var group = <Map<String, dynamic>>[];
    void flush() {
      if (group.isEmpty) return;
      final items = List<Map<String, dynamic>>.of(group);
      group = [];
      if (items.length == 1) {
        children.add(tileBuilder(items.first, null));
        return;
      }
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: LayoutBuilder(builder: (context, constraints) {
            final width =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0;
            final side = (width - 3) / 2;
            return _AlbumSheen(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < items.length; i += 2)
                Padding(
                  padding:
                      EdgeInsets.only(bottom: i + 2 < items.length ? 3 : 0),
                  child: Row(children: [
                    Expanded(child: tileBuilder(items[i], side)),
                    if (i + 1 < items.length) ...[
                      const SizedBox(width: 3),
                      Expanded(child: tileBuilder(items[i + 1], side)),
                    ],
                  ]),
                ),
            ]));
          }),
        ),
      ));
    }

    for (final attachment in attachments) {
      if (['image', 'video', 'gif'].contains(attachment['kind'])) {
        group.add(attachment);
      } else {
        flush();
        children.add(tileBuilder(attachment, null));
      }
    }
    flush();
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _AlbumSheen extends StatefulWidget {
  const _AlbumSheen({required this.child});
  final Widget child;
  @override
  State<_AlbumSheen> createState() => _AlbumSheenState();
}

class _AlbumSheenState extends State<_AlbumSheen>
    with SingleTickerProviderStateMixin {
  static final _program =
      ui.FragmentProgram.fromAsset('assets/shaders/dm_album_sheen.frag');
  late final AnimationController _animation;
  ui.FragmentShader? _shader;
  @override
  void initState() {
    super.initState();
    // Create the ticker while this element is active, even if shader loading fails.
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _load();
  }

  Future<void> _load() async {
    try {
      final program = await _program;
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      if (!MediaQuery.disableAnimationsOf(context)) _animation.forward();
    } catch (_) {
      // Media remains usable on renderers without fragment shader support.
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_shader != null && !MediaQuery.disableAnimationsOf(context))
          Positioned.fill(
              child: IgnorePointer(
                  child: AnimatedBuilder(
            animation: _animation,
            builder: (_, __) =>
                CustomPaint(painter: _SheenPainter(_shader!, _animation.value)),
          ))),
      ]);
}

class _SheenPainter extends CustomPainter {
  _SheenPainter(this.shader, this.progress);
  final ui.FragmentShader shader;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, progress);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.progress != progress;
}
