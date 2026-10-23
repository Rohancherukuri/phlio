import 'snap_audience.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Returns a captured photo, true for the Memories grid, or null on close.
class SnapCameraScreen extends StatefulWidget {
  const SnapCameraScreen({super.key, this.audience = const SnapAudience()});
  final SnapAudience audience;
  @override
  State<SnapCameraScreen> createState() => _SnapCameraState();
}

class _SnapCameraState extends State<SnapCameraScreen>
    with WidgetsBindingObserver {
  late SnapAudience audience = widget.audience;
  CameraController? controller;
  List<CameraDescription> cameras = [];
  int lens = 0, generation = 0;
  bool starting = false, taking = false, active = true;
  FlashMode flash = FlashMode.off;
  String? error;
  Future<void> pendingRelease = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
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
        final front = cameras
            .indexWhere((c) => c.lensDirection == CameraLensDirection.front);
        lens = front < 0 ? 0 : front;
      }
      if (!mounted || token != generation || !active) return;
      if (cameras.isEmpty) throw StateError('No camera');
      final camera = CameraController(
        cameras[lens],
        ResolutionPreset.high,
        enableAudio: false,
      );
      controller = camera;
      await camera.initialize();
      if (!mounted || token != generation || !active) return;
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await camera.setFlashMode(FlashMode.off);
      flash = FlashMode.off;
    } catch (_) {
      if (mounted && token == generation) {
        error =
            'Camera unavailable. Allow camera access in phone settings, then retry.';
      }
    } finally {
      if (mounted && token == generation) setState(() => starting = false);
    }
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(release());
    super.dispose();
  }

  Future<void> flip() async {
    if (starting || taking || cameras.length < 2) return;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flash is unavailable for this camera.'),
          ),
        );
      }
    }
  }

  Future<void> capture() async {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized || starting || taking) {
      return;
    }
    setState(() => taking = true);
    try {
      final photo = await camera.takePicture();
      if (mounted && active)
        Navigator.pop(context, (photo: photo, audience: audience));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not capture. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    final ready =
        camera?.value.isInitialized == true && !starting && error == null;
    return PopScope(
      canPop: !taking,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            tooltip: 'Close camera',
            onPressed: taking ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: const Text('New snap'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Your memories',
              onPressed: taking ? null : () => Navigator.pop(context, true),
              icon: const Icon(Icons.grid_view_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 440,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(72),
                            child: ColoredBox(
                              color: const Color(
                                0xff191919,
                              ),
                              child: ready
                                  ? LayoutBuilder(
                                      builder: (_, box) => ClipRect(
                                        child: OverflowBox(
                                          maxWidth: double.infinity,
                                          maxHeight: double.infinity,
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            child: SizedBox(
                                              width: box.maxWidth,
                                              height: box.maxWidth *
                                                  camera!.value.aspectRatio,
                                              child: CameraPreview(camera),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: error == null
                                          ? const CircularProgressIndicator()
                                          : Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    error!,
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  TextButton(
                                                    onPressed: () async {
                                                      await release();
                                                      if (mounted) {
                                                        start();
                                                      }
                                                    },
                                                    child: const Text(
                                                        'Retry camera'),
                                                  ),
                                                ],
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
                            tooltip: flash == FlashMode.off
                                ? 'Enable flash'
                                : 'Disable flash',
                            onPressed: ready && !taking ? toggleFlash : null,
                            icon: Icon(
                              flash == FlashMode.off
                                  ? Icons.flash_off
                                  : Icons.flash_on,
                            ),
                          ),
                          Semantics(
                            label: 'Capture snap',
                            button: true,
                            child: InkWell(
                              onTap: ready && !taking ? capture : null,
                              borderRadius: BorderRadius.circular(48),
                              child: Container(
                                width: 88,
                                height: 88,
                                padding: const EdgeInsets.all(
                                  7,
                                ),
                                decoration: const BoxDecoration(
                                  color: Color(
                                    0xff292b30,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: ready ? Colors.white : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                  child: taking
                                      ? const Padding(
                                          padding: EdgeInsets.all(20),
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Flip camera',
                            onPressed: ready && !taking && cameras.length > 1
                                ? flip
                                : null,
                            icon: const Icon(
                              Icons.flip_camera_ios_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      ActionChip(
                          avatar:
                              const Icon(Icons.people_alt_outlined, size: 18),
                          label: Text(audience.label),
                          onPressed: () async {
                            final value =
                                await pickSnapAudience(context, audience);
                            if (mounted && value != null)
                              setState(() => audience = value);
                          }),
                      const Text(
                        'Preview before sharing. Your audience can view for 24 hours.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
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
