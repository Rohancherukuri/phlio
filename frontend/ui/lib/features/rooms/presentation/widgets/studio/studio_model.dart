// Phlio Studio — the project model behind the CapCut-style DM editor.
//
// A project is a main track of clips (photos/videos), overlays (text and
// stickers) and audio items (music, extracted audio, voiceovers). Colour
// filters and adjustments are folded into one 3x4 affine colour matrix that
// is used for the on-device preview (ColorFilter.matrix) *and* sent to the
// server renderer (colorchannelmixer + lutrgb), so what you see is what you
// export.

import 'dart:convert';
import 'dart:math' as math;

import '../../../../../shared/media/phlio_look_data.dart';

int _seq = 0;
String studioId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

double _d(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

// -- clips -----------------------------------------------------------------------

class StudioClip {
  StudioClip({
    required this.path,
    required this.name,
    required this.kind,
    required this.sourceDuration,
    String? id,
    this.start = 0,
    double? end,
    this.fileId,
  })  : id = id ?? studioId(),
        end = end ?? sourceDuration;

  final String id;
  String path, name;
  String kind; // video | image
  double sourceDuration;
  double start, end;
  double speed = 1, volume = 1;
  int turns = 0;
  bool flip = false, flipV = false, reverse = false;
  double? hold; // freeze frame: seconds held
  List<double>? crop; // x, y, w, h (0-1) after rotation/flip
  String filter = 'none';
  double filterAmount = 1;
  Map<String, double> adjust = {};
  String effect = 'none';
  String fit = 'fill';
  double zoom = 1, panX = 0, panY = 0;
  String motion = 'none', animIn = 'none', animOut = 'none';
  double fadeAudioIn = 0, fadeAudioOut = 0;
  String transition = 'none';
  double transitionDuration = .5;
  String? fileId;
  // Speed curve (CapCut "Curve" tab): preset name + [[from, to, speed]] over
  // the trimmed source range (0-1). Null = normal constant speed.
  String? curveName;
  List<List<double>>? curve;
  // Keyframes: [local time, zoom, panX, panY].
  List<List<double>> keys = [];
  String voice = 'none';
  bool denoise = false;

  bool get isPhoto => kind == 'image' || hold != null;
  bool get hasCurve => curve != null && kind == 'video' && hold == null && !reverse;

  double get length {
    if (hold != null) return hold!;
    final span = end - start;
    if (hasCurve) {
      var l = 0.0;
      for (final c in curve!) {
        l += (c[1] - c[0]) * span / c[2];
      }
      return math.max(.3, l);
    }
    return math.max(.3, span / speed);
  }

  /// Source time shown at [local] seconds into the clip.
  double sourceAt(double local) {
    if (hold != null) return start;
    if (hasCurve) {
      final span = end - start;
      var acc = 0.0;
      for (final c in curve!) {
        final seg = (c[1] - c[0]) * span / c[2];
        if (local <= acc + seg) return start + c[0] * span + (local - acc) * c[2];
        acc += seg;
      }
      return end;
    }
    final s = (local * speed).clamp(0.0, end - start);
    return reverse ? end - s : start + s;
  }

  /// Playback speed at [local] (for the preview player).
  double speedAt(double local) {
    if (!hasCurve) return speed;
    final span = end - start;
    var acc = 0.0;
    for (final c in curve!) {
      acc += (c[1] - c[0]) * span / c[2];
      if (local <= acc) return c[2];
    }
    return curve!.last[2];
  }

  /// Zoom / pan at [local], interpolated between keyframes like the server.
  (double, double, double) transformAt(double local) {
    if (keys.isEmpty) return (zoom, panX, panY);
    return (
      keyValue(keys, local, 1),
      keyValue(keys, local, 2),
      keyValue(keys, local, 3),
    );
  }

  void setCurve(String? name) {
    curveName = name;
    curve = name == null ? null : studioCurve(name);
    if (name != null) reverse = false; // curves play forwards
  }

  List<double> get colorMatrix =>
      studioColorMatrix(filter, filterAmount, adjust);

  /// Matrix + look tone curve + vignette/grain (what the GPU shader draws).
  LookGrade get grade => studioGrade(filter, filterAmount, adjust);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'kind': kind,
        'sourceDuration': sourceDuration,
        'start': start,
        'end': end,
        'speed': speed,
        'volume': volume,
        'turns': turns,
        'flip': flip,
        'flipV': flipV,
        'reverse': reverse,
        'hold': hold,
        'crop': crop,
        'filter': filter,
        'filterAmount': filterAmount,
        'adjust': adjust,
        'effect': effect,
        'fit': fit,
        'zoom': zoom,
        'panX': panX,
        'panY': panY,
        'motion': motion,
        'animIn': animIn,
        'animOut': animOut,
        'fadeAudioIn': fadeAudioIn,
        'fadeAudioOut': fadeAudioOut,
        'transition': transition,
        'transitionDuration': transitionDuration,
        'fileId': fileId,
        'curveName': curveName,
        'curve': curve,
        'keys': keys,
        'voice': voice,
        'denoise': denoise,
      };

  static StudioClip fromJson(Map j) => StudioClip(
        id: j['id'] as String,
        path: j['path'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        sourceDuration: _d(j['sourceDuration'], 3),
        start: _d(j['start']),
        end: _d(j['end'], 3),
        fileId: j['fileId'] as String?,
      )
        ..speed = _d(j['speed'], 1)
        ..volume = _d(j['volume'], 1)
        ..turns = (j['turns'] as num?)?.toInt() ?? 0
        ..flip = j['flip'] == true
        ..flipV = j['flipV'] == true
        ..reverse = j['reverse'] == true
        ..hold = (j['hold'] as num?)?.toDouble()
        ..crop = (j['crop'] as List?)?.map((e) => _d(e)).toList()
        ..filter = j['filter'] as String? ?? 'none'
        ..filterAmount = _d(j['filterAmount'], 1)
        ..adjust = {
          for (final e in ((j['adjust'] as Map?) ?? const {}).entries)
            e.key.toString(): _d(e.value)
        }
        ..effect = j['effect'] as String? ?? 'none'
        ..fit = j['fit'] as String? ?? 'fill'
        ..zoom = _d(j['zoom'], 1)
        ..panX = _d(j['panX'])
        ..panY = _d(j['panY'])
        ..motion = j['motion'] as String? ?? 'none'
        ..animIn = j['animIn'] as String? ?? 'none'
        ..animOut = j['animOut'] as String? ?? 'none'
        ..fadeAudioIn = _d(j['fadeAudioIn'])
        ..fadeAudioOut = _d(j['fadeAudioOut'])
        ..transition = j['transition'] as String? ?? 'none'
        ..transitionDuration = _d(j['transitionDuration'], .5)
        ..curveName = j['curveName'] as String?
        ..curve = _rows(j['curve'])
        ..keys = _rows(j['keys']) ?? []
        ..voice = j['voice'] as String? ?? 'none'
        ..denoise = j['denoise'] == true;

  StudioClip duplicate() => fromJson({...toJson(), 'id': studioId()});

  /// Server render spec.
  Map<String, dynamic> plan() {
    final m = colorMatrix;
    final identity = _isIdentity(m);
    return {
      'file_id': fileId,
      'start': double.parse(start.toStringAsFixed(3)),
      'end': double.parse(end.toStringAsFixed(3)),
      'speed': hasCurve ? 1 : speed,
      'volume': volume,
      'turns': turns,
      'flip': flip,
      'flip_v': flipV,
      'reverse': reverse && !isPhoto,
      if (hold != null) 'hold': hold,
      if (crop != null) 'crop': crop,
      if (!identity) 'color': m,
      ..._gradePlan(grade, adjust),
      'effect': effect,
      'fit': fit,
      'zoom': zoom,
      'pan_x': panX,
      'pan_y': panY,
      'motion': motion,
      'anim_in': animIn,
      'anim_out': animOut,
      'fade_audio_in': fadeAudioIn,
      'fade_audio_out': fadeAudioOut,
      'transition': transition,
      'transition_duration': transitionDuration,
      if (hasCurve) 'curve': curve,
      if (keys.isNotEmpty) 'keys': [for (final k in keys) [for (final v in k) _r(v)]],
      'voice': voice,
      'denoise': denoise,
    };
  }
}

// -- overlays (text + stickers) ----------------------------------------------------------

class StudioOverlay {
  StudioOverlay({
    required this.kind,
    String? id,
    this.text = '',
    this.sticker,
    this.asset,
    this.x = .5,
    this.y = .45,
    this.size = .08,
    this.rotation = 0,
    this.start = 0,
    this.end = 3,
  }) : id = id ?? studioId();

  final String id;
  String kind; // text | sticker
  String text;
  String? sticker; // emoji
  String? asset; // bundled Foxy sticker
  double x, y; // centre, fraction of the canvas
  double size; // text: font size / canvas width; sticker: width / canvas width
  double rotation; // radians
  double start, end;
  String font = 'Manrope';
  int color = 0xFFFFFFFF;
  int accent = 0xFF8D78FF; // box / outline / glow colour
  String style = 'shadow'; // plain | shadow | box | outline | neon | gradient
  String align = 'center';
  bool bold = true;
  String animIn = 'fade', animOut = 'fade';
  String loop = 'none'; // bounce | pulse | wiggle | float | blink
  // Keyframes: [time from start, x, y, size, rotation, opacity].
  List<List<double>> keys = [];
  String? fileId; // uploaded PNG at export

  bool get isCaption => kind == 'caption';
  bool get isText => kind == 'text' || kind == 'caption';

  /// Placement at timeline time [t] (keyframes, before in/out/loop motion).
  ({double x, double y, double size, double rotation, double opacity}) at(double t) {
    if (keys.isEmpty) return (x: x, y: y, size: size, rotation: rotation, opacity: 1);
    final l = t - start;
    return (
      x: keyValue(keys, l, 1),
      y: keyValue(keys, l, 2),
      size: keyValue(keys, l, 3),
      rotation: keyValue(keys, l, 4),
      opacity: keyValue(keys, l, 5).clamp(0.0, 1.0),
    );
  }

  /// Needs per-frame placement on the server (rasterised unrotated).
  bool get isDynamic =>
      keys.isNotEmpty ||
      loop != 'none' ||
      const {'pop', 'drop'}.contains(animIn) ||
      animOut == 'shrink';

  String get label => isText
      ? (text.isEmpty ? 'Text' : text.replaceAll('\n', ' '))
      : (sticker ?? 'Sticker');

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'text': text,
        'sticker': sticker,
        'asset': asset,
        'x': x,
        'y': y,
        'size': size,
        'rotation': rotation,
        'start': start,
        'end': end,
        'font': font,
        'color': color,
        'accent': accent,
        'style': style,
        'align': align,
        'bold': bold,
        'animIn': animIn,
        'animOut': animOut,
        'loop': loop,
        'keys': keys,
      };

  static StudioOverlay fromJson(Map j) => StudioOverlay(
        kind: j['kind'] as String,
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        sticker: j['sticker'] as String?,
        asset: j['asset'] as String?,
        x: _d(j['x'], .5),
        y: _d(j['y'], .5),
        size: _d(j['size'], .08),
        rotation: _d(j['rotation']),
        start: _d(j['start']),
        end: _d(j['end'], 3),
      )
        ..font = j['font'] as String? ?? 'Manrope'
        ..color = (j['color'] as num?)?.toInt() ?? 0xFFFFFFFF
        ..accent = (j['accent'] as num?)?.toInt() ?? 0xFF8D78FF
        ..style = j['style'] as String? ?? 'shadow'
        ..align = j['align'] as String? ?? 'center'
        ..bold = j['bold'] != false
        ..animIn = j['animIn'] as String? ?? 'fade'
        ..animOut = j['animOut'] as String? ?? 'fade'
        ..loop = j['loop'] as String? ?? 'none'
        ..keys = _rows(j['keys']) ?? [];

  StudioOverlay duplicate() =>
      fromJson({...toJson(), 'id': studioId(), 'x': x + .04, 'y': y + .04});
}

