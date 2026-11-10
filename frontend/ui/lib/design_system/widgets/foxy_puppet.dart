// Foxy, live: a rigged puppet animated at the display's frame rate.
//
// v2 art: Foxy in his blue button shorts. Nine poses are rigged from the
// reference sheet (scripts/media/foxy_rig/puppet_export_v2.py): neutral
// (bright-eyed, paw out), wave (paw on head, wink), love (blissful), clap
// (full body, mid-stride "let's go"), peek (paws over face), think (glasses),
// sad (turned away), phone (phone to ear) and oops (sheepish sweat).
//
// Foxy's art is a flat illustration, so instead of redrawing him in parts
// he is rigged like a puppet. Each pose (assets/foxy_puppet/foxy_puppet_
// <pose>.png + .json, exported by scripts/media/foxy_rig/puppet_export.py)
// carries a bone rig — head, ears, arm/paw, tail, eyes. Every frame the
// bones are posed procedurally and the image is bent with a textured mesh
// (moving-least-squares rigid deformation of a vertex grid, drawn with
// Canvas.drawVertices). So he really blinks, tilts his head, droops his
// ears, waves, wags and hops — smoothly, on device, from ~1 MB of art.
//
// [FoxyPuppet] takes an [FoxyAct] (what he's doing) plus live inputs:
// `talking` (bobs while his speech bubble types), `lean` (turns toward
// what you type) and one-shot signals for a nod, an "oops" head-shake and a
// hop.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;

/// What Foxy is doing.
enum FoxyAct {
  /// Listening: breathing, blinking, the odd ear twitch.
  idle,

  /// Speaking (pair with `talking: true` while the bubble types).
  talk,

  /// Waving hello with his paw.
  wave,

  /// Eyes shut, head turned away — "I'm not looking".
  peek,

  /// Head tilted, thinking it over.
  think,

  /// Ears down, head low.
  sad,

  /// Bouncing with joy, tail going.
  cheer,

  /// Paws to his face, hearts.
  love,

  /// Celebrating a milestone (full-body "let's go!").
  clap,

  /// Phone to his ear — asking for a number or email.
  phone,

  /// Sheepish grin with a sweat drop — something went wrong.
  oops,

  /// Blissful and content (love pose, no hearts) — welcomes, the agent.
  happy,

  /// Sitting back, relaxed, the odd "z" — quiet empty states.
  chill,

  /// Full-body, ready to go: a light on-the-spot bounce — explore screens.
  ready,

  /// Full-body run cycle (pair with a moving position, e.g. the splash).
  run,

  /// Both arms up, bouncing: "hey!" — the splash finale.
  hooray,

  /// Curled up asleep on his pillow, breathing slowly, Zzz.
  sleep,
}

String _poseOf(FoxyAct act) => switch (act) {
      FoxyAct.idle || FoxyAct.talk => 'neutral',
      FoxyAct.wave => 'wave',
      FoxyAct.peek => 'peek',
      FoxyAct.think => 'think',
      FoxyAct.sad => 'sad',
      FoxyAct.cheer || FoxyAct.clap || FoxyAct.ready || FoxyAct.run => 'clap',
      FoxyAct.hooray => 'hooray',
      FoxyAct.sleep => 'sleep',
      FoxyAct.love || FoxyAct.happy => 'love',
      FoxyAct.chill => 'wave',
      FoxyAct.phone => 'phone',
      FoxyAct.oops => 'oops',
    };

const _poses = [
  'neutral',
  'wave',
  'love',
  'clap',
  'peek',
  'think',
  'sad',
  'phone',
  'oops',
  'hooray',
  'sleep',
];
const _assetDir = 'assets/foxy_puppet';
const _grid = 44;
const _alpha = 1.6;

// ---------------------------------------------------------------------------
// Rig data + mesh

class _Bone {
  _Bone(this.name, this.px, this.py, this.parent);
  final String name;
  final double px, py;
  final int parent;
}

class FoxyRig {
  FoxyRig._(this.image, this.scale, this.rest, this.owner, this.bones, this.eyes,
      this.bounds) {
    _buildMesh();
  }

  final ui.Image image;
  final double scale;
  final Float32List rest; // control points, x/y interleaved
  final Int32List owner; // bone index per point, -1 = anchor
  final List<_Bone> bones;
  final List<List<int>> eyes; // [centre, top, bottom]
  final List<double> bounds;

