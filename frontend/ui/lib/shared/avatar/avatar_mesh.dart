// Phlio avatar — low-poly 3D character meshes, built procedurally from an
// avatar config.
//
// Stylised, faceted characters (chunky proportions, angular hair locks,
// flat-shaded planes), built from a handful of primitives:
//
//   * ellipsoids (head, hands, hair caps, buns, afros)
//   * lofts — rings along a path (torso, limbs, coats, skirts, tails)
//   * wedges (hair locks, beard tufts, spikes)
//   * flat decals just in front of the face (eyes, brows, mouth)
//
// Every triangle is oriented outwards when it's created, carries its base
// colour, a material kind (matte / hair / unlit / glass / metal) and an
// animation group (legs, upper body, head, eyes) so the renderer can
// breathe and blink without rebuilding the mesh. avatar_figure.dart draws
// it: rotation, perspective, back-face culling, painter's sort, toon
// lighting with a violet rim light, then GPU shaders for the stage and the
// outline / anti-aliasing pass.

import 'dart:math' as math;
import 'dart:ui';

class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get unit {
    final l = length;
    return l < 1e-9 ? const V3(0, 1, 0) : V3(x / l, y / l, z / l);
  }
}

/// Materials.
const kMatte = 0, kHair = 1, kUnlit = 2, kGlass = 3, kMetal = 4, kSkin = 5;

/// Animation groups.
const gStatic = 0, gBody = 1, gHead = 2, gEyes = 3;

class Tri {
  Tri(this.a, this.b, this.c, this.color, this.kind, this.group, {this.pivot, this.twoSided = false, this.bias = 0});
  final V3 a, b, c;

  /// Added to the depth when sorting (decals and front locks draw on top).
  final double bias;
  final Color color;
  final int kind, group;
  final V3? pivot; // blink pivot for eye parts
  final bool twoSided;
}

class MeshBuilder {
  final tris = <Tri>[];
  int group = gStatic;

  /// Adds a triangle facing [out] (a direction) — winding is fixed here.
  /// Depth bias for everything added while it's set (see [Tri.bias]).
  double bias = 0;

  void tri(V3 a, V3 b, V3 c, Color color, {V3? out, int kind = kMatte, V3? pivot, bool twoSided = false, double? bias}) {
    if (out != null) {
      final n = (b - a).cross(c - a);
      if (n.dot(out) < 0) {
        final t = b;
        b = c;
        c = t;
      }
    }
    tris.add(Tri(a, b, c, color, kind, group, pivot: pivot, twoSided: twoSided, bias: bias ?? this.bias));
  }

  /// Closed shape: faces point away from [center].
  void triFrom(V3 a, V3 b, V3 c, V3 center, Color color, {int kind = kMatte}) =>
      tri(a, b, c, color, out: (a + b + c) * (1 / 3) - center, kind: kind);

  void quad(V3 a, V3 b, V3 c, V3 d, V3 center, Color color, {int kind = kMatte}) {
    triFrom(a, b, c, center, color, kind: kind);
    triFrom(a, c, d, center, color, kind: kind);
  }

  // ------------------------------------------------------------ primitives

  /// Faceted ellipsoid. [from]/[to] limit the polar range (0 = top, pi =
  /// bottom) for caps; [deform] reshapes each point (unit-sphere coords in,
  /// offset in model units out).
  void ellipsoid(V3 c, double rx, double ry, double rz, Color color,
      {int lat = 6,
      int lon = 10,
      double from = 0,
      double to = math.pi,
      int kind = kMatte,
      double bias = 0,
      V3 Function(V3 unit, V3 p)? deform,
      bool Function(V3 centroid)? skip}) {
    V3 at(int i, int j) {
      final th = from + (to - from) * i / lat;
      final ph = 2 * math.pi * j / lon + (i.isOdd ? math.pi / lon : 0); // staggered rows = faceted look
      final u = V3(math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph));
      final p = c + V3(u.x * rx, u.y * ry, u.z * rz);
      return deform == null ? p : deform(u, p);
    }