// -- audio ---------------------------------------------------------------------------

class StudioAudio {
  StudioAudio({
    required this.kind,
    required this.title,
    required this.sourceDuration,
    String? id,
    this.path,
    this.libraryUrl,
    this.at = 0,
    this.start = 0,
    double? end,
    this.fileId,
  })  : id = id ?? studioId(),
        end = end ?? sourceDuration;

  final String id;
  String kind; // music | voice | extract | file
  String title;
  String? path, libraryUrl;
  double sourceDuration, at, start, end;
  double volume = 1, fadeIn = 0, fadeOut = 0;
  String voice = 'none';
  bool denoise = false;
  String? fileId;
  List<double> peaks = const [];

  double get length => math.max(.2, end - start);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'path': path,
        'libraryUrl': libraryUrl,
        'sourceDuration': sourceDuration,
        'at': at,
        'start': start,
        'end': end,
        'volume': volume,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        'fileId': fileId,
        'peaks': peaks,
        'voice': voice,
        'denoise': denoise,
      };

  static StudioAudio fromJson(Map j) => StudioAudio(
        kind: j['kind'] as String,
        title: j['title'] as String,
        sourceDuration: _d(j['sourceDuration'], 1),
        id: j['id'] as String,
        path: j['path'] as String?,
        libraryUrl: j['libraryUrl'] as String?,
        at: _d(j['at']),
        start: _d(j['start']),
        end: _d(j['end'], 1),
        fileId: j['fileId'] as String?,
      )
        ..volume = _d(j['volume'], 1)
        ..fadeIn = _d(j['fadeIn'])
        ..fadeOut = _d(j['fadeOut'])
        ..peaks = ((j['peaks'] as List?) ?? const []).map((e) => _d(e)).toList()
        ..voice = j['voice'] as String? ?? 'none'
        ..denoise = j['denoise'] == true;

  StudioAudio duplicate() => fromJson({...toJson(), 'id': studioId()});

  Map<String, dynamic> plan() => {
        if (libraryUrl != null) 'library_url': libraryUrl else 'file_id': fileId,
        'at': double.parse(at.toStringAsFixed(3)),
        'start': double.parse(start.toStringAsFixed(3)),
        'end': double.parse(end.toStringAsFixed(3)),
        'volume': volume,
        'fade_in': fadeIn,
        'fade_out': fadeOut,
        'voice': voice,
        'denoise': denoise,
      };
}

