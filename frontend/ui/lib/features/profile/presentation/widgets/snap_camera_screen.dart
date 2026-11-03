// Snap camera: a square, rounded preview with flash, flip and audience.
//
//   * Tap the shutter for a photo; hold it to record a video (up to 15 s).
//     Holding first sends a Phlio gradient streak once round the photo
//     slot's border, then the video starts rolling and the gradient ring
//     fills round the border as the progress. Let go before the streak
//     finishes and nothing is recorded.
//   * Swipe left or right on the preview to change the filter: colour
//     looks (Clarendon, Vintage…) and live effects (Pixelate, Fish eye,
//     Drift, Glitch, VHS…). The name flashes up as you swipe.
//
// The filter isn't baked into the file: snaps carry it as data ("look" or
// "look+effect") and are drawn with the same GPU shader everywhere, so
// photos and videos get the same filter and animated effects keep moving.

import 'snap_audience.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/colors.dart';
import '../../../../shared/media/phlio_look_data.dart';
import '../../../../shared/media/phlio_look_view.dart';

/// A snap filter: what it's called, the colour look and the effect.
typedef SnapFilter = ({String name, String look, String effect});

/// The filters the snap camera swipes through, in order.
const List<SnapFilter> snapFilters = [
  (name: 'Normal', look: 'normal', effect: 'none'),
  (name: 'Clarendon', look: 'clarendon', effect: 'none'),
  (name: 'Juno', look: 'juno', effect: 'none'),
  (name: 'Vintage', look: 'vintage', effect: 'none'),
  (name: 'Pixelate', look: 'normal', effect: 'pixelate'),
  (name: 'Fish eye', look: 'normal', effect: 'fisheye'),
  (name: 'Drift', look: 'normal', effect: 'drift'),
  (name: 'Lark', look: 'lark', effect: 'none'),
  (name: 'Valencia', look: 'valencia', effect: 'none'),
  (name: 'Glitch', look: 'normal', effect: 'glitch'),
  (name: 'VHS', look: 'normal', effect: 'vhs'),
  (name: 'Dreamy', look: 'normal', effect: 'dreamy'),
  (name: 'Old film', look: 'normal', effect: 'film'),
  (name: 'Prism', look: 'normal', effect: 'prism'),
  (name: 'Light leak', look: 'rise', effect: 'light_leak'),
  (name: 'Lo-Fi', look: 'lofi', effect: 'none'),
  (name: 'Moon', look: 'moon', effect: 'none'),
  (name: 'Inkwell', look: 'inkwell', effect: 'none'),
  (name: 'Phlio', look: 'phlio', effect: 'none'),
];

/// What the camera returns: the file, whether it's a video, the audience
/// and the filter ("look" or "look+effect").
typedef SnapCapture = ({XFile photo, SnapAudience audience, bool video, String filter});

/// Longest snap video.
const snapVideoLimit = Duration(seconds: 15);

/// Returns a [SnapCapture], true for "your snaps", or null on close.
class SnapCameraScreen extends StatefulWidget {
  const SnapCameraScreen({super.key, this.audience = const SnapAudience(), this.title = 'New snap'});
  final SnapAudience audience;
  final String title;
  @override
  State<SnapCameraScreen> createState() => _SnapCameraState();
}

