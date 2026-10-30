// Phlio's custom glyphs that Material Icons doesn't have.
//
// [PhlioIcons.send] is the paper-plane "send" icon used everywhere a post,
// clip, video or message is sent or shared. It is a sentinel [IconData]:
// render it through [PhlioIcon] (a drop-in for [Icon]) or use
// [PhlioSendIcon] directly.

import 'package:flutter/material.dart';

abstract final class PhlioIcons {
  /// Paper-plane send/share. Never pass to a plain [Icon]; use [PhlioIcon].
  static const IconData send = IconData(0xF8FF, fontFamily: 'PhlioGlyphs');
}

/// Drop-in replacement for [Icon] that also draws Phlio's custom glyphs.
class PhlioIcon extends StatelessWidget {
  const PhlioIcon(this.icon, {super.key, this.size, this.color, this.shadows});
  final IconData? icon;
  final double? size;
  final Color? color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    if (icon != PhlioIcons.send) {
      return Icon(icon, size: size, color: color, shadows: shadows);
    }
    return PhlioSendIcon(size: size, color: color);
  }
}

/// Outlined paper plane pointing up-right (24-unit grid).
class PhlioSendIcon extends StatelessWidget {
  const PhlioSendIcon({super.key, this.size, this.color, this.strokeWidth});
  final double? size;
  final Color? color;

  /// In 24-unit grid space; defaults to 2 (a touch thinner when small).
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final paint = color ?? theme.color ?? Colors.white;
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _PlanePainter(paint, strokeWidth ?? (side < 20 ? 2.3 : 2)),
      ),
    );
  }
}

class _PlanePainter extends CustomPainter {
  _PlanePainter(this.color, this.stroke);
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final body = Path()
      ..moveTo(11.698 * s, 20.334 * s)
      ..lineTo(22 * s, 3.001 * s)
      ..lineTo(2 * s, 3.001 * s)
      ..lineTo(9.218 * s, 10.084 * s)
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawLine(Offset(22 * s, 3 * s), Offset(9.218 * s, 10.083 * s), paint);
  }

  @override
  bool shouldRepaint(covariant _PlanePainter old) =>
      old.color != color || old.stroke != stroke;
}