// -- keyframes ---------------------------------------------------------------------

double _r(double v) => double.parse(v.toStringAsFixed(4));

List<List<double>>? _rows(Object? v) => v is List
    ? [for (final r in v) [for (final x in r as List) _d(x)]]
    : null;

/// Value in column [col] at time [t]: smoothstep between keyframes, held
/// before the first / after the last (the server builds the same curve).
double keyValue(List<List<double>> keys, double t, int col) {
  if (keys.isEmpty) return 0;
  if (t <= keys.first[0]) return keys.first[col];
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i], b = keys[i + 1];
    if (t < b[0]) {
      final p = ((t - a[0]) / math.max(1e-3, b[0] - a[0])).clamp(0.0, 1.0);
      return a[col] + (b[col] - a[col]) * p * p * (3 - 2 * p);
    }
  }
  return keys.last[col];
}

/// Insert or replace the keyframe at [t] (within a frame), kept sorted.
void setKey(List<List<double>> keys, List<double> row) {
  keys.removeWhere((k) => (k[0] - row[0]).abs() < .04);
  keys
    ..add(row)
    ..sort((a, b) => a[0].compareTo(b[0]));
}

int keyIndexAt(List<List<double>> keys, double t) =>
    keys.indexWhere((k) => (k[0] - t).abs() < .04);

// -- overlay media (picture-in-picture) ------------------------------------------------

class StudioPip {
  StudioPip({
    required this.path,
    required this.name,
    required this.kind,
    required this.sourceDuration,
    String? id,
    this.at = 0,
    this.start = 0,
    double? end,
    this.aspect = 1,
  })  : id = id ?? studioId(),
        end = end ?? sourceDuration;

