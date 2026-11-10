// Foxy (Agent) quick actions — the bottom-nav "+" while the Agent platform
// is open. It blooms into a wheel of options:
//
//   Foxy Lens (camera) · Voice · Maps
//
// Options fly out of the + along an arc, and fly back into it on close.
//
// Foxy Lens is a Google-Lens-style camera: point, pick what you want
// (Ask / Shop / Translate / Places), shoot, and the photo goes to Foxy with
// that question. Voice records a voice message for Foxy.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';
import '../controllers/agent_controller.dart';
import '../screens/foxy_maps_screen.dart';

/// True while a capture from the wheel is uploading / waiting for Foxy.
final agentBusyProvider = StateProvider<bool>((ref) => false);

enum _WheelAction { lens, voice, maps }

/// Opens the wheel above the bottom-nav "+" and runs what was picked.
Future<void> showAgentWheel(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  HapticFeedback.mediumImpact();
  final action = await showGeneralDialog<_WheelAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 620),
    pageBuilder: (context, animation, _) => _Wheel(animation: animation),
  );
  if (action == null || !context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  switch (action) {
    case _WheelAction.maps:
      await navigator.push(MaterialPageRoute(builder: (_) => const FoxyMapsScreen()));
    case _WheelAction.lens:
      final result = await navigator.push<_LensResult>(
        PageRouteBuilder(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, __, ___) => const FoxyLensScreen(),
          transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
          ),
        ),
      );
      if (result == null || !context.mounted) return;
      await _send(container, context, [result.path], result.prompt);
    case _WheelAction.voice:
      final path = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _VoiceSheet(),
      );
      if (path == null || !context.mounted) return;
      await _send(container, context, [path], '');
  }
}

Future<void> _send(ProviderContainer container, BuildContext context, List<String> paths, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final busy = container.read(agentBusyProvider.notifier);
  busy.state = true;
  try {
    final controller = container.read(agentControllerProvider.notifier);
    final uploaded = await controller.uploadFiles(paths);
    final files = uploaded.valueOrNull;
    if (files == null) {
      uploaded.when(
        success: (_) {},
        failure: (f) => messenger?.showSnackBar(SnackBar(content: Text(f.message))),
      );
      return;
    }
    final sent = await controller.sendMessage(text, attachments: files);
    sent.when(success: (_) {}, failure: (f) => messenger?.showSnackBar(SnackBar(content: Text(f.message))));
  } finally {
    busy.state = false;
  }
}

// ---------------------------------------------------------------------------
// The wheel

class _Wheel extends StatelessWidget {
  const _Wheel({required this.animation});

  final Animation<double> animation;

