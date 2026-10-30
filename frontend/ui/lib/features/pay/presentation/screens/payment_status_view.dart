import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Status is supplied by verification, never inferred from animation completion.
class PaymentStatusView extends StatefulWidget {
  const PaymentStatusView(
      {required this.status, this.amount, this.preview = false, super.key});
  final String status;
  final int? amount;
  final bool preview;
  @override
  State<PaymentStatusView> createState() => _PaymentStatusViewState();
}

class _PaymentStatusViewState extends State<PaymentStatusView>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850));
  void animate() {
    if (widget.status == 'processing' &&
        !MediaQuery.disableAnimationsOf(context)) {
      animation.repeat();
    } else {
      animation.stop();
      if (MediaQuery.disableAnimationsOf(context)) {
        animation.value = 1;
      } else {
        animation.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    animate();
  }

  @override
  void didUpdateWidget(covariant PaymentStatusView old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) animate();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final success = widget.status == 'success';
    final pending = widget.status == 'processing';
    final color = pending
        ? const Color(0xFF9575FF)
        : success
            ? const Color(0xFF46D99A)
            : const Color(0xFFFF7188);
    final label = pending
        ? 'Checking payment'
        : success
            ? 'Payment successful'
            : 'Payment failed';
    return Semantics(
        liveRegion: true,
        label: label,
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.preview)
                const Text('Animation preview · no payment made'),
              const SizedBox(height: 24),
              AnimatedBuilder(
                  animation: animation,
                  builder: (_, __) => CustomPaint(
                      size: const Size(120, 120),
                      painter: _StatusPainter(
                          widget.status, animation.value, color))),
              const SizedBox(height: 24),
              Text(label,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              if (widget.amount != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                        'INR ${(widget.amount! / 100).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 28))),
              const SizedBox(height: 12),
              Text(
                  pending
                      ? 'Waiting for confirmation. Check the status before starting another payment.'
                      : success
                          ? 'Confirmed by the payment provider.'
                          : 'The provider reported a failed payment.',
                  textAlign: TextAlign.center),
            ])));
  }
}

class _StatusPainter extends CustomPainter {
  _StatusPainter(this.status, this.progress, this.color);
  final String status;
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
        centre, 56, Paint()..color = color.withValues(alpha: .12));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    if (status == 'processing') {
      canvas.drawArc(Rect.fromCircle(center: centre, radius: 46),
          progress * math.pi * 2, math.pi * 1.4, false, paint);
      return;
    }
    canvas.drawCircle(centre, 46, paint..color = color.withValues(alpha: .3));
    final path = Path();
    if (status == 'success') {
      path.moveTo(35, 61);
      path.lineTo(52, 78);
      path.lineTo(85, 43);
    } else {
      path.moveTo(43, 43);
      path.lineTo(77, 77);
      path.moveTo(77, 43);
      path.lineTo(43, 77);
    }
    paint.color = color;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
          metric.extractPath(
              0, metric.length * Curves.easeOut.transform(progress)),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StatusPainter old) =>
      old.progress != progress || old.status != status;
}