  final String id;
  String path, name, kind; // video | image
  double sourceDuration, at, start, end;
  double aspect; // width / height of the source
  double speed = 1, volume = 1;
  double x = .5, y = .5, w = .5, rotation = 0, opacity = 1;
  bool flip = false;
  String blend = 'normal';
  String mask = 'none'; // none | linear | mirror | circle | rect | heart | star
  double maskSize = .8, maskFeather = .1, maskRotation = 0;
  bool maskInvert = false;
  int? chroma; // ARGB key colour
  double chromaStrength = .3;
  String filter = 'none';
  double filterAmount = 1;
  Map<String, double> adjust = {};
  String animIn = 'none', animOut = 'none';
  // Keyframes: [time from `at`, x, y, scale, rotation, opacity].
  List<List<double>> keys = [];
  String? fileId, maskFileId;

  bool get isPhoto => kind == 'image';
  double get length => math.max(.2, (end - start) / speed);
  double sourceAt(double local) => start + (local * speed).clamp(0.0, end - start);
  List<double> get colorMatrix => studioColorMatrix(filter, filterAmount, adjust);
  LookGrade get grade => studioGrade(filter, filterAmount, adjust);

  ({double x, double y, double scale, double rotation, double opacity}) placeAt(double t) {
    if (keys.isEmpty) return (x: x, y: y, scale: 1, rotation: rotation, opacity: opacity);
    final l = t - at;
    return (
      x: keyValue(keys, l, 1),
      y: keyValue(keys, l, 2),
      scale: keyValue(keys, l, 3),
      rotation: keyValue(keys, l, 4),
      opacity: keyValue(keys, l, 5).clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'path': path, 'name': name, 'kind': kind,
        'sourceDuration': sourceDuration, 'at': at, 'start': start, 'end': end,
        'aspect': aspect, 'speed': speed, 'volume': volume, 'x': x, 'y': y, 'w': w,
        'rotation': rotation, 'opacity': opacity, 'flip': flip, 'blend': blend,
        'mask': mask, 'maskSize': maskSize, 'maskFeather': maskFeather,
        'maskRotation': maskRotation, 'maskInvert': maskInvert, 'chroma': chroma,
        'chromaStrength': chromaStrength, 'filter': filter, 'filterAmount': filterAmount,
        'adjust': adjust, 'animIn': animIn, 'animOut': animOut, 'keys': keys,
        'fileId': fileId,
      };

  static StudioPip fromJson(Map j) => StudioPip(
        path: j['path'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        sourceDuration: _d(j['sourceDuration'], 3),
        id: j['id'] as String,
        at: _d(j['at']),
        start: _d(j['start']),
        end: _d(j['end'], 3),
        aspect: _d(j['aspect'], 1),
      )
        ..speed = _d(j['speed'], 1)
        ..volume = _d(j['volume'], 1)
        ..x = _d(j['x'], .5)
        ..y = _d(j['y'], .5)
        ..w = _d(j['w'], .5)
        ..rotation = _d(j['rotation'])
        ..opacity = _d(j['opacity'], 1)
        ..flip = j['flip'] == true
        ..blend = j['blend'] as String? ?? 'normal'
        ..mask = j['mask'] as String? ?? 'none'
        ..maskSize = _d(j['maskSize'], .8)
        ..maskFeather = _d(j['maskFeather'], .1)
        ..maskRotation = _d(j['maskRotation'])
        ..maskInvert = j['maskInvert'] == true
        ..chroma = (j['chroma'] as num?)?.toInt()
        ..chromaStrength = _d(j['chromaStrength'], .3)
        ..filter = j['filter'] as String? ?? 'none'
        ..filterAmount = _d(j['filterAmount'], 1)
        ..adjust = {
          for (final e in ((j['adjust'] as Map?) ?? const {}).entries) e.key.toString(): _d(e.value)
        }
        ..animIn = j['animIn'] as String? ?? 'none'
        ..animOut = j['animOut'] as String? ?? 'none'
        ..keys = _rows(j['keys']) ?? []
        ..fileId = j['fileId'] as String?;

  StudioPip duplicate() => fromJson({...toJson(), 'id': studioId()});

  /// Server spec; [maskId] is the uploaded mask PNG.
  Map<String, dynamic> plan(String? maskId) {
    final m = colorMatrix;
    return {
      'file_id': fileId,
      'at': _r(at),
      'start': _r(start),
      'end': _r(end),
      'speed': speed,
      'volume': volume,
      'cx': _r(x),
      'cy': _r(y),
      'w': _r(w),
      'rotation': _r(rotation),
      'flip': flip,
      'opacity': _r(opacity),
      'blend': blend,
      if (maskId != null) 'mask_id': maskId,
      if (chroma != null)
        'chroma': '#${(chroma! & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      'chroma_strength': chromaStrength,
      if (!_isIdentity(m)) 'color': m,
      if (!grade.toneIsIdentity) 'tone': [for (final v in grade.tone) _r(v)],
      if (keys.isNotEmpty)
        'keys': [
          for (final k in keys) [_r(k[0] + at), _r(k[1]), _r(k[2]), _r(k[3]), _r(k[4]), _r(k[5])]
        ],
      'anim_in': animIn,
      'anim_out': animOut,
    };
  }
}

String _effectName(String? id) {
  for (final (key, name) in studioSegmentEffects) {
    if (key == id) return name;
  }
  return 'Effect';
}

// -- timeline effects / filters / adjustments ----------------------------------------------

class StudioSegment {
  StudioSegment({required this.kind, String? id, this.start = 0, this.end = 3, this.effect})
      : id = id ?? studioId();
  final String id;
  String kind; // effect | filter | adjust
  String? effect;
  String filter = 'none';
  double filterAmount = 1;
  Map<String, double> adjust = {};
  double start, end;

  String get label => switch (kind) {
        'effect' => _effectName(effect),
        'filter' => studioFilterNames[filter] ?? 'Filter',
        _ => 'Adjust',
      };

  List<double> get colorMatrix =>
      studioColorMatrix(kind == 'filter' ? filter : 'none', filterAmount, adjust);
  LookGrade get grade => studioGrade(kind == 'filter' ? filter : 'none', filterAmount, adjust);

  Map<String, dynamic> toJson() => {
        'id': id, 'kind': kind, 'effect': effect, 'filter': filter,
        'filterAmount': filterAmount, 'adjust': adjust, 'start': start, 'end': end,
      };

  static StudioSegment fromJson(Map j) => StudioSegment(
        kind: j['kind'] as String,
        id: j['id'] as String,
        start: _d(j['start']),
        end: _d(j['end'], 3),
        effect: j['effect'] as String?,
      )
        ..filter = j['filter'] as String? ?? 'none'
        ..filterAmount = _d(j['filterAmount'], 1)
        ..adjust = {
          for (final e in ((j['adjust'] as Map?) ?? const {}).entries) e.key.toString(): _d(e.value)
        };

  StudioSegment duplicate() => fromJson({...toJson(), 'id': studioId()});

  Map<String, dynamic> plan() => kind == 'effect'
      ? {'kind': 'effect', 'effect': effect, 'start': _r(start), 'end': _r(end)}
      : {
          'kind': 'color',
          'color': colorMatrix,
          ..._gradePlan(grade, adjust),
          'start': _r(start),
          'end': _r(end),
        };
}

// -- project -------------------------------------------------------------------------

class StudioProject {
  final clips = <StudioClip>[];
  final overlays = <StudioOverlay>[];
  final audios = <StudioAudio>[];
  final pips = <StudioPip>[];
  final segments = <StudioSegment>[];
  String ratio = '9:16';
  int resolution = 1080, fps = 30;
  String quality = 'recommended'; // low | recommended | high
  String background = 'blur'; // blur | #rrggbb
  double blur = .6;
  bool muteOriginal = false;
  double? coverTime; // frame used as the cover
  String? coverPath; // or a photo from the gallery
  String coverText = '';

  double overlapAfter(int i) {
    if (i < 0 || i >= clips.length - 1) return 0;
    final a = clips[i], b = clips[i + 1];
    if (a.transition == 'none') return 0;
    return [a.transitionDuration, a.length / 3, b.length / 3].reduce(math.min);
  }

  /// Timeline start of every clip (transitions overlap neighbours).
  List<double> get starts {
    final out = <double>[];
    var t = 0.0;
    for (var i = 0; i < clips.length; i++) {
      out.add(t);
      t += clips[i].length - overlapAfter(i);
    }
    return out;
  }

  double get total {
    if (clips.isEmpty) return 0;
    final s = starts;
    return s.last + clips.last.length;
  }

  /// (clip index, local time) at timeline time [t].
  (int, double) clipAt(double t) {
    final s = starts;
    for (var i = clips.length - 1; i >= 0; i--) {
      if (t >= s[i] - 1e-6) {
        return (i, (t - s[i]).clamp(0.0, clips[i].length));
      }
    }
    return (0, 0);
  }

  double get aspect {
    const fixed = {
      '9:16': 9 / 16,
      '16:9': 16 / 9,
      '1:1': 1.0,
      '4:5': 4 / 5,
      '3:4': 3 / 4,
      '4:3': 4 / 3,
      '2:1': 2.0,
      '2.35:1': 2.35,
      '5.8in': 1125 / 2436,
    };
    return fixed[ratio] ?? _originalAspect ?? 9 / 16;
  }

  double? _originalAspect;
  void setOriginalAspect(double? value) => _originalAspect = value;

  bool get isSinglePhoto =>
      clips.length == 1 &&
      clips.first.kind == 'image' &&
      audios.isEmpty &&
      pips.isEmpty &&
      segments.isEmpty &&
      clips.first.keys.isEmpty &&
      !overlays.any((o) => o.isDynamic) &&
      clips.first.motion == 'none' &&
      clips.first.animIn == 'none' &&
      clips.first.animOut == 'none' &&
      !const {'shake', 'flash'}.contains(clips.first.effect);

  String snapshot() => jsonEncode({
        'clips': [for (final c in clips) c.toJson()],
        'overlays': [for (final o in overlays) o.toJson()],
        'audios': [for (final a in audios) a.toJson()],
        'pips': [for (final x in pips) x.toJson()],
        'segments': [for (final x in segments) x.toJson()],
        'ratio': ratio,
        'resolution': resolution,
        'fps': fps,
        'quality': quality,
        'background': background,
        'blur': blur,
        'muteOriginal': muteOriginal,
        'coverTime': coverTime,
        'coverPath': coverPath,
        'coverText': coverText,
      });

  void restore(String json) {
    final j = jsonDecode(json) as Map;
    clips
      ..clear()
      ..addAll([for (final c in j['clips'] as List) StudioClip.fromJson(c as Map)]);
    overlays
      ..clear()
      ..addAll([
        for (final o in j['overlays'] as List) StudioOverlay.fromJson(o as Map)
      ]);
    audios
      ..clear()
      ..addAll([for (final a in j['audios'] as List) StudioAudio.fromJson(a as Map)]);
    pips
      ..clear()
      ..addAll([for (final x in (j['pips'] as List?) ?? const []) StudioPip.fromJson(x as Map)]);
    segments
      ..clear()
      ..addAll([
        for (final x in (j['segments'] as List?) ?? const []) StudioSegment.fromJson(x as Map)
      ]);
    ratio = j['ratio'] as String;
    resolution = (j['resolution'] as num).toInt();
    fps = (j['fps'] as num).toInt();
    quality = j['quality'] as String? ?? 'recommended';
    background = j['background'] as String;
    blur = _d(j['blur'], .6);
    muteOriginal = j['muteOriginal'] == true;
    coverTime = (j['coverTime'] as num?)?.toDouble();
    coverPath = j['coverPath'] as String?;
    coverText = j['coverText'] as String? ?? '';
  }
}

// -- colour ----------------------------------------------------------------------------

const _identity = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0];

bool _isIdentity(List<double> m) {
  for (var i = 0; i < 12; i++) {
    if ((m[i] - _identity[i]).abs() > 1e-3) return false;
  }
  return true;
}

/// a ∘ b for 3x4 affine colour matrices (row-major, offset last, 0-1 units).
List<double> mulColor(List<double> a, List<double> b) {
  final out = List<double>.filled(12, 0);
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      var v = 0.0;
      for (var k = 0; k < 3; k++) {
        v += a[r * 4 + k] * b[k * 4 + c];
      }
      out[r * 4 + c] = v;
    }
    var o = a[r * 4 + 3];
    for (var k = 0; k < 3; k++) {
      o += a[r * 4 + k] * b[k * 4 + 3];
    }
    out[r * 4 + 3] = o;
  }
  return out;
}