  late final int vertexCount;
  late final Float32List verts; // rest vertex positions (rig px)
  late final Float32List tex; // texture coordinates (image px)
  late final Float32List pStar;
  late final Float32List weights; // vertexCount × points, normalised
  late final Float32List aX, aY; // w·(p − p*)
  late final Uint16List indices;

  int get pointCount => owner.length;

  static final Map<String, Future<FoxyRig>> _cache = {};

  static Future<FoxyRig> load(String pose) => _cache[pose] ??= _load(pose);

  /// Starts loading every pose (call early, e.g. on the splash screen).
  static void warmUp() {
    for (final pose in _poses) {
      load(pose);
    }
    _Fx.load();
  }

  static Future<FoxyRig> _load(String pose) async {
    final json = jsonDecode(
            await rootBundle.loadString('$_assetDir/foxy_puppet_$pose.json'))
        as Map<String, dynamic>;
    final bytes = await rootBundle.load('$_assetDir/foxy_puppet_$pose.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    final pts = (json['points'] as List).cast<List>();
    final rest = Float32List(pts.length * 2);
    final owner = Int32List(pts.length);
    for (var i = 0; i < pts.length; i++) {
      rest[i * 2] = (pts[i][0] as num).toDouble();
      rest[i * 2 + 1] = (pts[i][1] as num).toDouble();
      owner[i] = (pts[i][2] as num).toInt();
    }
    final bones = [
      for (final b in (json['bones'] as List).cast<Map<String, dynamic>>())
        _Bone(
          b['name'] as String,
          ((b['pivot'] as List)[0] as num).toDouble(),
          ((b['pivot'] as List)[1] as num).toDouble(),
          (b['parent'] as num).toInt(),
        ),
    ];
    final eyes = [
      for (final e in (json['eyes'] as List).cast<Map<String, dynamic>>())
        [(e['c'] as num).toInt(), (e['t'] as num).toInt(), (e['b'] as num).toInt()],
    ];
    final bounds = [
      for (final v in json['bounds'] as List) (v as num).toDouble(),
    ];
    return FoxyRig._(image, (json['scale'] as num).toDouble(), rest, owner,
        bones, eyes, bounds);
  }

  void _buildMesh() {
    const pad = 24.0;
    final x0 = math.max(0.0, bounds[0] - pad), y0 = math.max(0.0, bounds[1] - pad);
    final x1 = math.min(320.0, bounds[2] + pad), y1 = math.min(320.0, bounds[3] + pad);
    vertexCount = _grid * _grid;
    final k = pointCount;
    verts = Float32List(vertexCount * 2);
    tex = Float32List(vertexCount * 2);
    pStar = Float32List(vertexCount * 2);
    weights = Float32List(vertexCount * k);
    aX = Float32List(vertexCount * k);
    aY = Float32List(vertexCount * k);
    for (var r = 0; r < _grid; r++) {
      for (var c = 0; c < _grid; c++) {
        final i = r * _grid + c;
        final vx = x0 + (x1 - x0) * c / (_grid - 1);
        final vy = y0 + (y1 - y0) * r / (_grid - 1);
        verts[i * 2] = vx;
        verts[i * 2 + 1] = vy;
        tex[i * 2] = vx * scale;
        tex[i * 2 + 1] = vy * scale;
        var sum = 0.0;
        for (var j = 0; j < k; j++) {
          final dx = rest[j * 2] - vx, dy = rest[j * 2 + 1] - vy;
          final w = 1 / (math.pow(dx * dx + dy * dy, _alpha) + 1e-6);
          weights[i * k + j] = w.toDouble();
          sum += w;
        }
        var px = 0.0, py = 0.0;
        for (var j = 0; j < k; j++) {
          final w = weights[i * k + j] / sum;
          weights[i * k + j] = w;
          px += w * rest[j * 2];
          py += w * rest[j * 2 + 1];
        }
        pStar[i * 2] = px;
        pStar[i * 2 + 1] = py;
        for (var j = 0; j < k; j++) {
          final w = weights[i * k + j];
          aX[i * k + j] = w * (rest[j * 2] - px);
          aY[i * k + j] = w * (rest[j * 2 + 1] - py);
        }
      }
    }
    final idx = <int>[];
    for (var r = 0; r < _grid - 1; r++) {
      for (var c = 0; c < _grid - 1; c++) {
        final i = r * _grid + c;
        idx..addAll([i, i + 1, i + _grid])..addAll([i + 1, i + _grid + 1, i + _grid]);
      }
    }
    indices = Uint16List.fromList(idx);
  }

  int boneIndex(String name) => bones.indexWhere((b) => b.name == name);

  /// Poses the control points: [pose] maps bone name -> (angle, dx, dy).
  void solve(Map<String, (double, double, double)> pose, double blink, Float32List out) {
    final n = bones.length;
    // World affine per bone: [a, b, c, d, e, f] (x' = a·x + c·y + e).
    final world = List<List<double>?>.filled(n, null);
    List<double> worldOf(int i) {
      final cached = world[i];
      if (cached != null) return cached;
      final bone = bones[i];
      final (ang, dx, dy) = pose[bone.name] ?? (0.0, 0.0, 0.0);
      final co = math.cos(ang), si = math.sin(ang);
      final local = [
        co, si, -si, co,
        bone.px - co * bone.px + si * bone.py + dx,
        bone.py - si * bone.px - co * bone.py + dy,
      ];
      List<double> m = local;
      if (bone.parent >= 0) {
        final p = worldOf(bone.parent);
        m = [
          p[0] * local[0] + p[2] * local[1],
          p[1] * local[0] + p[3] * local[1],
          p[0] * local[2] + p[2] * local[3],
          p[1] * local[2] + p[3] * local[3],
          p[0] * local[4] + p[2] * local[5] + p[4],
          p[1] * local[4] + p[3] * local[5] + p[5],
        ];
      }
      return world[i] = m;
    }

    for (var j = 0; j < pointCount; j++) {
      final x = rest[j * 2], y = rest[j * 2 + 1];
      final b = owner[j];
      if (b < 0) {
        out[j * 2] = x;
        out[j * 2 + 1] = y;
      } else {
        final m = worldOf(b);
        out[j * 2] = m[0] * x + m[2] * y + m[4];
        out[j * 2 + 1] = m[1] * x + m[3] * y + m[5];
      }
    }
    if (blink > 0) {
      final squeeze = 1 - 0.95 * blink.clamp(0.0, 1.0);
      for (final e in eyes) {
        final cx = out[e[0] * 2], cy = out[e[0] * 2 + 1];
        for (final j in [e[1], e[2]]) {
          out[j * 2] = cx + (out[j * 2] - cx) * squeeze;
          out[j * 2 + 1] = cy + (out[j * 2 + 1] - cy) * squeeze;
        }
      }
    }
  }

  /// Moves the mesh so the rest control points land on [q].
  void deform(Float32List q, Float32List out) {
    final k = pointCount;
    for (var i = 0; i < vertexCount; i++) {
      var qx = 0.0, qy = 0.0, c = 0.0, s = 0.0;
      final base = i * k;
      for (var j = 0; j < k; j++) {
        final w = weights[base + j];
        final x = q[j * 2], y = q[j * 2 + 1];
        qx += w * x;
        qy += w * y;
        final ax = aX[base + j], ay = aY[base + j];
        c += ax * x + ay * y;
        s += ax * y - ay * x;
      }
      final norm = math.sqrt(c * c + s * s) + 1e-9;
      final co = c / norm, si = s / norm;
      final dx = verts[i * 2] - pStar[i * 2];
      final dy = verts[i * 2 + 1] - pStar[i * 2 + 1];
      out[i * 2] = co * dx - si * dy + qx;
      out[i * 2 + 1] = si * dx + co * dy + qy;
    }
  }
}

/// Small props drawn around Foxy (exported with the rig art).
class _Fx {
  static final Map<String, ui.Image> images = {};
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= () async {
        for (final name in [
          'sparkle_peach',
          'sparkle_violet',
          'sparkle_yellow',
          'heart',
          'sweat',
          'question',
          'zed',
          'puff',
        ]) {
          final bytes = await rootBundle.load('$_assetDir/foxy_fx_$name.png');
          final codec =
              await ui.instantiateImageCodec(bytes.buffer.asUint8List());
          images[name] = (await codec.getNextFrame()).image;
        }
      }();
}

// ---------------------------------------------------------------------------
// The widget

class FoxyPuppet extends StatefulWidget {
  const FoxyPuppet({
    super.key,
    this.act = FoxyAct.idle,
    this.size = 160,
    this.talking = false,
    this.lean = 0,
    this.nodSignal = 0,
    this.oopsSignal = 0,
    this.hopSignal = 0,
    this.tapToHop = true,
    this.entrance = true,
    this.poseBlend = const Duration(milliseconds: 220),
    this.poofOnSwap = false,
  });

