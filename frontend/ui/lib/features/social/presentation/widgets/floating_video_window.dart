// The floating ("picture-in-picture") player, YouTube / Twitch style.
//
// When a video is minimised it keeps playing in a small 16:9 window above
// every screen while the viewer keeps browsing:
//
//  * drag it anywhere; on release it glides to the nearest corner;
//  * fling it off the left/right edge to close it;
//  * pinch to resize (between 160 px and most of the screen width);
//  * tap to show controls (play/pause, ±10 s, expand, close) for 3 s;
//  * double-tap to expand back to the full player.
//
// A thin progress bar runs along the bottom. Position and size survive
// rebuilds (they live in this State, which stays mounted while floating).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../../design_system/colors.dart';
import '../controllers/video_playback_controller.dart';

class FloatingVideoWindow extends StatefulWidget {
  const FloatingVideoWindow({
    super.key,
    required this.controller,
    required this.picture,
    required this.bounds,
    required this.onExpand,
  });

  /// Shared playback controller (the same player keeps playing).
  final VideoPlaybackController controller;

  /// The video surface.
  final Widget picture;

  /// The area the window may move in (the whole app overlay).
  final BoxConstraints bounds;

  /// Returns to the full player.
  final VoidCallback onExpand;

  @override
  State<FloatingVideoWindow> createState() => _FloatingVideoWindowState();
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _FloatingVideoWindowState extends State<FloatingVideoWindow> with SingleTickerProviderStateMixin {
  static const _margin = 12.0;
  static const _minWidth = 160.0;

  _Corner corner = _Corner.bottomRight;
  double width = 220;
  Offset? dragPosition; // top-left while the finger is down
  double _scaleStartWidth = 220;
  bool controls = false;
  Timer? _hideControls;
  late final AnimationController _settle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Offset? _from;

  @override
  void dispose() {
    _hideControls?.cancel();
    _settle.dispose();
    super.dispose();
  }

  double get _maxWidth => math.max(_minWidth, widget.bounds.maxWidth - 2 * _margin);
  double get _height => width * 9 / 16;

  EdgeInsets get _safe => MediaQuery.paddingOf(context);

  Offset _cornerOffset(_Corner c) {
    final b = widget.bounds;
    // Keep clear of the status bar and the bottom navigation bar.
    final top = _safe.top + _margin;
    final bottom = b.maxHeight - _height - _safe.bottom - 96;
    final left = _margin;
    final right = b.maxWidth - width - _margin;
    return switch (c) {
      _Corner.topLeft => Offset(left, top),
      _Corner.topRight => Offset(right, top),
      _Corner.bottomLeft => Offset(left, math.max(top, bottom)),
      _Corner.bottomRight => Offset(right, math.max(top, bottom)),
    };
  }

  _Corner _nearest(Offset topLeft) {
    final centre = topLeft + Offset(width / 2, _height / 2);
    final rightSide = centre.dx > widget.bounds.maxWidth / 2;
    final lowerHalf = centre.dy > widget.bounds.maxHeight / 2;
    return lowerHalf
        ? (rightSide ? _Corner.bottomRight : _Corner.bottomLeft)
        : (rightSide ? _Corner.topRight : _Corner.topLeft);
  }

  void _showControls() {
    setState(() => controls = true);
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => controls = false);
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _settle.stop();
    _scaleStartWidth = width;
    dragPosition = _currentOffset();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      if (d.pointerCount > 1) {
        width = (_scaleStartWidth * d.scale).clamp(_minWidth, _maxWidth);
      }
      dragPosition = (dragPosition ?? _currentOffset()) + d.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final at = dragPosition ?? _currentOffset();
    final vx = d.velocity.pixelsPerSecond.dx;
    final offLeft = at.dx < -width * 0.35 || (vx < -1400 && at.dx < widget.bounds.maxWidth / 3);
    final offRight = at.dx + width > widget.bounds.maxWidth + width * 0.35 ||
        (vx > 1400 && at.dx + width > widget.bounds.maxWidth * 2 / 3);
    if (offLeft || offRight) {
      // Flung away: close, like YouTube's swipe-to-dismiss.
      HapticFeedback.lightImpact();
      widget.controller.close();
      return;
    }
    // Glide to the nearest corner (velocity nudges the choice).
    final projected = at + d.velocity.pixelsPerSecond * 0.12;
    _from = at;
    setState(() {
      corner = _nearest(projected);
      dragPosition = null;
    });
    _settle.forward(from: 0);
  }

  Offset _currentOffset() {
    final target = _cornerOffset(corner);
    final from = _from;
    if (dragPosition != null) return dragPosition!;
    if (from == null || !_settle.isAnimating) return target;
    return Offset.lerp(from, target, Curves.easeOutCubic.transform(_settle.value))!;
  }

  @override
  Widget build(BuildContext context) {
    width = width.clamp(_minWidth, _maxWidth);
    final c = widget.controller;
    final p = c.player;
    return AnimatedBuilder(
      animation: _settle,
      builder: (context, _) {
        final at = _currentOffset();
        return Stack(children: [
          Positioned(
            left: at.dx,
            top: at.dy,
            width: width,
            height: _height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showControls,
              onDoubleTap: widget.onExpand,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: Material(
                color: Colors.black,
                elevation: 18,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Stack(fit: StackFit.expand, children: [
                  IgnorePointer(child: widget.picture),
                  if (p != null && p.value.isInitialized)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 3,
                      child: VideoProgressIndicator(p,
                          allowScrubbing: false,
                          padding: EdgeInsets.zero,
                          colors: const VideoProgressColors(
                              playedColor: PhlioColors.brandPink, backgroundColor: Colors.white24)),
                    ),
                  AnimatedOpacity(
                    opacity: controls ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: IgnorePointer(
                      ignoring: !controls,
                      child: _Controls(controller: c, onExpand: widget.onExpand, onTouched: _showControls),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onExpand, required this.onTouched});

  final VideoPlaybackController controller;
  final VoidCallback onExpand;
  final VoidCallback onTouched;

  @override
  Widget build(BuildContext context) {
    final p = controller.player;
    final playing = p?.value.isPlaying ?? false;
    Widget icon(IconData data, String tip, VoidCallback onTap, {double size = 22}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: size,
          color: Colors.white,
          onPressed: () {
            onTouched();
            onTap();
          },
          icon: Icon(data),
        );
    Future<void> skip(int seconds) async {
      final player = p;
      if (player == null) return;
      await controller.seek(player.value.position + Duration(seconds: seconds));
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black45),
      child: Stack(children: [
        Positioned(top: 0, left: 0, child: icon(Icons.open_in_full_rounded, 'Expand player', onExpand, size: 18)),
        Positioned(top: 0, right: 0, child: icon(Icons.close_rounded, 'Close player', controller.close, size: 20)),
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            icon(Icons.replay_10_rounded, 'Back 10 seconds', () => skip(-10)),
            icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, playing ? 'Pause' : 'Play',
                controller.toggle, size: 34),
            icon(Icons.forward_10_rounded, 'Forward 10 seconds', () => skip(10)),
          ]),
        ),
      ]),
    );
  }
}
