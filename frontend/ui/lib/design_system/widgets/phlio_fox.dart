// Phlio design system — the fox mascot.
//
// The reference screens use a friendly red-panda/fox character throughout
// onboarding and the Phlio Agent. The primary rendering is a real asset —
// Twemoji's fox illustration (`assets/agent/fox.svg`, CC-BY 4.0, see that
// directory's README for attribution) via `flutter_svg`.
//
// [PhlioFox] still carries a hand-drawn `CustomPainter` fallback
// (`_PhlioFoxPainter`, below) used automatically if the SVG asset ever
// fails to load — e.g. a build that stripped assets, or a platform quirk
// rendering this particular SVG. A mascot that silently disappears reads
// as broken; a mascot that gracefully degrades to a simpler on-brand
// illustration does not. `pose` only affects the fallback illustration
// (the SVG has one pose) — see `PhlioFoxPose` for what each value draws.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../colors.dart';

enum PhlioFoxPose { idle, waving, thinking }

class PhlioFox extends StatelessWidget {
  const PhlioFox({super.key, this.size = 96, this.pose = PhlioFoxPose.idle});

  final double size;
  final PhlioFoxPose pose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/agent/fox.svg',
        width: size,
        height: size,
        placeholderBuilder: (context) => CustomPaint(painter: _PhlioFoxPainter(pose: pose)),
        errorBuilder: (context, error, stackTrace) => CustomPaint(painter: _PhlioFoxPainter(pose: pose)),
      ),
    );
  }
}

class _PhlioFoxPainter extends CustomPainter {
  _PhlioFoxPainter({required this.pose});

  final PhlioFoxPose pose;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h * 0.56);
    final headRadius = w * 0.36;

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [PhlioColors.brandOrange, PhlioColors.brandPink],
      ).createShader(Rect.fromCircle(center: center, radius: headRadius));

    // Ears — two rounded triangles behind the head.
    final earPaint = Paint()..color = PhlioColors.brandOrange;
    _drawEar(canvas, center, headRadius, earPaint, tiltLeft: true);
    _drawEar(canvas, center, headRadius, earPaint, tiltLeft: false);

    // Head.
    canvas.drawCircle(center, headRadius, bodyPaint);

    // Muzzle patch.
    final muzzlePaint = Paint()..color = Colors.white.withOpacity(0.95);
    final muzzleCenter = Offset(center.dx, center.dy + headRadius * 0.28);
    canvas.drawOval(
      Rect.fromCenter(center: muzzleCenter, width: headRadius * 1.15, height: headRadius * 0.85),
      muzzlePaint,
    );

    // Eyes.
    final eyePaint = Paint()..color = const Color(0xFF241522);
    final eyeOffsetX = headRadius * 0.32;
    final eyeY = center.dy - headRadius * 0.05;
    final eyeRadius = headRadius * (pose == PhlioFoxPose.thinking ? 0.05 : 0.075);
    canvas.drawCircle(Offset(center.dx - eyeOffsetX, eyeY), eyeRadius, eyePaint);
    canvas.drawCircle(Offset(center.dx + eyeOffsetX, eyeY), eyeRadius, eyePaint);

    // Nose.
    final nosePaint = Paint()..color = const Color(0xFF241522);
    final noseCenter = Offset(center.dx, muzzleCenter.dy - headRadius * 0.08);
    canvas.drawCircle(noseCenter, headRadius * 0.09, nosePaint);

    // Cheeks (a small warmth touch — two soft pink circles).
    final cheekPaint = Paint()..color = PhlioColors.brandPink.withOpacity(0.35);
    canvas.drawCircle(Offset(center.dx - headRadius * 0.62, center.dy + headRadius * 0.15),
        headRadius * 0.14, cheekPaint);
    canvas.drawCircle(Offset(center.dx + headRadius * 0.62, center.dy + headRadius * 0.15),
        headRadius * 0.14, cheekPaint);

    if (pose == PhlioFoxPose.waving) {
      final pawPaint = Paint()..color = PhlioColors.brandOrange;
      final pawCenter = Offset(center.dx + headRadius * 1.15, center.dy - headRadius * 0.65);
      canvas.drawCircle(pawCenter, headRadius * 0.28, pawPaint);
      final tipPaint = Paint()..color = Colors.white.withOpacity(0.9);
      canvas.drawCircle(pawCenter, headRadius * 0.12, tipPaint);
    }
  }

  void _drawEar(Canvas canvas, Offset center, double headRadius, Paint paint, {required bool tiltLeft}) {
    final direction = tiltLeft ? -1 : 1;
    final earBase = Offset(center.dx + direction * headRadius * 0.55, center.dy - headRadius * 0.65);
    final path = Path()
      ..moveTo(earBase.dx - headRadius * 0.28, earBase.dy + headRadius * 0.25)
      ..lineTo(earBase.dx + direction * headRadius * 0.18, earBase.dy - headRadius * 0.55)
      ..lineTo(earBase.dx + headRadius * 0.28, earBase.dy + headRadius * 0.25)
      ..close();
    canvas.drawPath(path, paint);

    final innerPaint = Paint()..color = Colors.white.withOpacity(0.85);
    final innerPath = Path()
      ..moveTo(earBase.dx - headRadius * 0.14, earBase.dy + headRadius * 0.16)
      ..lineTo(earBase.dx + direction * headRadius * 0.1, earBase.dy - headRadius * 0.28)
      ..lineTo(earBase.dx + headRadius * 0.14, earBase.dy + headRadius * 0.16)
      ..close();
    canvas.drawPath(innerPath, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _PhlioFoxPainter oldDelegate) => oldDelegate.pose != pose;
}
