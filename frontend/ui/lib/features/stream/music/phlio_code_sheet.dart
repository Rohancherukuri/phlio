// Phlio Stream · Music — showing, sharing and scanning Phlio Codes.
//
// Every song has a code (song menu → Phlio Code, or the now-playing menu).
// The camera button in the music search bar opens the scanner: point it at
// a code on another phone or a screenshot, or pick a photo from the gallery.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'music_library.dart';
import 'music_models.dart';
import 'music_player.dart';
import 'music_ui.dart';
import 'now_playing.dart';
import 'open_music_api.dart';
import 'phlio_code.dart';

// -- showing a code ----------------------------------------------------------------------------

/// Bottom sheet with [t]'s Phlio Code on a card in its artwork colours.
Future<void> showPhlioCodeSheet(BuildContext context, Track t) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CodeSheet(track: t),
    );

/// The code card plus Scan and Share buttons.
class _CodeSheet extends ConsumerStatefulWidget {
  const _CodeSheet({required this.track});
  final Track track;
  @override
  ConsumerState<_CodeSheet> createState() => _CodeSheetState();
}

/// Renders the card to a PNG for sharing.
class _CodeSheetState extends ConsumerState<_CodeSheet> {
  final _card = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _card.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/phlio_code_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: '${widget.track.title} · ${widget.track.artist}: scan this Phlio Code in Phlio Stream',
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not share the code')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final code = PhlioCode.forTrack(t);
    final colors = ref.watch(artColorsProvider(artKey(t))).valueOrNull ?? ArtColors.phlio;
    final bg = colors.primary;
    final fg = colors.onPrimary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RepaintBoundary(
            key: _card,
            child: Container(
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Artwork(track: t, size: 64, radius: 12),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w900)),
                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: .75))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 22),
                if (code != null)
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PhlioCodeView(code: code, height: 60, color: fg, background: bg),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t.isDevice
                ? 'This song is a file on your phone, so its code opens it on this phone only.'
                : 'Scan it in Phlio Stream: Music → camera button in the search bar.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  openPhlioCodeScanner(context);
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Scan a code'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _sharing || code == null ? null : _share,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// -- resolving ----------------------------------------------------------------------------------

/// The track a scanned code points to (library, saved Audius tracks or the
/// Audius API), or null.
Future<Track?> resolvePhlioCode(WidgetRef ref, PhlioCode code) async {
  if (code.kind == PhlioCode.audius) {
    final id = code.audiusId!;
    final saved = ref.read(musicStoreProvider).remote['aud_$id'];
    if (saved != null) return saved;
    return ref.read(audiusProvider).track(id);
  }
  for (final t in ref.read(trackByIdProvider).values) {
    if (PhlioCode.hashId(t.id) == code.payload) return t;
  }
  return null;
}

// -- scanning -------------------------------------------------------------------------------------

/// Opens the full-screen code scanner.
Future<void> openPhlioCodeScanner(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PhlioCodeScanner()));

PhlioCode? _decodeInIsolate((Uint8List, int, int) a) {
  final (g, w, h) = a;
  return decodePhlioCode(g, w, h) ?? decodePhlioCode(_transpose(g, w, h), h, w);
}

Uint8List _transpose(Uint8List g, int w, int h) {
  final out = Uint8List(g.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[x * h + y] = g[y * w + x];
    }
  }
  return out;
}

/// Live camera scanner for Phlio Codes, with torch and scan-from-photo.
/// A match plays the song and opens Now playing.
class PhlioCodeScanner extends ConsumerStatefulWidget {
  const PhlioCodeScanner({super.key});
  @override
  ConsumerState<PhlioCodeScanner> createState() => _PhlioCodeScannerState();
}

/// Runs the camera image stream, decodes the guide-box region about six
/// times a second and pauses the camera when the app goes to the background.
class _PhlioCodeScannerState extends ConsumerState<PhlioCodeScanner> with WidgetsBindingObserver {
  CameraController? _cam;
  int _sensor = 90;
  String? _error;
  bool _busy = false, _found = false, _torch = false;
  DateTime _last = DateTime(0);
  PhlioCode? _candidate;
  Size _screen = Size.zero;
  String _status = 'Point your camera at a Phlio Code';