List<double> _saturation(double s) {
  final lr = .2126 * (1 - s), lg = .7152 * (1 - s), lb = .0722 * (1 - s);
  return [lr + s, lg, lb, 0, lr, lg + s, lb, 0, lr, lg, lb + s, 0];
}

List<double> _contrast(double k, [double lift = 0]) {
  final o = .5 * (1 - k) + lift;
  return [k, 0, 0, o, 0, k, 0, o, 0, 0, k, o];
}

List<double> _scale(double r, double g, double b, [double o = 0]) =>
    [r, 0, 0, o, 0, g, 0, o, 0, 0, b, o];

List<double> _offset(double r, double g, double b) =>
    [1, 0, 0, r, 0, 1, 0, g, 0, 0, 1, b];

List<double> _hue(double degrees) {
  final a = degrees * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  const lr = .213, lg = .715, lb = .072;
  return [
    lr + c * (1 - lr) + s * -lr,
    lg + c * -lg + s * -lg,
    lb + c * -lb + s * (1 - lb),
    0,
    lr + c * -lr + s * .143,
    lg + c * (1 - lg) + s * .14,
    lb + c * -lb + s * -.283,
    0,
    lr + c * -lr + s * -(1 - lr),
    lg + c * -lg + s * lg,
    lb + c * (1 - lb) + s * lb,
    0,
  ];
}

