// Phlio avatar — rendering. A real-time low-poly 3D renderer on Canvas:
//
//   1. The character mesh (avatar_character.dart) is built once per look
//      and cached.
//   2. Every frame each triangle is animated (breathing, head sway,
//      blinking), turned to the current yaw (drag to spin the turntable),
//      projected with perspective, back-face culled and sorted far → near.
//   3. Toon lighting per face: a key light quantised into three bands with
//      cool violet shadows, a violet rim light on the silhouette, sheen on
//      hair and metal, see-through tinted glass.
//   4. All triangles go to the GPU in one drawVertices call.
//   5. Shaders: `avatar_stage.frag` paints the studio backdrop (gradient,
//      spotlight, floor, contact shadow, shards) and `avatar_shade.frag`
//      post-processes the figure (edge smoothing, ink outline, inner edge
//      line, saturation). Without shader support both fall back to plain
//      drawing.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import 'avatar_character.dart';
import 'avatar_mesh.dart';

export 'avatar_character.dart';

/// Your saved avatar (null until you make one).
final myAvatarProvider = FutureProvider<AvatarConfig?>((ref) async {
  final res = await getIt<ApiClient>().dio.get<dynamic>('/social/avatar');
  final a = (res.data as Map)['avatar'];
  return a is Map ? AvatarConfig(Map<String, dynamic>.from(a)) : null;
});

Future<void> saveMyAvatar(AvatarConfig config) =>
    getIt<ApiClient>().dio.put<dynamic>('/social/avatar', data: config.toJson());

/// How much of the character the camera shows.
enum AvatarFraming { full, bust, head }

const _backdrops = <String, (Color, Color)>{
  'studio': (Color(0xFF2BC4C9), Color(0xFFA9F0EB)),
  'gradient': (Color(0xFF8D78FF), Color(0xFFE795D7)),
  'sunset': (Color(0xFFFF8F5E), Color(0xFFFFD9A8)),
  'mint': (Color(0xFF3CC4A3), Color(0xFFC9F7DD)),
  'night': (Color(0xFF141A3A), Color(0xFF3E3282)),
};

// Mesh cache (built meshes by look).
final _meshes = <String, List<Tri>>{};
List<Tri> _meshFor(AvatarConfig cfg) {
  final key = cfg.key;
  final hit = _meshes.remove(key);
  if (hit != null) return _meshes[key] = hit;
  final mesh = buildAvatarMesh(cfg);
  _meshes[key] = mesh;
  if (_meshes.length > 48) _meshes.remove(_meshes.keys.first);
  return mesh;
}

class _Shaders {
  static ui.FragmentProgram? stage, shade;
  static Future<void>? loading;
  static Future<void> load() => loading ??= () async {
        try {
          stage = await ui.FragmentProgram.fromAsset('assets/shaders/avatar_stage.frag');
          shade = await ui.FragmentProgram.fromAsset('assets/shaders/avatar_shade.frag');
        } catch (_) {}
      }();
}

/// The 3D avatar. [size] is the width (the box is 6:7). Drag to turn it
/// when [interactive].
class AvatarFigure extends StatefulWidget {
  const AvatarFigure({
    required this.config,
    super.key,
    this.size = 160,
    this.animate = true,
    this.background = true,
    this.framing = AvatarFraming.full,
    this.interactive = false,
    this.yaw = -.38,
  });

  final AvatarConfig config;
  final double size;
  final bool animate, background, interactive;
  final AvatarFraming framing;

  /// Starting turn (radians; 0 faces the camera). Default is a ¾ view.
  final double yaw;

  @override
  State<AvatarFigure> createState() => _AvatarFigureState();
}

