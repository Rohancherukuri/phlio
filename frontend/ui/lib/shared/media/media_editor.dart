// Advanced photo and video editor (Experiences).
//
//   Crop     aspect presets, pinch / drag to frame, rotate 90°, flip and —
//            for photos — straighten (-45°..45°).
//   Adjust   exposure, brightness, contrast, highlights, shadows, warmth,
//            tint, saturation, vibrance, fade, clarity, sharpen, vignette,
//            grain (a colour grade on the GPU, story_grade.frag).
//   Filters  Phlio looks with strength.
//   Effects  the full story effects catalogue (AR / AI say "coming soon").
//   Trim, Speed, Sound (videos).
//
// Nothing is lost: photos bake only the geometry (crop / rotate / flip /
// straighten) into a new JPEG; colour, looks and effects stay data in the
// filter spec, drawn live and editable later. Videos send every geometric
// and time edit as data and the server renders them with FFmpeg
// (backend/app/api/v1/media_edits.py), matching the preview here.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'phlio_look_view.dart';
import 'smart_filters.dart';
import 'story_fx_catalog.dart';
import 'story_fx_view.dart';

/// What the editor produced for one photo / video.
class MediaEdit {
  MediaEdit({
    required this.path,
    FilterSpec? spec,
    this.quarterTurns = 0,
    this.flip = false,
    this.straighten = 0,
    this.aspect,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.trimStart,
    this.trimEnd,
    this.speed = 1,
    this.mute = false,
    this.motion,
    this.crop,
  }) : spec = spec ?? FilterSpec();

  /// The file to upload (photos: a new file when the geometry changed).
  final String path;
  final FilterSpec spec;

  // Geometry, kept so the editor reopens where you left it.
  final int quarterTurns;
  final bool flip;
  final double straighten, zoom;
  final double? aspect;
  final Offset pan;

  // Video only.
  final Duration? trimStart, trimEnd;
  final double speed;
  final bool mute;
  final String? motion;

  /// Video crop as fractions of the source frame [x, y, w, h].
  final List<double>? crop;

  bool get hasVideoEdits =>
      (trimStart != null && trimStart! > Duration.zero) ||
      trimEnd != null ||
      speed != 1 ||
      mute ||
      quarterTurns % 4 != 0 ||
      flip ||
      crop != null ||
      motion != null;

  /// `edits` form field for videos (null when there's nothing to do).
  Map<String, dynamic>? videoEdits() => !hasVideoEdits
      ? null
      : {
          if (trimStart != null && trimStart! > Duration.zero) 'trim_start': trimStart!.inMilliseconds / 1000,
          if (trimEnd != null) 'trim_end': trimEnd!.inMilliseconds / 1000,
          if (speed != 1) 'speed': speed,
          if (mute) 'mute': true,
          if (quarterTurns % 4 != 0) 'rotate': (quarterTurns % 4) * 90,
          if (flip) 'flip': true,
          if (crop != null) 'crop': crop,
          if (motion != null) 'motion': motion,
        };
}

Future<MediaEdit?> openMediaEditor(BuildContext context,
        {required String original, required bool isVideo, MediaEdit? initial}) =>
    Navigator.of(context, rootNavigator: true).push<MediaEdit>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MediaEditorScreen(original: original, isVideo: isVideo, initial: initial),
    ));

const _adjustTools = <(String, String, IconData)>[
  ('exposure', 'Exposure', Icons.exposure_rounded),
  ('brightness', 'Brightness', Icons.light_mode_outlined),
  ('contrast', 'Contrast', Icons.contrast_rounded),
  ('highlights', 'Highlights', Icons.wb_sunny_outlined),
  ('shadows', 'Shadows', Icons.nights_stay_outlined),
  ('warmth', 'Warmth', Icons.thermostat_rounded),
  ('tint', 'Tint', Icons.colorize_rounded),
  ('saturation', 'Saturation', Icons.water_drop_outlined),
  ('vibrance', 'Vibrance', Icons.palette_outlined),
  ('fade', 'Fade', Icons.gradient_rounded),
  ('clarity', 'Clarity', Icons.blur_off_rounded),
  ('sharpen', 'Sharpen', Icons.details_rounded),
  ('vignette', 'Vignette', Icons.vignette_outlined),
  ('grain', 'Grain', Icons.grain_rounded),
];