List<double> _chain(List<List<double>> ms) =>
    ms.fold(List.of(_identity), (acc, m) => mulColor(m, acc));

/// Filter presets (CapCut-style names in Phlio's palette).
final Map<String, List<double>> studioFilters = {
  'none': List.of(_identity),
  'vivid': _chain([_saturation(1.35), _contrast(1.08)]),
  'warm': [1.1, 0, 0, .02, 0, 1.02, 0, .01, 0, 0, .86, -.02],
  'cool': [.9, 0, 0, -.01, 0, 1, 0, 0, 0, 0, 1.12, .03],
  'mono': _saturation(0),
  'noir': _chain([_saturation(0), _contrast(1.35)]),
  'fade': _chain([_saturation(.85), _contrast(.82, .08)]),
  'vintage': _chain([
    [.393, .769, .189, 0, .349, .686, .168, 0, .272, .534, .131, 0],
    _contrast(.9, .04),
  ]),
  'cinematic': _chain([
    [1.08, -.04, -.04, 0, -.02, 1, .02, 0, -.06, .04, 1.04, .03],
    _contrast(1.1),
  ]),
  'pastel': _chain([_saturation(.7), _contrast(.88, .06)]),
  'sunset': _chain([_scale(1.08, .97, 1.0), _offset(.03, -.01, .02), _contrast(1.04)]),
  'dream': _chain([_scale(.98, .94, 1.08), _offset(.03, 0, .05), _contrast(.92)]),
  'moody': _chain([_saturation(.8), _contrast(1.12), _offset(-.02, -.01, .02)]),
  'golden': _chain([_scale(1.12, 1.04, .82), _offset(.03, .02, -.02), _saturation(1.1)]),
  'teal': _chain([_scale(.9, 1.02, 1.08), _offset(-.02, .02, .03), _contrast(1.06)]),
};