class _AvatarFigureState extends State<AvatarFigure> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0, _spin = 0, _velocity = 0;
  late double _yaw = widget.yaw;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.animate) _ticker.start();
    if (_Shaders.stage == null) {
      _Shaders.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _t += dt;
    // Fling: keep turning, slowing down.
    if (_velocity.abs() > .01) {
      _yaw += _velocity * dt;
      _velocity *= math.pow(.04, dt).toDouble();
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AvatarFigure old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size, h = widget.size * 7 / 6;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final mesh = _meshFor(widget.config);
    final bg = widget.background ? _backdrops[widget.config.s('background')] : null;
    Widget figure = CustomPaint(
      size: Size(w, h),
      painter: _FigurePainter(mesh, _t, _yaw + _spin, widget.framing, shadow: bg == null && widget.framing == AvatarFraming.full),
    );
    final shade = _Shaders.shade;
    if (shade != null && ui.ImageFilter.isShaderFilterSupported) {
      final s = shade.fragmentShader();
      final values = [w * dpr, h * dpr, math.max(1.4, w * dpr / 260), .13, .1, .2, .9];
      for (var i = 0; i < values.length; i++) {
        s.setFloat(i, values[i]);
      }
      figure = ImageFiltered(imageFilter: ui.ImageFilter.shader(s), child: figure);
    }
    Widget stack = SizedBox(
      width: w,
      height: h,
      child: Stack(fit: StackFit.expand, children: [
        if (bg != null)
          CustomPaint(painter: _StagePainter(bg.$1, bg.$2, _t, widget.framing == AvatarFraming.full ? .9 : -1)),
        figure,
      ]),
    );
    if (bg != null) stack = ClipRRect(borderRadius: BorderRadius.circular(w * .06), child: stack);
    if (!widget.interactive) return stack;
    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => _yaw += d.delta.dx / w * 4),
      onHorizontalDragEnd: (d) => _velocity = (d.primaryVelocity ?? 0) / w * 4,
      onDoubleTap: () => setState(() {
        _velocity = 0;
        _yaw = widget.yaw;
      }),
      child: stack,
    );
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.top, this.bottom, this.t, this.floor);
  final Color top, bottom;
  final double t, floor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final program = _Shaders.stage;
    if (program == null) {
      canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(rect));
      return;
    }
    final s = program.fragmentShader();
    final shadow = Color.lerp(top, const Color(0xFF4A2E8F), .7)!;
    final v = [size.width, size.height, t, top.r, top.g, top.b, bottom.r, bottom.g, bottom.b, floor, shadow.r, shadow.g, shadow.b];
    for (var i = 0; i < v.length; i++) {
      s.setFloat(i, v[i]);
    }
    canvas.drawRect(rect, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.t != t || old.top != top || old.bottom != bottom || old.floor != floor;
}

class _FigurePainter extends CustomPainter {
  _FigurePainter(this.mesh, this.t, this.yaw, this.framing, {this.shadow = false});
  final List<Tri> mesh;
  final double t, yaw;
  final AvatarFraming framing;
  final bool shadow;

  static const _light = V3(-.45, .66, .6);
  static const _camDist = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    final (top, bottom) = switch (framing) {
      AvatarFraming.head => (4.55, 3.0),
      AvatarFraming.bust => (4.6, 2.05),
      AvatarFraming.full => (4.62, -.06),
    };
    final yc = (top + bottom) / 2;
    final k = size.height * .9 / (top - bottom);
    final cx = size.width / 2, cyScreen = size.height / 2;
    final light = _light.unit;
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    const pitch = .06;
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    // Animation.
    final breathe = math.sin(t * 2.1) * .018;
    final headYaw = math.sin(t * .55) * .06;
    final cycle = t % 4.3;
    final lid = cycle > 4.15 ? (((cycle - 4.15) / .15 - .5).abs() * 2).clamp(.08, 1.0) : 1.0;
    final cosH = math.cos(headYaw), sinH = math.sin(headYaw);
    const headPivot = V3(0, 3.1, 0);

    V3 animate(V3 v, Tri tri) {
      var p = v;
      switch (tri.group) {
        case gBody:
          p = V3(p.x, p.y + breathe * .6, p.z);
        case gHead:
        case gEyes:
          if (tri.group == gEyes && tri.pivot != null) {
            p = V3(p.x, tri.pivot!.y + (p.y - tri.pivot!.y) * lid, p.z);
          }
          final d = p - headPivot;
          p = headPivot + V3(d.x * cosH + d.z * sinH, d.y, -d.x * sinH + d.z * cosH) + V3(0, breathe, 0);
      }
      return p;
    }