const _aspects = <(String, double?)>[
  ('Original', null),
  ('1:1', 1),
  ('4:5', 4 / 5),
  ('3:4', 3 / 4),
  ('9:16', 9 / 16),
  ('16:9', 16 / 9),
];

class MediaEditorScreen extends StatefulWidget {
  const MediaEditorScreen({required this.original, required this.isVideo, this.initial, super.key});
  final String original;
  final bool isVideo;
  final MediaEdit? initial;

  @override
  State<MediaEditorScreen> createState() => _MediaEditorScreenState();
}

class _MediaEditorScreenState extends State<MediaEditorScreen> {
  late final FilterSpec spec = widget.initial?.spec.copy() ?? FilterSpec();
  late int quarterTurns = widget.initial?.quarterTurns ?? 0;
  late bool flip = widget.initial?.flip ?? false;
  late double straighten = widget.initial?.straighten ?? 0;
  late double? aspect = widget.initial?.aspect;
  late double zoom = widget.initial?.zoom ?? 1;
  late Offset pan = widget.initial?.pan ?? Offset.zero;
  late double speed = widget.initial?.speed ?? 1;
  late bool mute = widget.initial?.mute ?? false;
  late String? motion = widget.initial?.motion;
  RangeValues? trim; // seconds

  String tab = 'crop';
  String tool = 'exposure';
  bool busy = false;

  Size? sourceSize; // pixels of the photo / video frame
  VideoPlayerController? video;
  double _zoomStart = 1;
  Offset _panStart = Offset.zero, _focalStart = Offset.zero;

  bool get isVideo => widget.isVideo;

  @override
  void initState() {
    super.initState();
    if (isVideo) {
      final c = VideoPlayerController.file(File(widget.original));
      video = c;
      c.initialize().then((_) async {
        if (!mounted) return;
        final length = c.value.duration.inMilliseconds / 1000;
        final i = widget.initial;
        trim = RangeValues(
          ((i?.trimStart?.inMilliseconds ?? 0) / 1000).clamp(0.0, length),
          ((i?.trimEnd?.inMilliseconds ?? (length * 1000).round()) / 1000).clamp(0.0, length),
        );
        sourceSize = c.value.size;
        await c.setLooping(true);
        await c.setVolume(mute ? 0 : 1);
        await c.setPlaybackSpeed(speed);
        c.addListener(_loopTrim);
        await c.play();
        if (mounted) setState(() {});
      });
    } else {
      FileImage(File(widget.original)).resolve(const ImageConfiguration()).addListener(
            ImageStreamListener((info, _) {
              if (mounted) setState(() => sourceSize = Size(info.image.width.toDouble(), info.image.height.toDouble()));
            }),
          );
    }
  }

  void _loopTrim() {
    final c = video;
    final t = trim;
    if (c == null || t == null || !c.value.isInitialized) return;
    final pos = c.value.position.inMilliseconds / 1000;
    if (pos > t.end + .05 || pos < t.start - .3) c.seekTo(Duration(milliseconds: (t.start * 1000).round()));
  }

  @override
  void dispose() {
    video?.removeListener(_loopTrim);
    video?.dispose();
    super.dispose();
  }

  // -- geometry -----------------------------------------------------------------------------

  /// Image size after the quarter turns.
  Size get _rotated {
    final s = sourceSize ?? const Size(1, 1);
    return quarterTurns.isOdd ? Size(s.height, s.width) : s;
  }

  /// Output frame aspect (width / height).
  double get _frameAspect => aspect ?? (_rotated.width / _rotated.height);

  /// Output frame in source-pixel units (keeps the photo's resolution).
  Size get _frameSize {
    final r = _rotated;
    final a = _frameAspect;
    return r.width / r.height > a ? Size(r.height * a, r.height) : Size(r.width, r.width / a);
  }

  /// Scale that makes the (rotated, straightened) picture cover the frame.
  double _coverScale(Size frame) {
    final r = _rotated;
    final angle = straighten * math.pi / 180;
    final c = math.cos(angle).abs(), s = math.sin(angle).abs();
    return math.max((frame.width * c + frame.height * s) / r.width, (frame.width * s + frame.height * c) / r.height);
  }

  /// Source point (centred, px) -> frame point (centred, px).
  Matrix4 _matrix(Size frame) {
    final k = _coverScale(frame) * zoom;
    return Matrix4.identity()
      ..translate(pan.dx * frame.width, pan.dy * frame.height)
      ..scale(flip ? -1.0 : 1.0, 1.0)
      ..rotateZ(quarterTurns * math.pi / 2 + straighten * math.pi / 180)
      ..scale(k, k);
  }