  final FoxyAct act;
  final double size;
  final bool talking;

  /// -1 (turns left) … 1 (turns right).
  final double lean;
  final int nodSignal;
  final int oopsSignal;
  final int hopSignal;
  final bool tapToHop;
  final bool entrance;

  /// Cross-fade between poses. [Duration.zero] snaps cartoon-style (best
  /// paired with [poofOnSwap] and a hop, as on the splash).
  final Duration poseBlend;

  /// A ring of dust puffs bursts out when the pose changes, hiding the cut.
  final bool poofOnSwap;

  @override
  State<FoxyPuppet> createState() => _FoxyPuppetState();
}

class _FoxyPuppetState extends State<FoxyPuppet>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _rand = math.Random();
  final Map<String, FoxyRig> _rigs = {};

  double _t = 0; // seconds since mount
  double _actStart = 0;
  double _nodAt = -10, _oopsAt = -10, _hopAt = -10;
  double _nextBlink = 1.2, _blinkAt = -10;
  double _nextTwitch = 2.5, _twitchAt = -10;
  int _twitchEar = 0;
  double _lean = 0; // smoothed
  double _talk = 0; // smoothed 0..1
  String _pose = 'neutral';
  String? _fromPose;
  double _poseAt = -10;

  @override
  void initState() {
    super.initState();
    FoxyRig.warmUp();
    _pose = _poseOf(widget.act);
    for (final pose in _poses) {
      FoxyRig.load(pose).then((rig) {
        if (!mounted) return;
        setState(() => _rigs[pose] = rig);
      });
    }
    _Fx.load().then((_) {
      if (mounted) _repaint.value++;
    });
    var last = Duration.zero;
    _ticker = createTicker((elapsed) {
      final dt = ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 0.05);
      last = elapsed;
      _t += dt;
      _lean += (widget.lean.clamp(-1.0, 1.0) - _lean) * math.min(1.0, dt * 8);
      _talk += ((widget.talking ? 1.0 : 0.0) - _talk) * math.min(1.0, dt * 10);
      _repaint.value++;
    })
      ..start();
    if (widget.entrance) _hopAt = 0.15;
  }

  @override
  void didUpdateWidget(FoxyPuppet old) {
    super.didUpdateWidget(old);
    if (widget.act != old.act) {
      _actStart = _t;
      final pose = _poseOf(widget.act);
      if (pose != _pose) {
        _fromPose = widget.poseBlend == Duration.zero ? null : _pose;
        _pose = pose;
        _poseAt = _t;
      }
    }
    if (widget.nodSignal != old.nodSignal) _nodAt = _t;
    if (widget.oopsSignal != old.oopsSignal) {
      _oopsAt = _t;
      HapticFeedback.mediumImpact();
    }
    if (widget.hopSignal != old.hopSignal) _hopAt = _t;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _tap() {
    _hopAt = _t;
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = CustomPaint(
      size: Size.square(widget.size),
      painter: _FoxyPainter(this, repaint: _repaint),
    );
    if (widget.tapToHop) {
      child = GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: _tap, child: child);
    }
    if (widget.entrance) {
      child = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: child,
      );
    }
    return Semantics(
      label: 'Foxy',
      image: true,
      child: SizedBox.square(dimension: widget.size, child: child),
    );
  }

  // -------------------------------------------------------------------------
  // Motion

  static double _sn(double t, double period, [double phase = 0]) =>
      math.sin(2 * math.pi * (t / period + phase));

  static double _pulse(double t, double start, double length) {
    if (t < start || t > start + length) return 0;
    return math.sin(math.pi * (t - start) / length);
  }

  static double _ease(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// Bone pose, blink, global transform and props for [act] at time [t].
  _Frame frame(FoxyAct act, String pose) {
    final t = _t;
    final a = t - _actStart; // time in this act
    final bones = <String, (double, double, double)>{};
    void add(String bone, double ang, [double dx = 0, double dy = 0]) {
      final (a0, x0, y0) = bones[bone] ?? (0.0, 0.0, 0.0);
      bones[bone] = (a0 + ang, x0 + dx, y0 + dy);
    }

    var blink = 0.0;
    var gAngle = 0.0, gDx = 0.0, gDy = 0.0, gSx = 1.0, gSy = 1.0;
    final props = <_Prop>[];

    // Idle life, under everything: breathing, blinks, ear twitches.
    final breath = 0.5 - 0.5 * math.cos(2 * math.pi * t / 3.2);
    gSy += 0.012 * breath;
    gSx -= 0.004 * breath;
    add('head', 0.018 * _sn(t, 4.6), 0, 0.8 * _sn(t, 3.2, 0.2));
    if (t > _nextBlink) {
      _blinkAt = t;
      _nextBlink = t + 2.4 + _rand.nextDouble() * 3.2;
      if (_rand.nextDouble() < 0.25) _nextBlink = t + 0.32; // double blink
    }
    blink = math.max(blink, _pulse(t, _blinkAt, 0.16));
    if (t > _nextTwitch) {
      _twitchAt = t;
      _twitchEar = _rand.nextInt(2);
      _nextTwitch = t + 3.5 + _rand.nextDouble() * 4;
    }
    final tw = _pulse(t, _twitchAt, 0.22);
    add('ear$_twitchEar', (_twitchEar == 0 ? -0.22 : 0.22) * tw);

    // Talking: little nods and a bounce on the beat of the words.
    if (_talk > 0.01) {
      add('head', 0.03 * _sn(t, 0.36) * _talk, 0, -1.6 * _sn(t, 0.18).abs() * _talk);
      add('ear0', -0.06 * _sn(t, 0.36) * _talk);
      add('ear1', 0.06 * _sn(t, 0.36, 0.5) * _talk);
    }

    // Turning toward what's being typed.
    add('head', 0.07 * _lean, 4 * _lean, 0);

    // Tail: always alive, a little faster when he's happy.
    final wagSpeed = switch (act) {
      FoxyAct.cheer || FoxyAct.clap || FoxyAct.love => 0.55,
      FoxyAct.sad || FoxyAct.peek || FoxyAct.chill || FoxyAct.sleep => 3.2,
      FoxyAct.run || FoxyAct.hooray => 0.36,
      _ => 1.5,
    };
    add('tail', 0.09 * _sn(t, wagSpeed));

    switch (act) {
      case FoxyAct.idle:
      case FoxyAct.talk:
        // Paw out, presenting; a soft sway.
        add('paw', 0.05 * _sn(t, 2.2));
        add('arm', 0.02 * _sn(t, 2.2, 0.2));
        gAngle += 0.012 * _sn(t, 4.4);
      case FoxyAct.wave:
        // Paw on his head, a cheeky wink: rubs his head, tail swishing.
        final env = _ease(a / 0.25);
        add('paw', 0.06 * _sn(t, 0.34) * env);
        add('arm', 0.025 * _sn(t, 0.34, 0.2) * env);
        add('head', 0.05 * _sn(t, 1.3) * env);
        add('tail', 0.12 * _sn(t, 0.7));
        gAngle += 0.02 * _sn(t, 1.3);
        props.add(_Prop.twinkle('sparkle_peach', 62, 96, t, 0.7, 0, 26));
        props.add(_Prop.twinkle('sparkle_violet', 48, 168, t, 0.7, 0.5, 20));
      case FoxyAct.peek:
        // Paws over his face, trembling a little; ears shy.
        final e = _ease(a / 0.25);
        add('head', 0.012 * _sn(t, 0.16) * e, 0, 2 * e);
        add('ear0', -0.08 * e);
        add('ear1', 0.08 * e);
        add('paw', 0.02 * _sn(t, 0.5) * e);
      case FoxyAct.think:
        // Glasses on, tapping his chin, head tilting.
        final e = _ease(a / 0.45);
        add('head', 0.06 * e + 0.02 * _sn(t, 2.6), 0, 0);
        final tap = _pulse(a % 1.1, 0, 0.22);
        add('paw', -0.07 * tap * e);
        add('arm', -0.02 * tap * e);
        add('ear1', 0.08 * e * _sn(t, 3.0).abs());
        props.add(_Prop('question', 258, 52 + 4 * _sn(t, 1.4),
            0.55 + 0.05 * _sn(t, 1.4), -8 * _sn(t, 2.8), _ease(a / 0.3)));
      case FoxyAct.sad:
        // Turned to the wall: head sinks, ears droop, the odd sniffle.
        final e = _ease(a / 0.6);
        final sniff = _pulse(a % 2.8, 1.6, 0.3);
        add('head', 0.04 * e, 0, 4 * e - 2 * sniff);
        add('ear0', -0.12 * e);
        add('ear1', 0.14 * e + 0.03 * _sn(t, 3.4));
        gSy *= 1 - 0.015 * sniff;
      case FoxyAct.cheer:
      case FoxyAct.clap:
        // Full-body "let's go!": a bouncy run on the spot, pointing ahead.
        final u = a % 0.52;
        final air = u < 0.36 ? math.sin(math.pi * u / 0.36) : 0.0;
        final land = _pulse(u, 0.36, 0.16);
        gDy -= (act == FoxyAct.cheer ? 18 : 12) * air;
        gSx *= 1 + 0.05 * land;
        gSy *= 1 - 0.06 * land + 0.03 * air;
        gAngle += 0.025 * _sn(t, 1.04);
        add('prop', 0.32 * _sn(t, 0.52)); // back leg kicks
        add('arm', -0.05 * air);
        add('paw', 0.08 * _pulse(u, 0.0, 0.2));
        add('ear0', 0.18 * land - 0.08 * air);
        add('ear1', -0.12 * land + 0.06 * air);
        add('tail', 0.16 * _sn(t, 0.52, 0.25));
        if (land > 0) {
          for (final (dx, dy) in [(16.0, -18.0), (24.0, 6.0), (10.0, 22.0)]) {
            props.add(_Prop('sparkle_yellow', 262 + dx, 200 + dy,
                0.22 + 0.22 * land, 0, land));
          }
        }
      case FoxyAct.love:
        // Blissful, paw to his cheek, swaying; floppy ears swing.
        gAngle += 0.045 * _sn(t, 2.2);
        add('head', 0.05 * _sn(t, 2.2, 0.25));
        add('paw', 0.06 * _sn(t, 0.8));
        add('ear0', 0.09 * _sn(t, 2.2, 0.4));
        add('ear1', -0.09 * _sn(t, 2.2, 0.4));
        for (final (ph, x, dx) in [(0.0, 238.0, 20.0), (0.33, 70.0, -15.0), (0.66, 262.0, 5.0)]) {
          props.add(_Prop.rise('heart', t, 2.4, ph, x, 150, x + dx, 30, 0.42, 0.62));
        }
      case FoxyAct.phone:
        // Phone to his ear, nodding along; it buzzes now and then.
        final e = _ease(a / 0.3);
        add('head', 0.035 * _sn(t, 1.1) * e, 0, 1.2 * _sn(t, 0.55).abs() * e);
        add('paw', 0.03 * _sn(t, 1.1, 0.3) * e);
        final buzz = _pulse(a % 2.6, 1.8, 0.45);
        add('paw', 0.025 * _sn(t, 0.06) * buzz);
        add('ear1', 0.06 * _sn(t, 1.6));
        props.add(_Prop.twinkle('sparkle_peach', 30, 128, t, 0.8, 0, 22));
        props.add(_Prop.twinkle('sparkle_yellow', 74, 120, t, 0.8, 0.45, 18));
      case FoxyAct.happy:
        // Content sway, paw to his cheek.
        gAngle += 0.03 * _sn(t, 2.8);
        add('head', 0.04 * _sn(t, 2.8, 0.25));
        add('paw', 0.04 * _sn(t, 1.2));
        add('ear0', 0.06 * _sn(t, 2.8, 0.4));
        add('ear1', -0.06 * _sn(t, 2.8, 0.4));
      case FoxyAct.chill:
        // Sitting back: slow head tilt, lazy paw, a drifting "z".
        add('head', 0.035 * _sn(t, 5.0));
        add('paw', 0.025 * _sn(t, 3.4));
        props.add(_Prop.rise('zed', t, 3.2, 0, 236, 112, 262, 40, 0.3, 0.5));
      case FoxyAct.ready:
        // Light bounce in his stride, tail up.
        final u = a % 0.9;
        final air = u < 0.5 ? math.sin(math.pi * u / 0.5) : 0.0;
        gDy -= 5 * air;
        gSy *= 1 + 0.015 * air;
        add('prop', 0.12 * _sn(t, 0.9));
        add('tail', 0.1 * _sn(t, 0.9, 0.25));
        add('ear0', -0.04 * air);
      case FoxyAct.run:
        // Run cycle: two bounces per stride, back leg kicking, arm pumping,
        // leaning into it; dust puffs kicked up behind.
        const stride = 0.36;
        final u = (t % stride) / stride;
        final air = math.sin(math.pi * ((u * 2) % 1.0));
        gDy -= 7 * air;
        gSy *= 1 - 0.035 * (1 - air) + 0.02 * air;
        gSx *= 1 + 0.025 * (1 - air);
        gAngle += 0.07 + 0.015 * _sn(t, stride);
        add('prop', 0.5 * _sn(t, stride));
        add('arm', 0.09 * _sn(t, stride, 0.5));
        add('paw', 0.1 * _sn(t, stride, 0.5));
        add('head', -0.03 * air, 0, 1.5 * air);
        add('ear0', 0.16 * _sn(t, stride, 0.25));
        add('ear1', -0.12 * _sn(t, stride, 0.25));
        add('tail', 0.22 * _sn(t, stride, 0.35));
        for (final ph in [0.0, 0.5]) {
          final v = ((t / 0.72) + ph) % 1.0;
          final life = math.sin(math.pi * v);
          props.add(_Prop('puff', 96 - 70 * v, 292 - 16 * v,
              0.35 + 0.45 * v, 20 * v, life * (1 - v)));
        }
      case FoxyAct.hooray:
        // Arms up, waving them, little bounces; sparkles all round.
        final e = _ease(a / 0.2);
        final u = (a % 0.6) / 0.6;
        final air = math.sin(math.pi * u);
        gDy -= 6 * air * e;
        gSy *= 1 + 0.02 * air * e;
        add('arm', 0.14 * _sn(t, 0.6) * e);
        add('paw', 0.16 * _sn(t, 0.3) * e);
        add('prop', -0.14 * _sn(t, 0.6, 0.15) * e);
        add('head', 0.05 * _sn(t, 1.2) * e);
        add('ear1', 0.08 * _sn(t, 0.6, 0.3));
        add('tail', 0.2 * _sn(t, 0.6));
        props.add(_Prop.twinkle('sparkle_peach', 46, 70, t, 0.8, 0, 28));
        props.add(_Prop.twinkle('sparkle_violet', 262, 64, t, 0.8, 0.3, 24));
        props.add(_Prop.twinkle('sparkle_yellow', 272, 236, t, 0.8, 0.6, 22));
        props.add(_Prop.twinkle('sparkle_peach', 30, 236, t, 0.8, 0.85, 18));
      case FoxyAct.sleep:
        // Deep, slow breaths; a lazy tail; Zzz drifting up.
        final br = 0.5 - 0.5 * math.cos(2 * math.pi * t / 3.6);
        gSy *= 1 + 0.02 * br;
        gSx *= 1 + 0.006 * br;
        add('head', 0.02 * br, 0, 1.4 * br);
        add('tail', 0.05 * _sn(t, 4.0));
        for (final ph in [0.0, 0.5]) {
          props.add(_Prop.rise('zed', t, 3.6, ph, 236, 130, 266, 34, 0.26, 0.52));
        }
      case FoxyAct.oops:
        // Sheepish grin, rocking, sweat drop sliding down.
        final e = _ease(a / 0.25);
        add('head', 0.05 * _sn(t, 1.0) * e);
        add('ear0', -0.08 * e);
        add('ear1', 0.06 * e);
        add('paw', 0.05 * _sn(t, 0.3) * e);
        add('tail', 0.12 * _sn(t, 0.7));
        final u = (a % 1.6) / 1.6;
        props.add(_Prop('sweat', 248, 96 + 22 * _ease(u), 0.5, 0,
            e * (u < 0.8 ? 1 : (1 - u) / 0.2)));
    }

    // One-shots on top.
    final nod = t - _nodAt;
    if (nod < 0.6) {
      final n = _pulse(nod, 0, 0.3) + 0.6 * _pulse(nod, 0.3, 0.3);
      add('head', -0.04 * n, 0, 7 * n);
    }
    final oops = t - _oopsAt;
    if (oops < 0.7) {
      final decay = 1 - oops / 0.7;
      add('head', 0.09 * _sn(oops, 0.18) * decay);
      add('ear0', -0.2 * decay);
      add('ear1', 0.2 * decay);
      props.add(_Prop('sweat', 236, 92 + 18 * _ease(oops / 0.7), 0.5, 0, decay));
    }
    final hop = t - _hopAt;
    if (hop < 0.6) {
      final lift = hop < 0.42 ? math.sin(math.pi * hop / 0.42) : 0.0;
      final squash = hop >= 0.42 ? math.sin(math.pi * (hop - 0.42) / 0.18) : 0.0;
      final crouch = hop < 0.08 ? math.sin(math.pi * hop / 0.08) : 0.0;
      gDy -= 22 * lift;
      gSy *= 1 - 0.06 * (squash + crouch) + 0.04 * lift;
      gSx *= 1 + 0.05 * (squash + crouch) - 0.02 * lift;
    }
    // Pose change: a quick squash as he "snaps" into the new pose.
    final snap = t - _poseAt;
    if (widget.poofOnSwap && snap < 0.45) {
      final v = snap / 0.45;
      for (var k = 0; k < 7; k++) {
        final ang = 2 * math.pi * k / 7 + 0.4;
        final r = 70 + 70 * _ease(v);
        props.add(_Prop('puff', 160 + r * math.cos(ang), 190 + 0.8 * r * math.sin(ang),
            (1.15 - 0.5 * v) * (k.isEven ? 1.0 : 0.8), 40 * v, 1 - v));
      }
    }
    if (snap < 0.3) {
      final s = math.sin(math.pi * snap / 0.3);
      gSy *= 1 - 0.05 * s;
      gSx *= 1 + 0.04 * s;
    }
    return _Frame(bones, blink, gAngle, gDx, gDy, gSx, gSy, props);
  }
}