  static const _items = [
    (_WheelAction.lens, Icons.center_focus_strong_rounded, 'Foxy Lens', [Color(0xFF8D78FF), Color(0xFF72A7FF)]),
    (_WheelAction.voice, Icons.mic_rounded, 'Voice', [Color(0xFFE795D7), Color(0xFFFFB58F)]),
    (_WheelAction.maps, Icons.map_rounded, 'Maps', [Color(0xFF6FD6B5), Color(0xFF72A7FF)]),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Exactly over the bottom nav's centre button (64 px bar above the
    // safe area; 48 px round button in its middle).
    final center = Offset(size.width / 2, size.height - bottom - 32);
    const radius = 118.0;
    // Where each option settles on the upper arc, left to right.
    const angles = [212.0, 270.0, 328.0];

    // No Material ancestor in a general dialog — provide one so text
    // doesn't get the debug underline.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final a = animation.value.clamp(0.0, 1.0);
          final closing = animation.status == AnimationStatus.reverse;
          final fade = Curves.easeOut.transform(a);
          // The "pull" of the black hole: strongest mid-flight.
          final pull = math.sin(math.pi * a);
          return Stack(children: [
            // Blur + dim the app behind.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10 * fade, sigmaY: 10 * fade),
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.5 * fade)),
                ),
              ),
            ),
            // The vortex swirling around the + while things fly in/out,
            // and the arc track once the wheel has formed.
            Positioned(
              left: center.dx - radius - 60,
              top: center.dy - radius - 60,
              width: 2 * (radius + 60),
              height: 2 * (radius + 60),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _VortexPainter(
                    pull: pull,
                    spin: a,
                    arc: Curves.easeOutCubic.transform(((a - 0.55) / 0.45).clamp(0.0, 1.0)),
                    radius: radius,
                  ),
                ),
              ),
            ),
            for (var i = 0; i < _items.length; i++)
              () {
                final (action, icon, label, colors) = _items[i];
                // Each option's own progress: out = staggered and
                // springy; in = all together, accelerating into the hole.
                final t = closing
                    ? Curves.easeInCubic.transform(a)
                    : Interval(i * 0.1, 0.7 + i * 0.1, curve: Curves.easeOutBack).transform(a);
                final tc = t.clamp(0.0, 1.0);
                // Spiral: swirl round the + as the distance changes —
                // flung out on the way out, sucked in on the way back.
                const swirl = 1.6 * math.pi;
                final angle = angles[i] * math.pi / 180 - (1 - tc) * swirl;
                final r = radius * t;
                final pos = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
                // Shrinks to nothing at the event horizon.
                final scale = 0.08 + 0.92 * Curves.easeOut.transform(tc);
                // Squash along the path near the hole (spaghettification).
                final stretch = 1 + 0.35 * (1 - tc) * pull;
                return Positioned(
                  left: pos.dx - 36,
                  top: pos.dy - 31,
                  child: Opacity(
                    opacity: (tc / 0.1).clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: angle + math.pi / 2,
                      child: Transform.scale(
                        scaleX: scale / stretch,
                        scaleY: scale * stretch,
                        child: Transform.rotate(
                          angle: -(angle + math.pi / 2),
                          child: _WheelOption(
                            icon: icon,
                            label: label,
                            colors: colors,
                            spin: (1 - tc) * -2.4,
                            labelOpacity: Curves.easeOut.transform(((tc - 0.75) / 0.25).clamp(0.0, 1.0)),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context, action);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }(),
            // The + itself: same round button as the nav, its glyph
            // turning into × (one and a quarter turns).
            Positioned(
              left: center.dx - 24,
              top: center.dy - 24,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Transform.scale(
                  scale: 1 - 0.08 * pull,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: PhlioColors.sunsetGradient,
                    ),
                    child: Transform.rotate(
                      angle: Curves.easeInOutCubic.transform(a) * math.pi * 1.25,
                      child: const Icon(Icons.add_rounded, color: PhlioColors.textOnBrand, size: 26),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: center.dy - radius - 96,
              child: Opacity(
                opacity: Curves.easeOut.transform(((a - 0.5) / 0.5).clamp(0.0, 1.0)),
                child: Text('What should Foxy do?',
                    textAlign: TextAlign.center,
                    style: PhlioTypography.title.copyWith(color: Colors.white)),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// A faint swirl around the + (the black hole) while options are flung out
/// or pulled in, then the thin arc the wheel sits on.
class _VortexPainter extends CustomPainter {
  _VortexPainter({required this.pull, required this.spin, required this.arc, required this.radius});

  final double pull;
  final double spin;
  final double arc;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (pull > 0.02) {
      for (var k = 0; k < 3; k++) {
        final r = 30.0 + k * 16;
        final start = spin * math.pi * (3 - k) + k;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          start,
          math.pi * 1.1,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.22 * pull * (1 - k / 3)),
        );
      }
    }
    if (arc > 0) {
      final sweep = math.pi * 0.72 * arc;
      final startAngle = math.pi * 1.5 - sweep / 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius),
        startAngle,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.18 * arc),
      );
    }
  }

  @override
  bool shouldRepaint(_VortexPainter old) => true;
}

class _WheelOption extends StatelessWidget {
  const _WheelOption({
    required this.icon,
    required this.label,
    required this.colors,
    required this.spin,
    required this.onTap,
    this.labelOpacity = 1,
  });

  final IconData icon;
  final String label;
  final List<Color> colors;
  final double spin;
  final VoidCallback onTap;
  final double labelOpacity;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        height: 92,
        child: Column(children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
            ),
            child: Transform.rotate(angle: spin, child: Icon(icon, color: Colors.white, size: 28)),
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: labelOpacity,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: PhlioTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Foxy Lens

class _LensResult {
  const _LensResult(this.path, this.prompt);
  final String path;
  final String prompt;
}

enum _LensMode {
  ask('Ask', Icons.auto_awesome_rounded, 'What is this? Tell me about it.'),
  shop('Shop', Icons.shopping_bag_outlined, 'Find this, or something similar, that I can buy on Phlio Shop.'),
  translate('Translate', Icons.translate_rounded, 'Read the text in this photo and translate it to English.'),
  places('Places', Icons.place_outlined, 'Where is this, and what can I book or do nearby?');

  const _LensMode(this.label, this.icon, this.prompt);
  final String label;
  final IconData icon;
  final String prompt;
}

class FoxyLensScreen extends StatefulWidget {
  const FoxyLensScreen({super.key});

  @override
  State<FoxyLensScreen> createState() => _FoxyLensScreenState();
}

class _FoxyLensScreenState extends State<FoxyLensScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _lens = 0;
  bool _starting = true;
  String? _error;
  FlashMode _flash = FlashMode.off;
  _LensMode _mode = _LensMode.ask;
  String? _shot; // captured photo path (frozen while Foxy "looks")
  late final AnimationController _scan =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  late final AnimationController _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _scan.dispose();
    _snap.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _camera == null && _shot == null) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _lens = back < 0 ? 0 : back;
      }
      if (_cameras.isEmpty) throw StateError('No camera');
      final camera = CameraController(_cameras[_lens], ResolutionPreset.high, enableAudio: false);
      await camera.initialize();
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await camera.setFlashMode(_flash);
      if (!mounted) {
        await camera.dispose();
        return;
      }
      final old = _camera;
      setState(() => _camera = camera);
      await old?.dispose();
    } catch (_) {
      if (mounted) setState(() => _error = 'Camera unavailable. Allow camera access in phone settings, then try again.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    _lens = (_lens + 1) % _cameras.length;
    final old = _camera;
    setState(() => _camera = null);
    await old?.dispose();
    await _start();
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _camera?.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {}
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || camera.value.isTakingPicture || _shot != null) return;
    HapticFeedback.mediumImpact();
    try {
      final file = await camera.takePicture();
      await _finish(file.path);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t take the photo.')));
    }
  }

  Future<void> _gallery() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 2560);
    if (x != null) await _finish(x.path);
  }

  Future<void> _finish(String path) async {
    setState(() => _shot = path);
    await _snap.forward(from: 0);
    if (mounted) Navigator.pop(context, _LensResult(path, _mode.prompt));
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // Preview (cover) or the frozen shot.
        if (_shot != null)
          Image.file(File(_shot!), fit: BoxFit.cover)
        else if (camera != null && camera.value.isInitialized)
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: camera.value.previewSize?.height ?? 1080,
                height: camera.value.previewSize?.width ?? 1920,
                child: CameraPreview(camera),
              ),
            ),
          )
        else
          Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: PhlioTypography.body.copyWith(color: Colors.white)),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _start, child: const Text('Try again')),
                    ]),
                  )
                : _starting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const SizedBox(),
          ),
        // Lens frame + scan sweep.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: Listenable.merge([_scan, _snap]),
            builder: (context, _) => CustomPaint(
              painter: _LensPainter(scan: _scan.value, snap: _snap.value, looking: _shot != null),
            ),
          ),
        ),
        // Top bar: close top-left, flash top-right (pinned to the top —
        // the expand-fit Stack would otherwise centre it vertically).
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              _RoundIcon(icon: Icons.close_rounded, onTap: () => Navigator.pop(context)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ShaderMask(
                    shaderCallback: (r) => PhlioColors.brandGradient.createShader(r),
                    child: const Icon(Icons.center_focus_strong_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 6),
                  Text('Foxy Lens', style: PhlioTypography.bodyStrong.copyWith(color: Colors.white)),
                ]),
              ),
              const Spacer(),
              _RoundIcon(
                icon: _flash == FlashMode.off ? Icons.flash_off_rounded : Icons.flash_on_rounded,
                onTap: _toggleFlash,
              ),
            ]),
          ),
          ),
        ),
        if (_shot != null)
          Align(
            alignment: const Alignment(0, 0.35),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 8),
                Text('Foxy is looking…', style: PhlioTypography.bodyStrong.copyWith(color: Colors.white)),
              ]),
            ),
          ),
        // Bottom: modes + shutter.
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final m in _LensMode.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _mode = m);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: m == _mode ? Colors.white : Colors.black45,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(children: [
                                Icon(m.icon, size: 16, color: m == _mode ? Colors.black : Colors.white),
                                const SizedBox(width: 6),
                                Text(m.label,
                                    style: PhlioTypography.bodyStrong.copyWith(
                                        color: m == _mode ? Colors.black : Colors.white, fontSize: 14)),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _RoundIcon(icon: Icons.photo_library_outlined, onTap: _gallery, size: 48),
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 78,
                      height: 78,
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: PhlioColors.brandGradient),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 3),
                        ),
                        child: Icon(_mode.icon, color: Colors.black87, size: 28),
                      ),
                    ),
                  ),
                  _RoundIcon(icon: Icons.cameraswitch_rounded, onTap: _flip, size: 48),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.size = 42});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, color: Colors.white, size: size * 0.5)),
        ),
      );
}