final studioFilterNames = {
  'none': 'None',
  // Instagram-style looks (GPU shader preview, exact export).
  for (final e in phlioLookNames.entries)
    if (e.key != 'normal') e.key: e.value,
  'vivid': 'Vivid',
  'warm': 'Warm',
  'cool': 'Cool',
  'mono': 'Mono',
  'noir': 'Noir',
  'fade': 'Fade',
  'vintage': 'Vintage',
  'cinematic': 'Cinematic',
  'pastel': 'Pastel',
  'sunset': 'Sunset',
  'dream': 'Dream',
  'moody': 'Moody',
  'golden': 'Golden',
  'teal': 'Teal',
};

/// Adjustment keys, all in -1..1 (vignette/sharpen/grain/fade in 0..1).
const studioAdjustments = [
  ('brightness', 'Brightness'),
  ('contrast', 'Contrast'),
  ('saturation', 'Saturation'),
  ('exposure', 'Exposure'),
  ('temperature', 'Temp'),
  ('tint', 'Tint'),
  ('hue', 'Hue'),
  ('fade', 'Fade'),
  ('vignette', 'Vignette'),
  ('sharpen', 'Sharpen'),
  ('grain', 'Grain'),
];

const studioUnipolar = {'fade', 'vignette', 'sharpen', 'grain'};

List<double> studioColorMatrix(
    String filter, double amount, Map<String, double> adjust) {
  final f = studioFilters[filter] ?? phlioLooks[filter]?.matrix ?? _identity;
  final blended = [
    for (var i = 0; i < 12; i++) _identity[i] + (f[i] - _identity[i]) * amount
  ];
  double a(String k) => adjust[k] ?? 0;
  final steps = <List<double>>[blended];
  if (a('exposure') != 0) {
    final e = math.pow(2, a('exposure')).toDouble();
    steps.add(_scale(e, e, e));
  }
  if (a('temperature') != 0) {
    final t = a('temperature');
    steps.add(_scale(1 + .12 * t, 1 + .02 * t, 1 - .12 * t));
  }
  if (a('tint') != 0) {
    final t = a('tint');
    steps.add(_scale(1 + .05 * t, 1 - .1 * t, 1 + .05 * t));
  }
  if (a('hue') != 0) steps.add(_hue(a('hue') * 60));
  if (a('saturation') != 0) steps.add(_saturation(1 + a('saturation')));
  if (a('contrast') != 0) steps.add(_contrast(1 + .5 * a('contrast')));
  if (a('fade') != 0) steps.add(_contrast(1 - .3 * a('fade'), .15 * a('fade')));
  if (a('brightness') != 0) {
    final b = .22 * a('brightness');
    steps.add(_offset(b, b, b));
  }
  final m = _chain(steps);
  return [for (final v in m) v.clamp(-2.0, 2.0)];
}

/// Full grade: filter/adjust matrix, the look's tone curve (Instagram-style
/// looks from shared/media/phlio_look_data.dart) and vignette/grain.
LookGrade studioGrade(String filter, double amount, Map<String, double> adjust) {
  final look = phlioLooks[filter]?.scaled(amount.clamp(0.0, 1.0));
  return LookGrade(
    matrix: studioColorMatrix(filter, amount, adjust),
    lift: look?.lift ?? const [0, 0, 0],
    gamma: look?.gamma ?? const [1, 1, 1],
    gain: look?.gain ?? const [1, 1, 1],
    vignette: math.max(adjust['vignette'] ?? 0, look?.vignette ?? 0).clamp(0.0, 1.0),
    grain: math.max(adjust['grain'] ?? 0, look?.grain ?? 0).clamp(0.0, 1.0),
  );
}

Map<String, dynamic> _gradePlan(LookGrade g, Map<String, double> adjust) => {
      'vignette': _r(g.vignette),
      'sharpen': (adjust['sharpen'] ?? 0).clamp(0.0, 1.0),
      'grain': _r(g.grain),
      if (!g.toneIsIdentity) 'tone': [for (final v in g.tone) _r(v)],
    };

/// 4x5 matrix for [ColorFilter.matrix] (offsets in 0-255).
List<double> flutterColorMatrix(List<double> m) => [
      m[0], m[1], m[2], 0, m[3] * 255, //
      m[4], m[5], m[6], 0, m[7] * 255,
      m[8], m[9], m[10], 0, m[11] * 255,
      0, 0, 0, 1, 0,
    ];

bool isIdentityColor(List<double> m) => _isIdentity(m);

// -- catalogues --------------------------------------------------------------------------

const studioEffects = [
  ('none', 'None'),
  ('vignette', 'Vignette'),
  ('grain', 'Film grain'),
  ('blur', 'Blur'),
  ('soft', 'Soft glow'),
  ('glitch', 'Glitch'),
  ('rgb_split', 'RGB split'),
  ('vhs', 'VHS'),
  ('film', 'Old film'),
  ('mirror', 'Mirror'),
  ('shake', 'Shake'),
  ('flash', 'Flash'),
  ('pixelate', 'Pixelate'),
];

const studioTransitions = [
  ('none', 'None'),
  ('fade', 'Mix'),
  ('fadeblack', 'Black fade'),
  ('fadewhite', 'Flash white'),
  ('dissolve', 'Dissolve'),
  ('slideleft', 'Slide left'),
  ('slideright', 'Slide right'),
  ('slideup', 'Slide up'),
  ('slidedown', 'Slide down'),
  ('wipeleft', 'Wipe'),
  ('circleopen', 'Circle open'),
  ('circleclose', 'Circle close'),
  ('radial', 'Radial'),
  ('zoomin', 'Zoom in'),
  ('pixelize', 'Pixelize'),
  ('hblur', 'Blur'),
  ('smoothleft', 'Smooth'),
  ('squeezeh', 'Squeeze'),
  ('distance', 'Distance'),
];