class _Frame {
  _Frame(this.bones, this.blink, this.angle, this.dx, this.dy, this.sx, this.sy,
      this.props);
  final Map<String, (double, double, double)> bones;
  final double blink, angle, dx, dy, sx, sy;
  final List<_Prop> props;
}

class _Prop {
  _Prop(this.image, this.x, this.y, this.scale, this.angleDeg, this.alpha);

  factory _Prop.twinkle(String image, double x, double y, double t,
      double period, double phase, double size) {
    final u = ((t / period) + phase) % 1.0;
    final life = u < 0.5 ? math.sin(math.pi * u / 0.5) : 0.0;
    return _Prop(image, x, y, (size / 64) * (0.15 + 1.0 * life),
        15 * math.sin(2 * math.pi * u), math.min(1.0, life / 0.15));
  }

  factory _Prop.rise(String image, double t, double period, double phase,
      double x0, double y0, double x1, double y1, double s0, double s1) {
    final u = ((t / period) + phase) % 1.0;
    final grow = _FoxyPuppetState._ease(u / 0.15);
    final shrink = _FoxyPuppetState._ease((1 - u) / 0.35);
    final x = x0 + (x1 - x0) * u + 10 * math.sin(2 * math.pi * u * 1.5);
    return _Prop(image, x, y0 + (y1 - y0) * u, (s0 + (s1 - s0) * u) * grow * shrink,
        0, grow * shrink > 0.05 ? 1 : 0);
  }