/// Lens-style corner brackets that breathe, a gradient scan line sweeping
/// down, and (after the shot) brackets snapping in with a shimmer.
class _LensPainter extends CustomPainter {
  _LensPainter({required this.scan, required this.snap, required this.looking});

  final double scan;
  final double snap;
  final bool looking;

  @override
  void paint(Canvas canvas, Size size) {
    final breathe = 0.5 + 0.5 * math.sin(2 * math.pi * scan);
    final side = size.width * (0.72 - 0.03 * breathe - 0.12 * Curves.easeOutBack.transform(snap.clamp(0.0, 1.0)));
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.44), width: side, height: side * 1.1);
    const len = 34.0;
    const r = 18.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    void corner(Offset o, double sx, double sy) {
      final p = Path()
        ..moveTo(o.dx, o.dy + sy * len)
        ..lineTo(o.dx, o.dy + sy * r)
        ..arcToPoint(Offset(o.dx + sx * r, o.dy), radius: const Radius.circular(r), clockwise: sx * sy > 0)
        ..lineTo(o.dx + sx * len, o.dy);
      canvas.drawPath(p, paint);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);

    // Scan line sweeping through the frame.
    final y = rect.top + rect.height * (looking ? (snap * 2 % 1) : Curves.easeInOut.transform(scan));
    final line = Rect.fromLTWH(rect.left + 8, y - 30, rect.width - 16, 30);
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, PhlioColors.brandViolet.withValues(alpha: 0.35)],
        ).createShader(line),
    );
    canvas.drawLine(
      Offset(rect.left + 8, y),
      Offset(rect.right - 8, y),
      Paint()
        ..strokeWidth = 2
        ..shader = const LinearGradient(colors: [Color(0x008D78FF), Color(0xFFE795D7), Color(0x00FFB58F)])
            .createShader(Rect.fromLTWH(rect.left, y - 1, rect.width, 2)),
    );
    // Sparkle dots while looking.
    if (looking) {
      final rnd = math.Random(7);
      for (var i = 0; i < 14; i++) {
        final p = Offset(rect.left + rnd.nextDouble() * rect.width, rect.top + rnd.nextDouble() * rect.height);
        final tw = (math.sin(2 * math.pi * (snap * 2 + i / 14)) + 1) / 2;
        canvas.drawCircle(p, 2 + 2.5 * tw, Paint()..color = Colors.white.withValues(alpha: 0.75 * tw));
      }
    }
  }

  @override
  bool shouldRepaint(_LensPainter old) => true;
}