    for (var i = 0; i < lat; i++) {
      for (var j = 0; j < lon; j++) {
        final a = at(i, j), b = at(i, j + 1), d = at(i + 1, j), e = at(i + 1, j + 1);
        for (final t in [
          [a, b, e],
          [a, e, d]
        ]) {
          final cen = (t[0] + t[1] + t[2]) * (1 / 3);
          if ((t[0] - t[1]).length < 1e-6 || (t[1] - t[2]).length < 1e-6 || (t[0] - t[2]).length < 1e-6) continue;
          if (skip != null && skip(cen)) continue;
          tri(t[0], t[1], t[2], color, out: cen - c, kind: kind, bias: bias == 0 ? null : bias);
        }
      }
    }
  }

  /// A ring of [seg] points around [center], perpendicular to [axis].
  List<V3> ring(V3 center, V3 axis, double rx, double rz, int seg, {double twist = 0}) {
    final a = axis.unit;
    final ref = a.z.abs() > .9 ? const V3(0, 1, 0) : const V3(0, 0, 1);
    final u = ref.cross(a).unit;
    final v = a.cross(u).unit;
    return [
      for (var k = 0; k < seg; k++)
        center + u * (rx * math.cos(2 * math.pi * k / seg + twist)) + v * (rz * math.sin(2 * math.pi * k / seg + twist))
    ];
  }

  /// Rings along a path: [(centre, rx, rz)], capped at both ends.
  void loft(List<(V3, double, double)> path, Color color,
      {int seg = 7, bool capStart = true, bool capEnd = true, int kind = kMatte, List<Color>? colors}) {
    final rings = <List<V3>>[];
    for (var i = 0; i < path.length; i++) {
      final prev = path[math.max(0, i - 1)].$1, next = path[math.min(path.length - 1, i + 1)].$1;
      rings.add(ring(path[i].$1, next - prev, path[i].$2, path[i].$3, seg));
    }
    for (var i = 0; i < rings.length - 1; i++) {
      final mid = (path[i].$1 + path[i + 1].$1) * .5;
      final col = colors == null ? color : colors[math.min(i, colors.length - 1)];
      for (var k = 0; k < seg; k++) {
        quad(rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k], mid, col, kind: kind);
      }
    }
    void cap(List<V3> r, V3 c, V3 outward) {
      for (var k = 0; k < seg; k++) {
        tri(c, r[k], r[(k + 1) % seg], color, out: outward, kind: kind);
      }
    }

    if (capStart) cap(rings.first, path.first.$1, path.first.$1 - path[1].$1);
    if (capEnd) cap(rings.last, path.last.$1, path.last.$1 - path[path.length - 2].$1);
  }

  /// A pointed lock / spike: base around [root] (perpendicular to [dir]),
  /// tip at [tip]. [width] is the base size.
  void wedge(V3 root, V3 tip, double width, Color color, {int kind = kHair, int sides = 3, double flat = .55}) {
    final axis = tip - root;
    final base = ring(root, axis, width, width * flat, sides, twist: .3);
    final inside = root - axis.unit * (width * 1.5);
    for (var k = 0; k < sides; k++) {
      triFrom(base[k], base[(k + 1) % sides], tip, inside, color, kind: kind);
    }
    for (var k = 1; k < sides - 1; k++) {
      triFrom(base[0], base[k], base[k + 1], tip, color, kind: kind);
    }
  }

  /// Flat polygon decal facing +z (the face front), at depth [z]. Stacked
  /// decals (eye white → iris → pupil) need increasing [bias]: the painter's
  /// sort can't tell layers this close apart once the head turns.
  void decal(List<Offset> pts, double z, Color color, {int kind = kUnlit, V3? pivot, double? bias}) {
    final c = pts.fold(Offset.zero, (s, p) => s + p) / pts.length.toDouble();
    for (var k = 0; k < pts.length; k++) {
      final a = pts[k], b = pts[(k + 1) % pts.length];
      tri(V3(c.dx, c.dy, z), V3(a.dx, a.dy, z), V3(b.dx, b.dy, z), color,
          out: const V3(0, 0, 1), kind: kind, pivot: pivot, bias: bias);
    }
  }

  /// A thick curved stroke (brows, smiles) as a strip of quads facing +z.
  void stroke(List<Offset> pts, double width, double z, Color color, {int kind = kUnlit, V3? pivot, double? bias}) {
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final d = b - a;
      final n = Offset(-d.dy, d.dx) / math.max(d.distance, 1e-6) * (width / 2);
      final p = [a + n, b + n, b - n, a - n].map((o) => V3(o.dx, o.dy, z)).toList();
      tri(p[0], p[1], p[2], color, out: const V3(0, 0, 1), kind: kind, pivot: pivot, bias: bias);
      tri(p[0], p[2], p[3], color, out: const V3(0, 0, 1), kind: kind, pivot: pivot, bias: bias);
    }
  }
}

List<Offset> ellipsePts(Offset c, double rx, double ry, [int n = 10]) =>
    [for (var k = 0; k < n; k++) c + Offset(rx * math.cos(2 * math.pi * k / n), ry * math.sin(2 * math.pi * k / n))];

List<Offset> arcPts(Offset c, double rx, double ry, double a0, double a1, [int n = 8]) =>
    [for (var k = 0; k <= n; k++) c + Offset(rx * math.cos(a0 + (a1 - a0) * k / n), ry * math.sin(a0 + (a1 - a0) * k / n))];