    V3 view(V3 p) {
      // Turn around the vertical axis, then a slight downward look.
      final x = p.x * cosY + p.z * sinY;
      final z = -p.x * sinY + p.z * cosY;
      final y = p.y - yc;
      return V3(x, y * cosP - z * sinP, y * sinP + z * cosP);
    }

    final faces = <(double depth, V3 a, V3 b, V3 c, Color color)>[];
    for (final tri in mesh) {
      final a = view(animate(tri.a, tri)), b = view(animate(tri.b, tri)), c = view(animate(tri.c, tri));
      var n = (b - a).cross(c - a);
      final len = n.length;
      if (len < 1e-9) continue;
      n = n * (1 / len);
      final centroid = (a + b + c) * (1 / 3);
      final toCam = V3(-centroid.x, -centroid.y, _camDist - centroid.z);
      if (n.dot(toCam) <= 0) {
        if (!tri.twoSided) continue;
        n = n * -1;
      }
      faces.add((centroid.z + tri.bias, a, b, c, _shade(tri, n, light)));
    }
    faces.sort((p, q) => p.$1.compareTo(q.$1));

    if (shadow) {
      final foot = _project(view(const V3(0, 0, 0)), k, cx, cyScreen);
      canvas.drawOval(Rect.fromCenter(center: foot, width: size.width * .5, height: size.width * .1),
          Paint()
            ..color = const Color(0x40311A5E)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * .02));
    }

    final pos = Float32List(faces.length * 6);
    final cols = Int32List(faces.length * 3);
    var i = 0, j = 0;
    for (final f in faces) {
      for (final v in [f.$2, f.$3, f.$4]) {
        final o = _project(v, k, cx, cyScreen);
        pos[i++] = o.dx;
        pos[i++] = o.dy;
        cols[j++] = f.$5.toARGB32();
      }
    }
    canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: cols), BlendMode.dst, Paint());
  }

  Offset _project(V3 v, double k, double cx, double cy) {
    final s = _camDist / (_camDist - v.z);
    return Offset(cx + v.x * k * s, cy - v.y * k * s);
  }

  /// Toon lighting for one face.
  Color _shade(Tri tri, V3 n, V3 light) {
    final base = tri.color;
    if (tri.kind == kUnlit) return base;
    final diff = n.dot(light);
    // Skin gets gentler bands so faces stay readable; everything else
    // gets the full cel-shaded contrast.
    final band = tri.kind == kSkin
        ? (diff > .25 ? 1.0 : (diff > -.15 ? .9 : .8))
        : (diff > .45 ? 1.0 : (diff > .05 ? .82 : .66));
    double r = base.r * band, g = base.g * band, b = base.b * band;
    // Cool violet shadows.
    final cool = (1 - band) * (tri.kind == kSkin ? .9 : 1.4);
    r = r * (1 - cool * .18);
    g = g * (1 - cool * .22);
    b = math.min(1, b * (1 + cool * .25) + cool * .03);
    // Violet rim light on the edges, stronger on the left.
    final rim = math.pow(1 - n.z.clamp(0.0, 1.0), 2.4).toDouble() * (.55 + .45 * math.max(0, -n.x));
    final rimAmt = (rim * .6).clamp(0.0, .6);
    r += (.68 - r) * rimAmt;
    g += (.44 - g) * rimAmt;
    b += (1.0 - b) * rimAmt;
    // Highlights.
    if (tri.kind == kHair && diff > .72) {
      r += (1 - r) * .14;
      g += (1 - g) * .14;
      b += (1 - b) * .16;
    }
    if (tri.kind == kMetal) {
      final spec = diff > .6 ? .4 : 0.0;
      r += (1 - r) * spec;
      g += (1 - g) * spec;
      b += (1 - b) * spec * .7;
    }
    final a = base.a;
    if (tri.kind == kGlass && diff > .7) {
      r += (1 - r) * .3;
      g += (1 - g) * .3;
      b += (1 - b) * .3;
    }
    return Color.from(alpha: a, red: r.clamp(0.0, 1.0), green: g.clamp(0.0, 1.0), blue: b.clamp(0.0, 1.0));
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.t != t || old.yaw != yaw || old.mesh != mesh || old.framing != framing;
}