class _SnapCameraState extends State<SnapCameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  late SnapAudience audience = widget.audience;
  CameraController? controller;
  List<CameraDescription> cameras = [];
  int lens = 0, generation = 0;
  bool starting = false, taking = false, active = true;
  FlashMode flash = FlashMode.off;
  String? error;
  Future<void> pendingRelease = Future<void>.value();

  // Filters.
  int filterIndex = 0;
  bool showFilterName = false;
  Timer? _nameTimer;
  double _dragDx = 0;
  SnapFilter get filter => snapFilters[filterIndex];

  // Video recording: [recording] drives the gradient border's progress.
  late final AnimationController recording = AnimationController(vsync: this, duration: snapVideoLimit)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) stopRecording();
    });
  bool get isRecording => recording.isAnimating;

  /// The gradient streak that runs round the border before recording.
  late final AnimationController arming = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        arming.reset();
        startRecording();
      }
    });
  bool get isArming => arming.isAnimating;
  bool _holding = false;

  /// Hold started: run the streak, then record.
  void armRecording() {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized || starting || taking || isRecording) return;
    HapticFeedback.selectionClick();
    _holding = true;
    arming.forward(from: 0);
    setState(() {});
  }

  /// Hold ended: cancel the streak, or stop the video.
  void releaseShutter() {
    _holding = false;
    if (isArming) {
      arming.reset();
      setState(() {});
      return;
    }
    stopRecording();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  /// Swipe left = next filter, right = previous (wraps around).
  void stepFilter(int by) {
    HapticFeedback.selectionClick();
    _nameTimer?.cancel();
    setState(() {
      filterIndex = (filterIndex + by) % snapFilters.length;
      showFilterName = true;
    });
    _nameTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => showFilterName = false);
    });
  }

  Future<void> release() async {
    generation++;
    final previous = controller;
    controller = null;
    pendingRelease = previous?.dispose() ?? pendingRelease;
    await pendingRelease;
  }

  Future<void> start() async {
    final token = ++generation;
    setState(() {
      starting = true;
      error = null;
    });
    try {
      await pendingRelease;
      if (cameras.isEmpty) {
        cameras = await availableCameras();
        final front = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
        lens = front < 0 ? 0 : front;
      }
      if (!mounted || token != generation || !active) return;
      if (cameras.isEmpty) throw StateError('No camera');
      // Audio on, for snap videos.
      final camera = CameraController(cameras[lens], ResolutionPreset.high, enableAudio: true);
      controller = camera;
      await camera.initialize();
      if (!mounted || token != generation || !active) return;
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await camera.setFlashMode(FlashMode.off);
      flash = FlashMode.off;
    } catch (_) {
      if (mounted && token == generation) {
        error = 'Camera unavailable. Allow camera and microphone access in phone settings, then retry.';
      }
    } finally {
      if (mounted && token == generation) setState(() => starting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) {
      if (isRecording) recording.stop();
      unawaited(release());
    } else {
      start();
    }
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    arming.dispose();
    recording.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(release());
    super.dispose();
  }

  Future<void> flip() async {
    if (starting || taking || isRecording || cameras.length < 2) return;
    setState(() => starting = true);
    await release();
    if (!mounted || !active) return;
    lens = (lens + 1) % cameras.length;
    await start();
  }

  Future<void> toggleFlash() async {
    final camera = controller;
    if (camera == null || starting || taking) return;
    final next = flash == FlashMode.off ? FlashMode.always : FlashMode.off;
    try {
      await camera.setFlashMode(next);
      if (mounted) setState(() => flash = next);
    } catch (_) {
      _say('Flash is unavailable for this camera.');
    }
  }

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _done(XFile file, {required bool video}) {
    if (mounted && active) {
      Navigator.pop<SnapCapture>(context,
          (photo: file, audience: audience, video: video, filter: joinMomentFilter(filter.look, filter.effect)));
    }
  }

  Future<void> capture() async {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized || starting || taking || isRecording) return;
    setState(() => taking = true);
    try {
      _done(await camera.takePicture(), video: false);
    } catch (_) {
      _say('Could not capture. Please try again.');
    } finally {
      if (mounted) setState(() => taking = false);
    }
  }

  Future<void> startRecording() async {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized || starting || taking || isRecording) return;
    try {
      await camera.startVideoRecording();
      HapticFeedback.mediumImpact();
      recording.forward(from: 0);
      if (mounted) setState(() {});
      // Let go while the camera was starting: stop straight away.
      if (!_holding) await stopRecording();
    } catch (_) {
      _say('Could not start recording. Allow microphone access and try again.');
    }
  }

  Future<void> stopRecording() async {
    final camera = controller;
    if (camera == null || !camera.value.isRecordingVideo || taking) return;
    final length = recording.value * snapVideoLimit.inMilliseconds;
    recording.stop();
    setState(() => taking = true);
    try {
      final file = await camera.stopVideoRecording();
      if (length < 600) {
        _say('Hold a little longer to record a video.');
      } else {
        _done(file, video: true);
      }
    } catch (_) {
      _say('Could not save the video. Try again.');
    } finally {
      recording.reset();
      if (mounted) setState(() => taking = false);
    }
  }

  // -- UI -------------------------------------------------------------------------------

  Widget _preview(CameraController camera) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _dragDx = 0,
        onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (_dragDx < -40 || v < -300) {
            stepFilter(1);
          } else if (_dragDx > 40 || v > 300) {
            stepFilter(-1);
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          LayoutBuilder(
            builder: (_, box) => ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: box.maxWidth,
                    height: box.maxWidth * camera.value.aspectRatio,
                    child: PhlioLook(look: filter.look, effect: filter.effect, child: CameraPreview(camera)),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: showFilterName ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Center(
                child: Text(filter.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 12)])),
              ),
            ),
          ),
          if (isRecording)
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: recording,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        '● 0:${(recording.value * snapVideoLimit.inSeconds).floor().toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    final ready = camera?.value.isInitialized == true && !starting && error == null;
    return PopScope(
      canPop: !taking && !isRecording,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            tooltip: 'Close camera',
            onPressed: taking || isRecording ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.title),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Your snaps',
              onPressed: taking || isRecording ? null : () => Navigator.pop(context, true),
              icon: const Icon(Icons.grid_view_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: AnimatedBuilder(
                            animation: Listenable.merge([recording, arming]),
                            // Streak round the border while arming, then the
                            // Phlio gradient border = recording progress.
                            builder: (_, child) => CustomPaint(
                              foregroundPainter: isRecording
                                  ? _RecordingBorder(recording.value, 72)
                                  : isArming
                                      ? _ArmingBorder(arming.value, 72)
                                      : null,
                              child: child,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(72),
                              child: ColoredBox(
                                color: const Color(0xff191919),
                                child: ready
                                    ? _preview(camera!)
                                    : Center(
                                        child: error == null
                                            ? const CircularProgressIndicator()
                                            : Padding(
                                                padding: const EdgeInsets.all(24),
                                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                                  Text(error!, textAlign: TextAlign.center),
                                                  TextButton(
                                                    onPressed: () async {
                                                      await release();
                                                      if (mounted) start();
                                                    },
                                                    child: const Text('Retry camera'),
                                                  ),
                                                ]),
                                              ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton.filledTonal(
                            tooltip: flash == FlashMode.off ? 'Enable flash' : 'Disable flash',
                            onPressed: ready && !taking && !isRecording ? toggleFlash : null,
                            icon: Icon(flash == FlashMode.off ? Icons.flash_off : Icons.flash_on),
                          ),
                          Semantics(
                            label: 'Tap for a photo, hold for a video',
                            button: true,
                            child: GestureDetector(
                              onTap: ready && !taking ? capture : null,
                              onLongPressStart: ready && !taking ? (_) => armRecording() : null,
                              onLongPressEnd: (_) => releaseShutter(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: isRecording ? 100 : 88,
                                height: isRecording ? 100 : 88,
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  gradient: isRecording ? PhlioColors.brandGradient : null,
                                  color: isRecording ? null : const Color(0xff292b30),
                                  shape: BoxShape.circle,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: EdgeInsets.all(isRecording ? 18 : 0),
                                  decoration: BoxDecoration(
                                    color: isRecording ? PhlioColors.danger : (ready ? Colors.white : Colors.grey),
                                    shape: isRecording ? BoxShape.rectangle : BoxShape.circle,
                                    borderRadius: isRecording ? BorderRadius.circular(8) : null,
                                  ),
                                  child: taking
                                      ? const Padding(
                                          padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2))
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Flip camera',
                            onPressed: ready && !taking && !isRecording && cameras.length > 1 ? flip : null,
                            icon: const Icon(Icons.flip_camera_ios_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      ActionChip(
                          avatar: const Icon(Icons.people_alt_outlined, size: 18),
                          label: Text(audience.label),
                          onPressed: isRecording
                              ? null
                              : () async {
                                  final value = await pickSnapAudience(context, audience);
                                  if (mounted && value != null) setState(() => audience = value);
                                }),
                      const Text(
                        'Tap for a photo · hold for a video · swipe for filters',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The recording ring: a Phlio-gradient stroke that runs clockwise round
/// the preview's rounded border as the video fills up.
class _RecordingBorder extends CustomPainter {
  _RecordingBorder(this.progress, this.radius);
  final double progress, radius;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final gradient = SweepGradient(
      transform: const GradientRotation(-math.pi / 2),
      colors: const [PhlioColors.brandViolet, PhlioColors.brandPink, PhlioColors.brandPeach, PhlioColors.brandViolet],
    ).createShader(rect);
    // Faint full track, then the gradient progress on top.
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white24);
    final metric = path.computeMetrics().first;
    // Start at the top centre: the path starts at the top-left corner's end.
    final total = metric.length;
    final startAt = rect.width / 2 - radius;
    final end = progress * total;
    final draw = Path();
    if (startAt + end <= total) {
      draw.addPath(metric.extractPath(startAt, startAt + end), Offset.zero);
    } else {
      draw
        ..addPath(metric.extractPath(startAt, total), Offset.zero)
        ..addPath(metric.extractPath(0, startAt + end - total), Offset.zero);
    }
    canvas.drawPath(
        draw,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = gradient);
  }

  @override
  bool shouldRepaint(_RecordingBorder old) => old.progress != progress;
}


/// Before recording: a Phlio gradient streak travels once round the photo
/// slot's border (clockwise from the top), fading in a full ring at the end.
class _ArmingBorder extends CustomPainter {
  _ArmingBorder(this.t, this.radius);
  final double t, radius;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final metric = path.computeMetrics().first;
    final total = metric.length;
    final start = rect.width / 2 - radius; // top centre
    final head = start + Curves.easeInOut.transform(t) * total;
    final tail = head - total * .28;
    final shader = SweepGradient(
      transform: GradientRotation(-math.pi / 2 + t * math.pi * 2),
      colors: const [PhlioColors.brandViolet, PhlioColors.brandPink, PhlioColors.brandPeach, PhlioColors.brandViolet],
    ).createShader(rect);
    Path piece(double a, double b) {
      final out = Path();
      double wrap(double v) => ((v % total) + total) % total;
      final from = wrap(a), to = wrap(b);
      if (from <= to) {
        out.addPath(metric.extractPath(from, to), Offset.zero);
      } else {
        out
          ..addPath(metric.extractPath(from, total), Offset.zero)
          ..addPath(metric.extractPath(0, to), Offset.zero);
      }
      return out;
    }

    canvas.drawPath(
        piece(tail, head),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3));
    // The ring fills in as the streak finishes its lap.
    if (t > .7) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..shader = shader
            ..color = Colors.white.withValues(alpha: ((t - .7) / .3).clamp(0.0, 1.0)));
    }
  }

  @override
  bool shouldRepaint(_ArmingBorder old) => old.t != t;
}