  void _clampPan() {
    final room = (zoom - 1) / 2;
    pan = Offset(pan.dx.clamp(-room, room), pan.dy.clamp(-room, room));
  }

  /// The frame as a rectangle of the source (fractions), for FFmpeg.
  List<double>? _videoCrop() {
    final src = sourceSize;
    if (src == null) return null;
    final frame = _frameSize;
    final inverse = Matrix4.inverted(_matrix(frame));
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final corner in [
      Offset(-frame.width / 2, -frame.height / 2),
      Offset(frame.width / 2, -frame.height / 2),
      Offset(-frame.width / 2, frame.height / 2),
      Offset(frame.width / 2, frame.height / 2),
    ]) {
      final p = MatrixUtils.transformPoint(inverse, corner);
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final x = ((minX + src.width / 2) / src.width).clamp(0.0, 1.0);
    final y = ((minY + src.height / 2) / src.height).clamp(0.0, 1.0);
    final w = ((maxX - minX) / src.width).clamp(0.05, 1.0 - x);
    final h = ((maxY - minY) / src.height).clamp(0.05, 1.0 - y);
    if (x < .002 && y < .002 && w > .996 && h > .996) return null;
    return [x, y, w, h].map((v) => double.parse(v.toStringAsFixed(4))).toList();
  }

  bool get _geometryChanged =>
      quarterTurns % 4 != 0 || flip || straighten.abs() > .05 || aspect != null || zoom > 1.001 || pan != Offset.zero;

  // -- done ---------------------------------------------------------------------------------