// ---------------------------------------------------------------------------
// Voice message

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _recorder = AudioRecorder();
  final List<double> _levels = List.filled(36, 0.05, growable: true);
  StreamSubscription<Amplitude>? _amp;
  Timer? _timer;
  int _seconds = 0;
  String? _path;
  String? _error;
  bool _recording = false;

  static const _maxSeconds = 120;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _amp?.cancel();
    _timer?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _begin() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Allow microphone access to talk to Foxy.');
        return;
      }
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}${Platform.pathSeparator}foxy_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000), path: _path!);
      HapticFeedback.mediumImpact();
      _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
        // dBFS (-60..0) -> 0..1
        final v = ((a.current + 55) / 55).clamp(0.04, 1.0);
        if (!mounted) return;
        setState(() {
          _levels.add(v);
          if (_levels.length > 36) _levels.removeAt(0);
        });
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stop(send: true);
      });
      setState(() => _recording = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t start recording.');
    }
  }

  Future<void> _stop({required bool send}) async {
    _timer?.cancel();
    await _amp?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    if (!send) {
      if (path != null) File(path).delete().ignore();
      Navigator.pop(context);
      return;
    }
    if (_seconds < 1) {
      setState(() => _error = 'Hold on — say something first.');
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.pop(context, path ?? _path);
  }

  @override
  Widget build(BuildContext context) {
    final level = _levels.isEmpty ? 0.0 : _levels.last;
    final time = '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141A24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 6),
            FoxyPuppet(act: FoxyAct.happy, size: 120, talking: level > 0.35, entrance: true),
            Text(_error ?? (_recording ? 'Foxy is listening…' : 'Getting ready…'),
                style: PhlioTypography.title.copyWith(color: _error != null ? PhlioColors.danger : Colors.white)),
            const SizedBox(height: 4),
            Text(time, style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary, fontFeatures: const [ui.FontFeature.tabularFigures()])),
            const SizedBox(height: 14),
            // Live waveform.
            SizedBox(
              height: 56,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _levels.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: 4,
                    height: 6 + 50 * _levels[i],
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F)],
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _RoundIcon(icon: Icons.delete_outline_rounded, onTap: () => _stop(send: false), size: 52),
              GestureDetector(
                onTap: _recording ? () => _stop(send: true) : null,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  scale: 1 + 0.12 * level,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: PhlioColors.brandGradient,
                      boxShadow: [BoxShadow(color: PhlioColors.brandPink.withValues(alpha: 0.25 + 0.4 * level), blurRadius: 24, spreadRadius: 2)],
                    ),
                    child: const Icon(Icons.send_rounded, color: PhlioColors.textOnBrand, size: 25),
                  ),
                ),
              ),
              const SizedBox(width: 52),
            ]),
            const SizedBox(height: 6),
            Text('Tap send when you\'re done · up to 2 min',
                style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
          ]),
        ),
      ),
    );
  }
}