  // The on-screen guide box, as fractions of the screen width / height.
  static const _boxW = .86, _boxH = .30; // _boxH is a fraction of the screen width

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stop();
    } else if (state == AppLifecycleState.resumed && _cam == null && !_found) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      _sensor = back.sensorOrientation;
      final cam = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420);
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _error = null;
      });
      await cam.startImageStream(_onFrame);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable. Allow camera access, or scan a code from a photo.');
    }
  }

  Future<void> _stop() async {
    final cam = _cam;
    _cam = null;
    if (cam == null) return;
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
    } catch (_) {}
    await cam.dispose();
  }

  void _onFrame(CameraImage img) {
    if (_busy || _found) return;
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 160) return;
    _last = now;
    _busy = true;
    try {
      final (g, w, h) = _guideRegion(img);
      final code = decodePhlioCode(g, w, h);
      if (code != null) {
        // Two matching reads in a row: no lucky false positives.
        if (code == _candidate) {
          _onCode(code);
        } else {
          _candidate = code;
        }
      }
    } catch (_) {
      // A bad frame; keep going.
    } finally {
      _busy = false;
    }
  }

  /// Grey pixels under the guide box, upright, at most ~520 px wide.
  (Uint8List, int, int) _guideRegion(CameraImage img) {
    final plane = img.planes.first;
    final bytes = plane.bytes, bpr = plane.bytesPerRow;
    final bgra = img.format.group == ImageFormatGroup.bgra8888;
    final sw = img.width, sh = img.height;
    // Frames come in the sensor's orientation; turn landscape frames upright.
    final rot = sw > sh ? (_sensor == 270 ? 270 : 90) : 0;
    final pw = rot == 0 ? sw : sh, ph = rot == 0 ? sh : sw;
    // The preview fills the screen (cover), so part of the frame is hidden.
    final screen = _screen == Size.zero ? const Size(9, 19.5) : _screen;
    final camAspect = pw / ph, screenAspect = screen.width / screen.height;
    final visW = screenAspect < camAspect ? screenAspect / camAspect : 1.0;
    final visH = screenAspect < camAspect ? 1.0 : camAspect / screenAspect;
    final boxW = _boxW * visW * pw;
    final boxH = (_boxH * screen.width / screen.height) * visH * ph * 1.35;
    final x0 = (pw - boxW) / 2, y0 = (ph - boxH) / 2;
    final step = math.max(1.0, boxW / 520);
    final w = (boxW / step).floor(), h = (boxH / step).floor();
    final out = Uint8List(w * h);
    for (var j = 0; j < h; j++) {
      final py = (y0 + j * step).toInt().clamp(0, ph - 1);
      for (var i = 0; i < w; i++) {
        final px = (x0 + i * step).toInt().clamp(0, pw - 1);
        int x, y;
        switch (rot) {
          case 90:
            x = py;
            y = sh - 1 - px;
          case 270:
            x = sw - 1 - py;
            y = px;
          default:
            x = px;
            y = py;
        }
        if (bgra) {
          final o = y * bpr + x * 4;
          out[j * w + i] = (bytes[o] * 29 + bytes[o + 1] * 150 + bytes[o + 2] * 77) >> 8;
        } else {
          out[j * w + i] = bytes[y * bpr + x];
        }
      }
    }
    return (out, w, h);
  }

  Future<void> _onCode(PhlioCode code) async {
    if (_found) return;
    _found = true;
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _status = 'Found a code…');
    Track? track;
    try {
      track = await resolvePhlioCode(ref, code);
    } catch (_) {}
    if (!mounted) return;
    if (track == null) {
      setState(() {
        _status = code.kind == PhlioCode.device
            ? 'That song is a file on another phone.'
            : 'That code didn\'t match a song. Try again.';
        _found = false;
        _candidate = null;
      });
      return;
    }
    await _stop();
    if (!mounted) return;
    await ref.read(musicPlayerProvider).playTracks([track]);
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    unawaited(openNowPlaying(nav.context));
  }

  Future<void> _fromPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() => _status = 'Reading the photo…');
    try {
      final data = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(data, targetWidth: 760);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final w = img.width, h = img.height;
      final g = Uint8List(w * h);
      for (var i = 0, o = 0; i < g.length; i++, o += 4) {
        g[i] = (rgba[o] * 77 + rgba[o + 1] * 150 + rgba[o + 2] * 29) >> 8;
      }
      img.dispose();
      final code = await compute(_decodeInIsolate, (g, w, h));
      if (!mounted) return;
      if (code == null) {
        setState(() => _status = 'No Phlio Code in that photo.');
      } else {
        await _onCode(code);
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not read that photo.');
    }
  }

  Future<void> _toggleTorch() async {
    final cam = _cam;
    if (cam == null) return;
    try {
      await cam.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _screen = MediaQuery.sizeOf(context);
    final cam = _cam;
    final boxW = _screen.width * _boxW, boxH = _screen.width * _boxH;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          if (cam != null && cam.value.isInitialized)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  // previewSize is landscape; the preview is shown upright.
                  width: cam.value.previewSize?.height ?? 1,
                  height: cam.value.previewSize?.width ?? 1,
                  child: CameraPreview(cam),
                ),
              ),
            )
          else if (_error == null)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          // Dim everything but the guide box.
          IgnorePointer(child: CustomPaint(painter: _ScrimPainter(Size(boxW, boxH)))),
          Center(
            child: SizedBox(
              width: boxW,
              height: boxH,
              child: Stack(children: [
                const Positioned.fill(child: _ScanLine()),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: .9), width: 2.5),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          SafeArea(
            child: Column(children: [
              Row(children: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                ),
                const Expanded(
                  child: Text('Scan a Phlio Code',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                IconButton(
                  tooltip: _torch ? 'Torch off' : 'Torch on',
                  onPressed: cam == null ? null : _toggleTorch,
                  icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white),
                ),
              ]),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(_error ?? _status,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 28),
                child: Text('Line the bars up inside the box. Codes are under any song → Phlio Code.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), shape: const StadiumBorder()),
                onPressed: _fromPhoto,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Scan from a photo'),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Darkens the screen around the guide box.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.box);
  final Size box;
  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(Rect.fromCenter(center: size.center(Offset.zero), width: box.width, height: box.height),
        const Radius.circular(20));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .55));
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.box != box;
}

/// The glowing line sweeping up and down inside the guide box.
class _ScanLine extends StatefulWidget {
  const _ScanLine();
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

/// Drives the sweep animation.
class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Align(
          alignment: Alignment(0, -1 + 2 * Curves.easeInOut.transform(_c.value)),
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: const Color(0xFF7C5CFF).withValues(alpha: .8), blurRadius: 12)],
              gradient: const LinearGradient(colors: [Colors.transparent, Color(0xFFB9A8FF), Colors.transparent]),
            ),
          ),
        ),
      );
}