  Future<void> _done() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      var path = widget.original;
      if (!isVideo && _geometryChanged) path = await _bakePhoto();
      final t = trim;
      final length = video?.value.duration.inMilliseconds;
      if (!mounted) return;
      Navigator.of(context).pop(MediaEdit(
        path: path,
        spec: spec,
        quarterTurns: quarterTurns,
        flip: flip,
        straighten: straighten,
        aspect: aspect,
        zoom: zoom,
        pan: pan,
        trimStart: t == null || t.start < .05 ? null : Duration(milliseconds: (t.start * 1000).round()),
        trimEnd: t == null || length == null || t.end * 1000 > length - 60 ? null : Duration(milliseconds: (t.end * 1000).round()),
        speed: speed,
        mute: mute,
        motion: motion,
        crop: isVideo ? _videoCrop() : null,
      ));
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save your edit. Try again.')));
      }
    }
  }

  /// Crop / rotate / flip / straighten the photo into a new JPEG-quality PNG.
  Future<String> _bakePhoto() async {
    final bytes = await File(widget.original).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    sourceSize = Size(image.width.toDouble(), image.height.toDouble());
    final frame = _frameSize;
    const maxSide = 2400.0;
    final shrink = math.min(1.0, maxSide / math.max(frame.width, frame.height));
    final out = Size((frame.width * shrink).roundToDouble(), (frame.height * shrink).roundToDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(out.width / 2, out.height / 2);
    canvas.scale(shrink, shrink);
    canvas.transform(_matrix(frame).storage);
    canvas.drawImage(image, Offset(-image.width / 2, -image.height / 2), Paint()..filterQuality = FilterQuality.high);
    final picture = recorder.endRecording();
    final baked = await picture.toImage(out.width.toInt(), out.height.toInt());
    final png = await baked.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    baked.dispose();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/edit_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    return file.path;
  }

  // -- UI -----------------------------------------------------------------------------------

  Widget _media() {
    if (isVideo) {
      final c = video;
      if (c == null || !c.value.isInitialized) return const ColoredBox(color: Colors.black);
      return VideoPlayer(c);
    }
    return Image.file(File(widget.original), fit: BoxFit.fill, filterQuality: FilterQuality.medium);
  }

  /// The picture with its look, adjustments and effect, inside the crop frame.
  Widget _preview() {
    final src = sourceSize;
    if (src == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (context, box) {
      final frameAspect = _frameAspect;
      var fw = box.maxWidth, fh = box.maxWidth / frameAspect;
      if (fh > box.maxHeight) {
        fh = box.maxHeight;
        fw = fh * frameAspect;
      }
      final frame = _frameSize;
      final d = fw / frame.width; // display px per source px
      final m = _matrix(frame);
      final graded = StoryFxLayer(
        fx: spec.fx,
        amount: spec.fxAmount,
        adjust: spec.adjust,
        child: PhlioLook(look: spec.look, strength: spec.strength, child: _media()),
      );
      return Center(
        child: GestureDetector(
          onScaleStart: tab == 'crop'
              ? (s) {
                  _zoomStart = zoom;
                  _panStart = pan;
                  _focalStart = s.focalPoint;
                }
              : null,
          onScaleUpdate: tab == 'crop'
              ? (s) => setState(() {
                    zoom = (_zoomStart * s.scale).clamp(1.0, 5.0);
                    final delta = s.focalPoint - _focalStart;
                    pan = _panStart + Offset(delta.dx / fw, delta.dy / fh);
                    _clampPan();
                  })
              : null,
          onDoubleTap: tab == 'crop'
              ? () => setState(() {
                    zoom = 1;
                    pan = Offset.zero;
                  })
              : null,
          child: SizedBox(
            width: fw,
            height: fh,
            child: Stack(fit: StackFit.expand, children: [
              ClipRect(
                child: OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(d, d, 1)..multiply(m),
                    child: SizedBox(width: src.width, height: src.height, child: graded),
                  ),
                ),
              ),
              if (tab == 'crop') const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
            ]),
          ),
        ),
      );
    });
  }

  Widget _toolPanel() {
    switch (tab) {
      case 'crop':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 38,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final (label, value) in _aspects)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: aspect == value,
                    onSelected: (_) => setState(() {
                      aspect = value;
                      zoom = 1;
                      pan = Offset.zero;
                    }),
                  ),
                ),
            ]),
          ),
          if (!isVideo)
            Row(children: [
              const SizedBox(width: 16),
              const Icon(Icons.straighten_rounded, color: Colors.white60, size: 20),
              Expanded(
                child: Slider(
                  min: -45,
                  max: 45,
                  divisions: 180,
                  value: straighten,
                  label: '${straighten.toStringAsFixed(1)}°',
                  onChanged: (v) => setState(() => straighten = v),
                ),
              ),
              SizedBox(
                  width: 48,
                  child: Text('${straighten.toStringAsFixed(1)}°', style: const TextStyle(color: Colors.white70))),
            ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _RoundTool(
              icon: Icons.rotate_90_degrees_ccw_rounded,
              label: 'Rotate',
              onTap: () => setState(() {
                quarterTurns = (quarterTurns + 3) % 4;
                zoom = 1;
                pan = Offset.zero;
              }),
            ),
            _RoundTool(
              icon: Icons.flip_rounded,
              label: 'Flip',
              on: flip,
              onTap: () => setState(() => flip = !flip),
            ),
            _RoundTool(
              icon: Icons.restart_alt_rounded,
              label: 'Reset',
              onTap: () => setState(() {
                quarterTurns = 0;
                flip = false;
                straighten = 0;
                aspect = null;
                zoom = 1;
                pan = Offset.zero;
              }),
            ),
          ]),
        ]);
      case 'adjust':
        final value = spec.adjust[tool] ?? 0;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const SizedBox(width: 16),
            Text(_adjustTools.firstWhere((t) => t.$1 == tool).$2,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            Expanded(
              child: Slider(
                min: -1,
                max: 1,
                value: value,
                onChanged: (v) => setState(() {
                  if (v.abs() < .02) {
                    spec.adjust.remove(tool);
                  } else {
                    spec.adjust[tool] = double.parse(v.toStringAsFixed(3));
                  }
                }),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => spec.adjust.remove(tool)),
              child: SizedBox(
                width: 46,
                child: Text('${(value * 100).round()}', style: const TextStyle(color: Colors.white70)),
              ),
            ),
          ]),
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (id, label, icon) in _adjustTools)
                  _RoundTool(
                    icon: icon,
                    label: label,
                    on: tool == id,
                    dot: (spec.adjust[id] ?? 0).abs() > .001,
                    onTap: () => setState(() => tool = id),
                  ),
              ],
            ),
          ),
        ]);
      case 'filters':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (spec.look != 'normal')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Slider(value: spec.strength, onChanged: (v) => setState(() => spec.strength = v)),
            ),
          SizedBox(
            height: 96,
            child: PhlioLookStrip(
              selected: spec.look,
              thumb: _thumb(),
              onPick: (id) => setState(() => spec.look = id),
            ),
          ),
        ]);
      case 'effects':
        final def = storyFxById[spec.fx];
        return Column(mainAxisSize: MainAxisSize.min, children: [
          StoryFxPicker(
            selected: spec.fx,
            motion: motion,
            thumb: _thumb(),
            isVideo: isVideo,
            onPick: (e) => setState(() {
              if (e == null) {
                spec.fx = null;
                motion = null;
              } else if (e.kind == FxKind.video && isVideo) {
                motion = e.motion;
                spec.fx = null;
              } else {
                spec.fx = e.id;
                if (isVideo) motion = null;
              }
            }),
          ),
          if (def != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Slider(value: spec.fxAmount, onChanged: (v) => setState(() => spec.fxAmount = v)),
            )
          else if (motion != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('${storyFxEffects.firstWhere((e) => e.motion == motion).name} is applied when you share',
                  style: const TextStyle(color: Colors.white60)),
            ),
        ]);
      case 'trim':
        final c = video;
        final t = trim;
        if (c == null || t == null) return const SizedBox(height: 90);
        final length = c.value.duration.inMilliseconds / 1000;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RangeSlider(
              min: 0,
              max: math.max(length, .5),
              values: t,
              onChanged: (v) {
                if (v.end - v.start < .5) return;
                setState(() => trim = v);
              },
              onChangeEnd: (v) => c.seekTo(Duration(milliseconds: (v.start * 1000).round())),
            ),
            Text('${_clock(t.start)} – ${_clock(t.end)} · ${(t.end - t.start).toStringAsFixed(1)} s',
                style: const TextStyle(color: Colors.white70)),
          ]),
        );
      case 'speed':
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
            for (final s in const [0.25, 0.5, 1.0, 1.5, 2.0, 3.0])
              ChoiceChip(
                label: Text('${s == s.roundToDouble() ? s.toInt() : s}×'),
                selected: speed == s,
                onSelected: (_) {
                  setState(() => speed = s);
                  video?.setPlaybackSpeed(s);
                },
              ),
          ]),
        );
      case 'sound':
        return SwitchListTile(
          secondary: Icon(mute ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
          title: const Text('Mute this clip', style: TextStyle(color: Colors.white)),
          value: mute,
          onChanged: (v) {
            setState(() => mute = v);
            video?.setVolume(v ? 0 : 1);
          },
        );
    }
    return const SizedBox.shrink();
  }

  String _clock(double s) => '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';

  Widget _thumb() => SizedBox.expand(
        child: isVideo
            ? const DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3A2A5C), Color(0xFFFF8A3D)])))
            : Image.file(File(widget.original), fit: BoxFit.cover, cacheWidth: 200),
      );

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, String, IconData)>[
      ('crop', 'Crop', Icons.crop_rotate_rounded),
      ('adjust', 'Adjust', Icons.tune_rounded),
      ('filters', 'Filters', Icons.filter_vintage_outlined),
      ('effects', 'Effects', Icons.auto_awesome_motion_outlined),
      if (isVideo) ('trim', 'Trim', Icons.content_cut_rounded),
      if (isVideo) ('speed', 'Speed', Icons.speed_rounded),
      if (isVideo) ('sound', 'Sound', Icons.volume_up_outlined),
    ];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(isVideo ? 'Edit video' : 'Edit photo', style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: busy ? null : _done,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Done', style: TextStyle(color: Color(0xFFFFB58F), fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(16), child: _preview())),
          AnimatedSize(duration: const Duration(milliseconds: 180), child: _toolPanel()),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (id, label, icon) in tabs)
                  _TabButton(icon: icon, label: label, on: tab == id, onTap: () => setState(() => tab = id)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 72,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: on ? Colors.white : Colors.white54),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: on ? Colors.white : Colors.white54, fontSize: 12, fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
          ]),
        ),
      );
}

class _RoundTool extends StatelessWidget {
  const _RoundTool({required this.icon, required this.label, required this.onTap, this.on = false, this.dot = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on, dot;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? Colors.white : Colors.white.withValues(alpha: .08),
                ),
                child: Icon(icon, color: on ? Colors.black : Colors.white, size: 22),
              ),
              if (dot)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFFFB58F)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
          ]),
        ),
      );
}

/// Rule-of-thirds guide while cropping.
class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), p);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), p);
    }
    canvas.drawRect(Offset.zero & size, p..color = Colors.white70);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