  final String image;
  final double x, y, scale, angleDeg, alpha;
}

class _FoxyPainter extends CustomPainter {
  _FoxyPainter(this.state, {required Listenable repaint})
      : super(repaint: repaint);

  final _FoxyPuppetState state;
  final Map<String, Float32List> _q = {};
  final Map<String, Float32List> _pos = {};

  @override
  void paint(Canvas canvas, Size size) {
    final act = state.widget.act;
    final pose = state._pose;
    final rig = state._rigs[pose];
    if (rig == null) return;
    final f = state.frame(act, pose);
    final s = size.width / 320;
    canvas.save();
    canvas.scale(s);
    // Global transform about his feet.
    const px = 160.0, py = 300.0;
    canvas.translate(px + f.dx, py + f.dy);
    canvas.rotate(f.angle);
    canvas.scale(f.sx, f.sy);
    canvas.translate(-px, -py);

    // Cross-fade from the previous pose for a beat.
    final from = state._fromPose;
    final blend = state.widget.poseBlend.inMicroseconds / 1e6;
    final fade = blend <= 0
        ? 1.0
        : ((state._t - state._poseAt) / blend).clamp(0.0, 1.0);
    if (from != null && fade < 1) {
      final old = state._rigs[from];
      if (old != null) _drawRig(canvas, old, from, f, 1 - fade);
      _drawRig(canvas, rig, pose, f, fade);
    } else {
      _drawRig(canvas, rig, pose, f, 1);
    }

    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final p in f.props) {
      final img = _Fx.images[p.image];
      if (img == null || p.alpha <= 0.01 || p.scale <= 0.01) continue;
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.angleDeg * math.pi / 180);
      canvas.scale(p.scale);
      paint.color = Color.fromRGBO(255, 255, 255, p.alpha.clamp(0.0, 1.0));
      canvas.drawImage(
          img, Offset(-img.width / 2, -img.height / 2), paint);
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawRig(Canvas canvas, FoxyRig rig, String pose, _Frame f, double opacity) {
    final q = _q[pose] ??= Float32List(rig.pointCount * 2);
    final pos = _pos[pose] ??= Float32List(rig.vertexCount * 2);
    rig.solve(f.bones, f.blink, q);
    rig.deform(q, pos);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: rig.tex,
      indices: rig.indices,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..shader = ImageShader(rig.image, TileMode.clamp, TileMode.clamp,
          Matrix4.identity().storage);
    if (opacity < 1) {
      canvas.saveLayer(null,
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
      canvas.restore();
    } else {
      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    }
    vertices.dispose();
  }

  @override
  bool shouldRepaint(_FoxyPainter old) => true;
}
