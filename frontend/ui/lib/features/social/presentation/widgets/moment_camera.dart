// Full-screen camera for moments, laid out like Instagram's story camera:
// close · flash · settings on top; Create (Aa) · Boomerang · Effects and a
// chevron that expands to labelled tools on the left; gallery · shutter ·
// flip at the bottom, with a single "MOMENT" mode label underneath.
//
// Tap the shutter for a photo, hold it to record (up to 60s). Hands-free
// makes a tap start and a second tap stop recording.

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../design_system/colors.dart';

/// What the camera hands back to the composer.
class MomentCapture {
  const MomentCapture({this.path, this.video = false, this.create = false});
  final String? path;
  final bool video;

  /// "Create" (Aa): a text-only moment on a gradient background.
  final bool create;
}

Future<MomentCapture?> openMomentCamera(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<MomentCapture>(
        MaterialPageRoute(
            fullscreenDialog: true, builder: (_) => const MomentCameraScreen()));

class MomentCameraScreen extends StatefulWidget {
  const MomentCameraScreen({super.key});
  @override
  State<MomentCameraScreen> createState() => _MomentCameraScreenState();
}

class _MomentCameraScreenState extends State<MomentCameraScreen>
    with WidgetsBindingObserver {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  int lens = 0, generation = 0;
  bool starting = false, busy = false, active = true;
  bool expanded = false, handsFree = false, recording = false;
  FlashMode flash = FlashMode.off;
  String? error;
  Uint8List? galleryThumb;
  Timer? recordLimit;
  final recordWatch = Stopwatch();
  Future<void> pendingRelease = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
    _loadGalleryThumb();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    recordLimit?.cancel();
    unawaited(release());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) {
      unawaited(release());
    } else {
      start();
    }
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
        final back =
            cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        lens = back < 0 ? 0 : back;
      }
      if (!mounted || token != generation || !active) return;
      if (cameras.isEmpty) throw StateError('No camera');
      final camera = CameraController(cameras[lens], ResolutionPreset.high,
          enableAudio: true);
      controller = camera;
      await camera.initialize();
      if (!mounted || token != generation || !active) return;
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await camera.setFlashMode(flash);
    } catch (_) {
      if (mounted && token == generation) {
        error = 'Camera unavailable. Allow camera access in phone settings, '
            'then retry.';
      }
    } finally {
      if (mounted && token == generation) setState(() => starting = false);
    }
  }

  Future<void> _loadGalleryThumb() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) return;
      final albums = await PhotoManager.getAssetPathList(
          onlyAll: true, type: RequestType.common);
      if (albums.isEmpty) return;
      final latest = await albums.first.getAssetListRange(start: 0, end: 1);
      if (latest.isEmpty) return;
      final bytes = await latest.first
          .thumbnailDataWithSize(const ThumbnailSize.square(160));
      if (mounted) setState(() => galleryThumb = bytes);
    } catch (_) {
      // Gallery preview is optional (e.g. plugin needs a full rebuild).
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> flip() async {
    if (starting || busy || recording || cameras.length < 2) return;
    setState(() => starting = true);
    await release();
    if (!mounted || !active) return;
    lens = (lens + 1) % cameras.length;
    await start();
  }

  Future<void> cycleFlash() async {
    final camera = controller;
    if (camera == null || starting) return;
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await camera.setFlashMode(next);
      if (mounted) setState(() => flash = next);
    } catch (_) {
      _say('Flash is unavailable for this camera.');
    }
  }

  Future<void> takePhoto() async {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized || busy || starting) {
      return;
    }
    setState(() => busy = true);
    try {
      final photo = await camera.takePicture();
      if (mounted) Navigator.pop(context, MomentCapture(path: photo.path));
    } catch (_) {
      _say('Could not capture. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startRecording() async {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized || recording || busy) {
      return;
    }
    try {
      await camera.startVideoRecording();
      recordWatch
        ..reset()
        ..start();
      recordLimit = Timer(const Duration(seconds: 60), stopRecording);
      if (mounted) setState(() => recording = true);
    } catch (_) {
      _say('Could not start recording.');
    }
  }

  Future<void> stopRecording() async {
    final camera = controller;
    recordLimit?.cancel();
    if (camera == null || !recording) return;
    setState(() {
      recording = false;
      busy = true;
    });
    try {
      final file = await camera.stopVideoRecording();
      recordWatch.stop();
      if (mounted) {
        Navigator.pop(context, MomentCapture(path: file.path, video: true));
      }
    } catch (_) {
      _say('Could not save the recording.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickMedia();
      if (picked == null || !mounted) return;
      final lower = picked.path.toLowerCase();
      final video = ['.mp4', '.mov', '.m4v', '.webm', '.3gp']
          .any((ext) => lower.endsWith(ext));
      Navigator.pop(context, MomentCapture(path: picked.path, video: video));
    } catch (_) {
      _say('Could not open your gallery.');
    }
  }

  void comingSoon(String feature) => _say('$feature is coming soon.');

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    final ready =
        camera?.value.isInitialized == true && !starting && error == null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(fit: StackFit.expand, children: [
                  if (ready)
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: camera!.value.previewSize?.height ?? 1080,
                        height: camera.value.previewSize?.width ?? 1920,
                        child: CameraPreview(camera),
                      ),
                    )
                  else
                    Container(
                      color: const Color(0xFF15181E),
                      alignment: Alignment.center,
                      child: error == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(error!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white70)),
                                    const SizedBox(height: 12),
                                    OutlinedButton(
                                        onPressed: start,
                                        child: const Text('Retry camera')),
                                  ]),
                            ),
                    ),
                  if (expanded)
                    GestureDetector(
                      onTap: () => setState(() => expanded = false),
                      child: Container(color: Colors.black45),
                    ),
                  // Top bar.
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 8,
                    child: Row(children: [
                      _TopButton(
                          tooltip: 'Close camera',
                          icon: Icons.close_rounded,
                          onTap: () => Navigator.pop(context)),
                      const Spacer(),
                      _TopButton(
                          tooltip: 'Flash',
                          icon: switch (flash) {
                            FlashMode.auto => Icons.flash_auto_rounded,
                            FlashMode.always => Icons.flash_on_rounded,
                            _ => Icons.flash_off_rounded,
                          },
                          onTap: cycleFlash),
                      const Spacer(),
                      _TopButton(
                          tooltip: 'Camera settings',
                          icon: Icons.settings_outlined,
                          onTap: () => comingSoon('Camera settings')),
                    ]),
                  ),
                  // Left tools.
                  Positioned(
                    left: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SideTool(
                              expanded: expanded,
                              label: 'Create',
                              child: const Text('Aa',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w500)),
                              onTap: () => Navigator.pop(context,
                                  const MomentCapture(create: true))),
                          _SideTool(
                              expanded: expanded,
                              label: 'Boomerang',
                              child: const Icon(Icons.all_inclusive_rounded,
                                  color: Colors.white, size: 30),
                              onTap: () => comingSoon('Boomerang')),
                          _SideTool(
                              expanded: expanded,
                              label: 'Effects',
                              child: const Icon(Icons.blur_on_rounded,
                                  color: Colors.white, size: 30),
                              onTap: () => comingSoon('Effects')),
                          if (expanded) ...[
                            _SideTool(
                                expanded: true,
                                label: 'Layout',
                                child: const Icon(Icons.dashboard_outlined,
                                    color: Colors.white, size: 28),
                                onTap: () => comingSoon('Layout')),
                            _SideTool(
                                expanded: true,
                                label: handsFree
                                    ? 'Hands-free on'
                                    : 'Hands-free',
                                child: Icon(
                                    handsFree
                                        ? Icons.stop_circle_rounded
                                        : Icons.stop_circle_outlined,
                                    color: handsFree
                                        ? PhlioColors.brandPeach
                                        : Colors.white,
                                    size: 30),
                                onTap: () => setState(() {
                                      handsFree = !handsFree;
                                      expanded = false;
                                    })),
                          ],
                          _SideTool(
                              expanded: expanded,
                              label: 'Close',
                              child: Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 32),
                              onTap: () =>
                                  setState(() => expanded = !expanded)),
                        ],
                      ),
                    ),
                  ),
                  if (recording)
                    Positioned(
                      top: 64,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                              color: PhlioColors.danger,
                              borderRadius: BorderRadius.circular(14)),
                          child: const Text('REC',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  // Shutter row inside the preview, like the reference.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 18,
                    child: Center(
                      child: _Shutter(
                        recording: recording,
                        busy: busy,
                        onTap: handsFree
                            ? (recording ? stopRecording : startRecording)
                            : (recording ? stopRecording : takePhoto),
                        onLongPressStart: handsFree ? null : startRecording,
                        onLongPressEnd: handsFree ? null : stopRecording,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            // Bottom: gallery · MOMENT · flip.
            SizedBox(
              height: 84,
              child: Row(children: [
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: pickFromGallery,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                      color: const Color(0xFF22262D),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: galleryThumb != null
                        ? Image.memory(galleryThumb!, fit: BoxFit.cover)
                        : const Icon(Icons.photo_library_outlined,
                            color: Colors.white, size: 22),
                  ),
                ),
                const Expanded(
                  child: Center(
                    child: Text('MOMENT',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.4)),
                  ),
                ),
                IconButton(
                  tooltip: 'Flip camera',
                  onPressed: ready && cameras.length > 1 ? flip : null,
                  icon: const Icon(Icons.cameraswitch_outlined,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(width: 10),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton(
      {required this.tooltip, required this.icon, required this.onTap});
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon,
            color: Colors.white,
            size: 32,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)]),
      );
}

class _SideTool extends StatelessWidget {
  const _SideTool(
      {required this.expanded,
      required this.label,
      required this.child,
      required this.onTap});
  final bool expanded;
  final String label;
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 44, child: Center(child: child)),
            if (expanded) ...[
              const SizedBox(width: 16),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
            ],
          ]),
        ),
      );
}

class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.recording,
    required this.busy,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
  });
  final bool recording, busy;
  final VoidCallback onTap;
  final VoidCallback? onLongPressStart, onLongPressEnd;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        onLongPressStart:
            onLongPressStart == null ? null : (_) => onLongPressStart!(),
        onLongPressEnd: onLongPressEnd == null ? null : (_) => onLongPressEnd!(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: recording ? 92 : 80,
          height: recording ? 92 : 80,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: recording ? PhlioColors.danger : Colors.white,
                width: 4.5),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording
                  ? PhlioColors.danger
                  : Colors.white.withValues(alpha: busy ? .5 : .95),
            ),
          ),
        ),
      );
}
