import 'dart:async';
import 'package:flutter/material.dart';

/// Double-tap the sides of the picture; leave the centre play control alone.
class VideoSeekGesture extends StatefulWidget {
  const VideoSeekGesture(
      {required this.child,
      required this.onSeek,
      this.enabled = true,
      super.key});
  final Widget child;
  final ValueChanged<Duration> onSeek;
  final bool enabled;
  @override
  State<VideoSeekGesture> createState() => _VideoSeekGestureState();
}

class _VideoSeekGestureState extends State<VideoSeekGesture> {
  Timer? timer;
  int direction = 0;
  double tapX = 0;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: widget.enabled
              ? (details) => tapX = details.localPosition.dx
              : null,
          onDoubleTap: widget.enabled
              ? () {
                  final centre = bounds.maxWidth / 2;
                  if ((tapX - centre).abs() < 28) return;
                  final step = tapX < centre ? -1 : 1;
                  widget.onSeek(Duration(seconds: step * 10));
                  timer?.cancel();
                  setState(() => direction = step);
                  timer = Timer(const Duration(milliseconds: 650), () {
                    if (mounted) setState(() => direction = 0);
                  });
                }
              : null,
          child: Stack(fit: StackFit.expand, children: [
            widget.child,
            if (direction != 0)
              IgnorePointer(
                  child: Align(
                alignment: Alignment(direction * .65, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        direction < 0
                            ? Icons.replay_10_rounded
                            : Icons.forward_10_rounded,
                        color: Colors.white,
                        size: 32),
                    const Text('10 seconds',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
                ),
              )),
          ]),
        );
      });
}