const studioRatios = [
  ('original', 'Original'),
  ('9:16', '9:16'),
  ('16:9', '16:9'),
  ('1:1', '1:1'),
  ('4:5', '4:5'),
  ('3:4', '3:4'),
  ('4:3', '4:3'),
  ('2:1', '2:1'),
  ('2.35:1', '2.35:1'),
  ('5.8in', '5.8"'),
];

const studioTextFonts = [
  ('Manrope', 'Classic'),
  ('Quicksand', 'Round'),
  ('serif', 'Serif'),
  ('monospace', 'Mono'),
];

const studioTextStyles = [
  ('plain', 'Plain'),
  ('shadow', 'Shadow'),
  ('box', 'Label'),
  ('outline', 'Outline'),
  ('neon', 'Neon'),
  ('gradient', 'Phlio'),
];

const studioSwatches = [
  0xFFFFFFFF, 0xFF0B0F17, 0xFF8D78FF, 0xFFFFB58F, 0xFFE795D7, 0xFF68D7CD,
  0xFF72A7FF, 0xFFF5636B, 0xFFF6B93B, 0xFF4CD964, 0xFFFF9500, 0xFF5856D6,
];

/// Timeline effects (CapCut's "Video effects" layer).
const studioSegmentEffects = [
  ('vignette', 'Vignette'),
  ('grain', 'Film grain'),
  ('blur', 'Blur'),
  ('glitch', 'Glitch'),
  ('rgb_split', 'RGB split'),
  ('vhs', 'VHS'),
  ('film', 'Old film'),
  ('flash', 'Flash'),
  ('dream', 'Dreamy'),
  ('neon', 'Neon pop'),
  ('sepia_flicker', 'Flicker'),
];

const studioVoices = [
  ('none', 'None'),
  ('chipmunk', 'Chipmunk'),
  ('deep', 'Deep'),
  ('robot', 'Robot'),
  ('echo', 'Echo'),
  ('hall', 'Big hall'),
  ('radio', 'Radio'),
  ('megaphone', 'Megaphone'),
  ('vibrato', 'Vibrato'),
  ('tremolo', 'Tremble'),
];

const studioBlends = [
  ('normal', 'Normal'),
  ('screen', 'Screen'),
  ('multiply', 'Multiply'),
  ('overlay', 'Overlay'),
  ('lighten', 'Lighten'),
  ('darken', 'Darken'),
  ('addition', 'Add'),
  ('softlight', 'Soft light'),
  ('hardlight', 'Hard light'),
  ('difference', 'Difference'),
  ('exclusion', 'Exclusion'),
  ('colordodge', 'Color dodge'),
  ('colorburn', 'Color burn'),
];

const studioMasks = [
  ('none', 'None'),
  ('linear', 'Linear'),
  ('mirror', 'Mirror'),
  ('circle', 'Circle'),
  ('rect', 'Rectangle'),
  ('heart', 'Heart'),
  ('star', 'Star'),
];

const studioLoops = [
  ('none', 'None'),
  ('bounce', 'Bounce'),
  ('pulse', 'Pulse'),
  ('wiggle', 'Wiggle'),
  ('float', 'Float'),
  ('blink', 'Blink'),
];

/// Speed curve presets: control points (position 0-1, speed).
const studioCurvePoints = <String, List<(double, double)>>{
  'montage': [(0.0, 1.0), (.3, 4.0), (.5, .5), (.7, 4.0), (1.0, 1.0)],
  'hero': [(0.0, 1.5), (.35, 3.0), (.5, .3), (.65, 3.0), (1.0, 1.5)],
  'bullet': [(0.0, 4.0), (.4, 4.0), (.5, .2), (.6, 4.0), (1.0, 4.0)],
  'jump_cut': [(0.0, 1.0), (.45, 1.0), (.5, 6.0), (.55, 1.0), (1.0, 1.0)],
  'flash_in': [(0.0, 6.0), (.35, 2.0), (1.0, 1.0)],
  'flash_out': [(0.0, 1.0), (.65, 2.0), (1.0, 6.0)],
};

const studioCurveNames = [
  ('montage', 'Montage'),
  ('hero', 'Hero'),
  ('bullet', 'Bullet'),
  ('jump_cut', 'Jump cut'),
  ('flash_in', 'Flash in'),
  ('flash_out', 'Flash out'),
];

/// Curve as constant-speed parts (what the renderer and preview use).
List<List<double>> studioCurve(String name, {int parts = 10}) {
  final pts = studioCurvePoints[name] ?? const [(0.0, 1.0), (1.0, 1.0)];
  double at(double x) {
    for (var i = 0; i < pts.length - 1; i++) {
      final (x0, s0) = pts[i];
      final (x1, s1) = pts[i + 1];
      if (x <= x1) return s0 + (s1 - s0) * ((x - x0) / math.max(1e-6, x1 - x0));
    }
    return pts.last.$2;
  }

  return [
    for (var i = 0; i < parts; i++)
      [i / parts, (i + 1) / parts, double.parse(at((i + .5) / parts).clamp(.1, 10.0).toStringAsFixed(3))]
  ];
}
