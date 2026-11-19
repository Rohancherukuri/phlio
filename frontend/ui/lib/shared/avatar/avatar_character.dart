// Phlio avatar — the character: options, the saved config and the mesh
// built from it (see avatar_mesh.dart for the primitives and
// avatar_figure.dart for rendering).
//
// Proportions (model units, y up, feet at 0): legs to 1.7, torso to 2.95,
// head centred at 3.55 — a chunky, stylised figure with an oversized head,
// angular hair locks and faceted planes.

import 'dart:math' as math;
import 'dart:ui';

import 'avatar_mesh.dart';

Color _c(Object? hex, Color fallback) {
  if (hex is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }
  return fallback;
}

String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
Color _dark(Color c, double t) => _mix(c, const Color(0xFF000000), t);
Color _light(Color c, double t) => _mix(c, const Color(0xFFFFFFFF), t);

/// Choices for each part (same lists as the server's).
const avatarOptions = <String, List<String>>{
  'face': ['oval', 'round', 'square', 'heart', 'long', 'angular', 'soft'],
  'hair': [
    'none', 'buzz', 'short', 'swept', 'spiky', 'quiff', 'curly', 'wavy', 'long',
    'bun', 'ponytail', 'afro', 'mohawk', 'side', 'bob', 'pigtails'
  ],
  'eyes': ['round', 'almond', 'sleepy', 'happy', 'wink', 'sharp', 'wide', 'cute'],
  'brows': ['soft', 'straight', 'arched', 'bold', 'angry', 'raised'],
  'mouth': ['smile', 'grin', 'open', 'smirk', 'neutral', 'frown', 'tongue', 'cool'],
  'beard': ['none', 'stubble', 'short', 'full', 'goatee', 'moustache', 'van_dyke', 'chinstrap'],
  'glasses': ['none', 'round', 'square', 'aviator', 'sun', 'round_tint', 'visor'],
  'top': ['tee', 'hoodie', 'shirt', 'jacket', 'kurta', 'dress', 'suit', 'trench', 'track'],
  'accessory': ['none', 'earrings', 'cap', 'beanie', 'headphones', 'bindi', 'nose_ring', 'scarf', 'cape', 'crown'],
  'background': ['studio', 'gradient', 'sunset', 'mint', 'night', 'none'],
};

const avatarSkinTones = [
  Color(0xFFFFE3CC), Color(0xFFF6CFAE), Color(0xFFEDB98F), Color(0xFFE0A47A), Color(0xFFC98B5E),
  Color(0xFFAD7048), Color(0xFF8D5730), Color(0xFF6E4024), Color(0xFF4F2D1A), Color(0xFF3A2216),
];
const avatarHairColors = [
  Color(0xFF1E2230), Color(0xFF2B1B12), Color(0xFF5A3825), Color(0xFF8B5A2B), Color(0xFFD9A441),
  Color(0xFFF1D58A), Color(0xFFB0412E), Color(0xFFEDEDED), Color(0xFF8D78FF), Color(0xFFE76FB7),
  Color(0xFF2FA4A8), Color(0xFF3D6CE0), Color(0xFF53C26B),
];
const avatarEyeColors = [
  Color(0xFF3B2416), Color(0xFF16181D), Color(0xFF5B7F3A), Color(0xFF3F6FB5), Color(0xFF8A6A3C),
  Color(0xFF6B6F7A), Color(0xFFB03A5B), Color(0xFF8D78FF),
];
const avatarClothColors = [
  Color(0xFF2F6FD6), Color(0xFF2A3554), Color(0xFF34C3D0), Color(0xFFF08A2E), Color(0xFF8D78FF), Color(0xFFE795D7),
  Color(0xFFF5636B), Color(0xFF39D98A), Color(0xFFF6D365), Color(0xFF1C1F26), Color(0xFFEDEFF3), Color(0xFF7A4B2A),
];

class AvatarConfig {
  AvatarConfig(Map<String, dynamic>? json) : values = {..._defaults, ...?json};

  static const _defaults = <String, dynamic>{
    'skin': '#E0A47A', 'face': 'oval', 'hair': 'swept', 'hair_color': '#1E2230', 'eyes': 'round',
    'eye_color': '#3B2416', 'brows': 'soft', 'mouth': 'smile', 'beard': 'none', 'glasses': 'none',
    'top': 'suit', 'top_color': '#2F6FD6', 'accent_color': '#F08A2E', 'pants_color': '#2A3554',
    'accessory': 'none', 'background': 'studio', 'blush': true, 'freckles': false,
  };

  final Map<String, dynamic> values;

  String s(String k) {
    final v = '${values[k] ?? _defaults[k]}';
    final allowed = avatarOptions[k];
    return allowed == null || allowed.contains(v) ? v : '${_defaults[k]}';
  }

  Color color(String k, Color fallback) => _c(values[k], fallback);
  bool flag(String k) => values[k] == true;

  AvatarConfig copyWith(String key, Object value) => AvatarConfig({...values, key: value});
  Map<String, dynamic> toJson() => {...values};
  String get key => (values.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join(';');
}

// ---------------------------------------------------------------- the mesh

const _headC = V3(0.0, 3.55, 0);
const _ink = Color(0xFF1B1720);

/// Builds the full character.
List<Tri> buildAvatarMesh(AvatarConfig cfg) {
  final m = MeshBuilder();
  final skin = cfg.color('skin', const Color(0xFFE0A47A));
  final hair = cfg.color('hair_color', const Color(0xFF1E2230));
  final top = cfg.color('top_color', const Color(0xFF2F6FD6));
  final accent = cfg.color('accent_color', const Color(0xFFF08A2E));
  final pants = cfg.color('pants_color', const Color(0xFF2A3554));
  final face = cfg.s('face');

  // Head shape.
  final (rx, ry, rz, jaw, lat, lon) = switch (face) {
    'round' => (.47, .50, .47, .10, 8, 14),
    'square' => (.46, .52, .46, .04, 7, 12),
    'heart' => (.47, .52, .46, .40, 8, 14),
    'long' => (.40, .58, .44, .20, 8, 14),
    'angular' => (.45, .53, .45, .30, 6, 10),
    'soft' => (.45, .51, .46, .18, 9, 16),
    _ => (.44, .52, .46, .24, 8, 14),
  };
  double surfZ(double x, double y) {
    final dy = (y - _headC.y) / ry;
    var w = rx;
    if (dy < 0) w = rx * (1 - jaw * (-dy));
    final q = 1 - (x / w) * (x / w) - dy * dy;
    return rz * math.sqrt(math.max(.05, q));
  }

  V3 headDeform(V3 u, V3 p) {
    var x = p.x, y = p.y, z = p.z;
    if (u.y < 0) {
      x *= 1 - jaw * (-u.y);
      if (face == 'square' && u.y < -.7) y = _headC.y - ry * .78 + (y - _headC.y + ry * .78) * .35;
      if ((face == 'heart' || face == 'angular') && u.y < -.85 && u.z > .2) y -= .04;
      if (u.z > 0) z += .03 * (-u.y); // chin forward a touch
    }
    return V3(x, y, z);
  }

  // ---------------------------------------------------------- legs & shoes
  m.group = gStatic;
  final dress = cfg.s('top') == 'dress';
  final longCoat = cfg.s('top') == 'kurta' || cfg.s('top') == 'trench';
  for (final sx in [-1.0, 1.0]) {
    m.loft([
      (V3(sx * .22, 1.55, 0), .2, .2),
      (V3(sx * .23, .88, .01), .165, .165),
      (V3(sx * .23, .22, 0), .135, .14),
    ], dress ? skin : pants, seg: 7, colors: dress ? [skin, skin] : [pants, _dark(pants, .06)]);
    m.ellipsoid(V3(sx * .23, .12, .08), .17, .13, .27, const Color(0xFF2A2124), lat: 4, lon: 8);
    m.loft([(V3(sx * .23, .06, .08), .175, .28), (V3(sx * .23, .0, .08), .17, .27)], const Color(0xFFEDE6DA), seg: 8); // sole
  }
  // Pelvis.
  m.loft([(const V3(0.0, 1.42, 0), .42, .28), (const V3(0.0, 1.8, 0), .42, .28)], dress ? top : pants, seg: 8);

  // ---------------------------------------------------------- torso & arms
  m.group = gBody;
  final outfit = cfg.s('top');
  final shirt = _light(const Color(0xFFDCE3EE), .2);
  final torsoColor = switch (outfit) { 'suit' => top, _ => top };
  m.loft([
    (const V3(0.0, 1.78, 0), .42, .28),
    (const V3(0.0, 2.3, .01), .56, .34),
    (const V3(0.0, 2.7, 0), .63, .32),
    (const V3(0.0, 2.88, -.02), .27, .2),
  ], torsoColor, seg: 8, colors: outfit == 'track' ? [top, _dark(top, .05), top] : null);
  if (longCoat || dress) {
    // Coat / kurta / skirt flaring below the waist.
    final hemY = dress ? .85 : (outfit == 'kurta' ? .92 : .7);
    m.loft([
      (const V3(0.0, 1.82, 0), .45, .31),
      (V3(0, (1.82 + hemY) / 2, 0), dress ? .58 : .5, dress ? .44 : .35),
      (V3(0, hemY, 0), dress ? .7 : .56, dress ? .52 : .39),
    ], top, seg: 9, capStart: false);
  }
  // Neck.
  m.group = gHead;
  m.loft([(const V3(0.0, 2.8, -.02), .18, .17), (V3(0, _headC.y - .3, -.02), .17, .16)], _dark(skin, .08), seg: 7);
  m.group = gBody;

  // Arms.
  final sleeveLong = outfit != 'tee' && outfit != 'dress';
  final sleeve = switch (outfit) { 'suit' => shirt, _ => top };
  for (final sx in [-1.0, 1.0]) {
    m.ellipsoid(V3(sx * .66, 2.64, 0), .21, .2, .21, outfit == 'dress' ? skin : (outfit == 'suit' ? top : sleeve), lat: 4, lon: 8);
    final upper = [(V3(sx * .7, 2.6, 0), .165, .165), (V3(sx * .8, 2.0, .02), .145, .145)];
    final fore = [(V3(sx * .8, 2.0, .02), .14, .14), (V3(sx * .86, 1.5, .06), .12, .12)];
    if (outfit == 'tee') {
      m.loft([upper[0], (V3(sx * .75, 2.3, .01), .16, .16)], top, seg: 7, capStart: false);
      m.loft([(V3(sx * .75, 2.3, .01), .145, .145), upper[1]], skin, seg: 7, capEnd: false);
      m.loft(fore, skin, seg: 7, capStart: false);
    } else {
      m.loft(upper, outfit == 'dress' ? skin : sleeve, seg: 7, capStart: false,
          colors: outfit == 'track' ? [sleeve] : null);
      m.loft(fore, outfit == 'dress' ? skin : (sleeveLong ? sleeve : skin), seg: 7, capStart: false);
      if (outfit == 'track') {
        // Side stripes down the sleeve.
        m.loft([(V3(sx * .72, 2.58, .0), .17, .07), (V3(sx * .87, 1.56, .06), .125, .06)], accent, seg: 4);
      }
    }
    // Cuff and hand.
    if (sleeveLong) m.loft([(V3(sx * .85, 1.58, .06), .13, .13), (V3(sx * .86, 1.48, .06), .13, .13)], _dark(sleeve, .15), seg: 7);
    m.ellipsoid(V3(sx * .88, 1.34, .08), .15, .17, .13, skin, lat: 4, lon: 7, kind: kSkin);
  }

  // Outfit details on the front of the torso (drawn over it).
  m.bias = .05;
  void frontPanel(List<(double, double)> xy, double zAt, Color c) {
    final pts = [for (final (x, y) in xy) V3(x, y, zAt)];
    final cen = pts.fold(const V3(0.0, 0, 0), (s, p) => s + p) * (1 / pts.length);
    for (var k = 0; k < pts.length; k++) {
      m.tri(cen, pts[k], pts[(k + 1) % pts.length], c, out: const V3(0.0, 0, 1));
    }
  }

  switch (outfit) {
    case 'suit':
      // Shirt V, tie and vest buttons.
      frontPanel([(-.2, 2.84), (.2, 2.84), (0.0, 2.28)], .345, shirt);
      frontPanel([(-.06, 2.8), (.06, 2.8), (.07, 2.38), (0.0, 2.27), (-.07, 2.38)], .355, accent);
      for (final y in [2.18, 2.02, 1.88]) {
        m.ellipsoid(V3(0, y, .345), .028, .028, .02, _dark(top, .35), lat: 3, lon: 5);
      }
    case 'shirt':
      frontPanel([(-.22, 2.86), (0.0, 2.7), (-.07, 2.58)], .34, _light(accent, .3));
      frontPanel([(.22, 2.86), (0.0, 2.7), (.07, 2.58)], .34, _light(accent, .3));
      for (final y in [2.5, 2.3, 2.1, 1.92]) {
        m.ellipsoid(V3(0, y, .34), .022, .022, .015, _dark(top, .3), lat: 3, lon: 5);
      }
    case 'jacket':
      frontPanel([(-.16, 2.84), (.16, 2.84), (.12, 1.82), (-.12, 1.82)], .33, accent);
      frontPanel([(-.24, 2.86), (-.09, 2.86), (-.14, 2.28)], .35, _dark(top, .2));
      frontPanel([(.24, 2.86), (.09, 2.86), (.14, 2.28)], .35, _dark(top, .2));
    case 'hoodie':
      m.bias = 0;
      m.loft([(const V3(0.0, 2.86, -.2), .34, .22), (const V3(0.0, 2.98, -.32), .3, .19)], _dark(top, .12), seg: 8);
      m.bias = .05;
      frontPanel([(-.28, 2.06), (.28, 2.06), (.24, 1.82), (-.24, 1.82)], .31, _dark(top, .1));
      for (final sx in [-.08, .08]) {
        m.wedge(V3(sx, 2.78, .3), V3(sx, 2.45, .34), .016, const Color(0xFFF2F2F2), kind: kMatte);
      }
    case 'kurta':
      frontPanel([(-.06, 2.85), (.06, 2.85), (.06, 2.28), (-.06, 2.28)], .35, accent);
      for (final y in [2.74, 2.58, 2.42]) {
        m.ellipsoid(V3(0, y, .36), .024, .024, .016, const Color(0xFFF6D365), lat: 3, lon: 5, kind: kMetal);
      }
    case 'trench':
      frontPanel([(-.43, 1.86), (.43, 1.86), (.43, 1.74), (-.43, 1.74)], .31, _dark(top, .3)); // belt
      for (final sx in [-1.0, 1.0]) {
        m.wedge(V3(sx * .24, 2.82, .12), V3(sx * .34, 3.08, .1), .12, _dark(top, .1), kind: kMatte, flat: .4); // popped collar
      }
    case 'track':
      frontPanel([(-.018, 2.85), (.018, 2.85), (.018, 1.8), (-.018, 1.8)], .35, accent);
    case 'tee':
      frontPanel([(-.15, 2.84), (.15, 2.84), (0.0, 2.7)], .34, _dark(top, .2));
    case 'dress':
      for (final sx in [-1.0, 1.0]) {
        frontPanel([(sx * .24, 2.84), (sx * .31, 2.84), (sx * .24, 2.52)], .34, _dark(top, .1));
      }
  }
  m.bias = 0;

  // ---------------------------------------------------------- head
  m.group = gHead;
  m.ellipsoid(_headC, rx, ry, rz, skin, lat: lat, lon: lon, deform: headDeform, kind: kSkin);
  for (final sx in [-1.0, 1.0]) {
    m.ellipsoid(V3(sx * rx * .93, _headC.y - .04, -.04), .055, .1, .05, _dark(skin, .05), lat: 3, lon: 6, kind: kSkin);
  }
  // Nose: a small faceted wedge.
  m.bias = .08;
  final nz = surfZ(0, _headC.y - .1);
  m.wedge(V3(0, _headC.y - .07, nz - .03), V3(0, _headC.y - .16, nz + .07), .05, _dark(skin, .03), kind: kSkin, flat: .8);
  m.bias = 0;

  _face(m, cfg, skin, hair, rx, ry, surfZ);
  _beard(m, cfg, hair, rx, ry, rz, jaw, headDeform);
  _hair(m, cfg, hair, rx, ry, rz);
  _glasses(m, cfg, rx, surfZ);
  _extras(m, cfg, top, accent, rx, ry, rz, surfZ);
  // Stylised proportions: everything on the head is built at a neutral
  // size, then scaled up from the neck — the big-headed game-character look.
  const pivot = V3(0.0, 2.84, 0);
  const grow = 1.18;
  V3 up(V3 p) => pivot + (p - pivot) * grow;
  return [
    for (final t in m.tris)
      if (t.group == gHead || t.group == gEyes)
        Tri(up(t.a), up(t.b), up(t.c), t.color, t.kind, t.group,
            pivot: t.pivot == null ? null : up(t.pivot!), twoSided: t.twoSided, bias: t.bias)
      else
        t
  ];
}

// ---------------------------------------------------------------- face

void _face(MeshBuilder m, AvatarConfig cfg, Color skin, Color hair, double rx, double ry, double Function(double, double) surfZ) {
  final ey = _headC.y + .02;
  m.bias = .2;
  // Blush and freckles.
  if (cfg.flag('blush')) {
    for (final sx in [-1.0, 1.0]) {
      m.decal(ellipsePts(Offset(sx * .25, ey - .14), .07, .035, 8), surfZ(sx * .25, ey - .14) + .006,
          _mix(skin, const Color(0xFFFF6B81), .35), kind: kMatte);
    }
  }
  if (cfg.flag('freckles')) {
    for (final (x, y) in const [(-.24, -.1), (-.18, -.13), (-.28, -.15), (.24, -.1), (.18, -.13), (.28, -.15)]) {
      m.decal(ellipsePts(Offset(x, ey + y), .012, .012, 5), surfZ(x, ey + y) + .008, _dark(skin, .3), kind: kMatte);
    }
  }

  // Eyes (group gEyes so they blink).
  final eyes = cfg.s('eyes');
  final iris = cfg.color('eye_color', const Color(0xFF3B2416));
  for (final sx in [-1.0, 1.0]) {
    final ex = sx * .165;
    final z = surfZ(ex, ey) + .012;
    final c = Offset(ex, ey);
    final pivot = V3(ex, ey, z);
    m.group = gEyes;
    final closed = eyes == 'happy' || (eyes == 'wink' && sx > 0);
    if (closed) {
      m.stroke(arcPts(c.translate(0, -.02), .065, .05, .2, math.pi - .2), .022, z, _ink, pivot: pivot, bias: .4);
      continue;
    }
    final (w, h, ir) = switch (eyes) {
      'almond' => (.1, .055, .042),
      'sleepy' => (.09, .055, .04),
      'sharp' => (.095, .048, .04),
      'wide' => (.1, .09, .05),
      'cute' => (.09, .085, .062),
      _ => (.085, .075, .045),
    };
    // Layers, back to front (each a step nearer in the sort).
    m.decal(ellipsePts(c, w, h, 12), z, const Color(0xFFFFFFFF), pivot: pivot, bias: .3);
    // The iris is clipped to the eye's height.
    m.decal(ellipsePts(c.translate(sx * -.008, -.004), ir, math.min(ir, h * .95), 10), z + .002, iris, pivot: pivot, bias: .36);
    m.decal(ellipsePts(c.translate(sx * -.008, -.004), ir * .5, math.min(ir * .5, h * .5), 8), z + .003, const Color(0xFF0E0F12),
        pivot: pivot, bias: .42);
    m.decal(ellipsePts(c.translate(-.018, .022), .014, .014, 6), z + .004, const Color(0xFFFFFFFF), pivot: pivot, bias: .48);
    if (eyes == 'cute') {
      m.decal(ellipsePts(c.translate(.016, -.02), .008, .008, 5), z + .004, const Color(0xFFFFFFFF), pivot: pivot, bias: .48);
    }
    // Upper lid line.
    m.stroke(arcPts(c, w * 1.02, h * 1.02, .15, math.pi - .15), eyes == 'sharp' ? .028 : .018, z + .005, _ink,
        pivot: pivot, bias: .5);
    if (eyes == 'sleepy') {
      m.decal([c.translate(-w * 1.05, .0), c.translate(w * 1.05, .0), c.translate(w * 1.05, h * 1.1), c.translate(-w * 1.05, h * 1.1)],
          z + .006, _dark(skin, .06), kind: kSkin, pivot: pivot, bias: .52);
      m.stroke([c.translate(-w, 0), c.translate(w, 0)], .016, z + .007, _ink, pivot: pivot, bias: .54);
    }
  }
  m.group = gHead;

  // Brows.
  final browC = _dark(hair, .1);
  final brows = cfg.s('brows');
  for (final sx in [-1.0, 1.0]) {
    final bx = sx * .17, by = ey + .12;
    final z = surfZ(bx, by) + .014;
    final w = brows == 'bold' ? .036 : .024;
    final pts = switch (brows) {
      'straight' => [Offset(bx - sx * .08, by), Offset(bx + sx * .08, by + .005)],
      'arched' => arcPts(Offset(bx, by - .03), .085, .05, math.pi * .15, math.pi * .85, 6),
      'angry' => [Offset(bx + sx * .08, by + .03), Offset(bx - sx * .08, by - .03)],
      'raised' => arcPts(Offset(bx, by - .01), .08, .06, math.pi * .2, math.pi * .8, 6),
      _ => arcPts(Offset(bx, by - .04), .085, .045, math.pi * .2, math.pi * .8, 6),
    };
    m.stroke(pts, w, z, browC, bias: .3);
  }

  // Mouth.
  final my = _headC.y - .27;
  final mz = surfZ(0, my) + .016;
  const lip = Color(0xFF7A2E33), inner = Color(0xFF3A1214), tongue = Color(0xFFE86A7A);
  switch (cfg.s('mouth')) {
    case 'grin':
      final pts = arcPts(Offset(0, my + .03), .1, .085, math.pi, 2 * math.pi, 10);
      m.decal(pts, mz, inner, bias: .3);
      m.decal([Offset(-.095, my + .03), Offset(.095, my + .03), Offset(.08, my - .005), Offset(-.08, my - .005)], mz + .002,
          const Color(0xFFFFFFFF), bias: .36);
    case 'open':
      m.decal(ellipsePts(Offset(0, my - .01), .045, .05, 10), mz, inner, bias: .3);
      m.decal(ellipsePts(Offset(0, my - .035), .03, .018, 8), mz + .002, tongue, bias: .36);
    case 'tongue':
      m.decal(arcPts(Offset(0, my + .02), .075, .06, math.pi, 2 * math.pi, 9), mz, inner, bias: .3);
      m.decal(ellipsePts(Offset(.015, my - .045), .035, .04, 9), mz + .003, tongue, bias: .36);
    case 'smirk':
      m.stroke([Offset(-.07, my - .005), Offset(0, my - .015), Offset(.065, my + .02)], .02, mz, lip);
    case 'neutral':
      m.stroke([Offset(-.06, my - .005), Offset(.06, my - .005)], .02, mz, lip);
    case 'frown':
      m.stroke(arcPts(Offset(0, my - .06), .07, .045, .35, math.pi - .35, 7), .02, mz, lip);
    case 'cool':
      m.stroke([Offset(-.065, my), Offset(-.02, my - .012), Offset(.03, my - .01), Offset(.07, my + .005)], .018, mz, lip);
    default: // smile
      m.stroke(arcPts(Offset(0, my + .03), .085, .06, math.pi + .35, 2 * math.pi - .35, 8), .022, mz, lip);
  }
  m.bias = 0;
}

// ---------------------------------------------------------------- beard

void _beard(MeshBuilder m, AvatarConfig cfg, Color hair, double rx, double ry, double rz, double jaw,
    V3 Function(V3, V3) deform) {
  final style = cfg.s('beard');
  if (style == 'none') return;
  final my = _headC.y - .27;
  bool mouthHole(V3 c) => c.x.abs() < .12 && c.y > my - .07 && c.y < my + .06 && c.z > 0;
  void shell(double grow, double from, Color color, {double drop = 0, bool Function(V3)? keep}) {
    m.ellipsoid(_headC, rx * grow, ry * grow, rz * grow, color,
        lat: 7, lon: 12, from: from, to: math.pi, kind: kHair, deform: (u, p) {
      final q = deform(u, p);
      return u.z > .3 && u.y < -.8 ? V3(q.x, q.y - drop, q.z) : q;
    }, skip: (c) => c.z < -.12 || mouthHole(c) || (keep != null && !keep(c)));
  }

  m.bias = .12;
  switch (style) {
    case 'stubble':
      shell(1.012, math.pi * .62, hair.withValues(alpha: .38));
    case 'short':
      shell(1.04, math.pi * .62, hair);
    case 'full':
      shell(1.07, math.pi * .58, hair, drop: .1);
    case 'chinstrap':
      shell(1.04, math.pi * .64, hair, keep: (c) => c.y < my - .08 || c.x.abs() > rx * .62);
  }
  if (style == 'moustache' || style == 'van_dyke' || style == 'full' || style == 'short') {
    for (final sx in [-1.0, 1.0]) {
      final z = rz * .82;
      m.wedge(V3(sx * .035, my + .055, z + .01), V3(sx * .135, my + .0, z + .02), .055, hair, flat: .35);
    }
  }
  if (style == 'goatee' || style == 'van_dyke') {
    // A neat beard around the mouth and chin, joined to the moustache.
    bool smallHole(V3 c) => c.x.abs() < .085 && c.y > my - .045 && c.y < my + .035 && c.z > 0;
    m.ellipsoid(_headC, rx * 1.035, ry * 1.035, rz * 1.035, hair, lat: 9, lon: 16, from: math.pi * .6, to: math.pi, kind: kHair,
        deform: deform,
        skip: (c) => c.z < .1 || smallHole(c) || c.x.abs() > (style == 'van_dyke' ? .19 : .14) || c.y > my + .09);
    final z = rz * .78;
    m.wedge(V3(0, my - .07, z - .02), V3(0, my - .26, z + .02), .075, hair, sides: 4, flat: .6);
    if (style == 'van_dyke') m.wedge(V3(0, my - .04, z + .01), V3(0, my - .11, z + .04), .025, hair);
  }
  m.bias = 0;
}

// ---------------------------------------------------------------- hair

void _hair(MeshBuilder m, AvatarConfig cfg, Color color, double rx, double ry, double rz) {
  final style = cfg.s('hair');
  if (style == 'none') return;
  final hatOn = cfg.s('accessory') == 'beanie';
  if (hatOn && style != 'long' && style != 'ponytail' && style != 'pigtails' && style != 'bob') return;
  final c = _headC;

  /// A point on the scalp: [yaw] around (0 = front), [pitch] down from the top.
  V3 scalp(double yaw, double pitch, [double grow = 1.08]) => c +
      V3(math.sin(pitch) * math.sin(yaw) * rx * grow, math.cos(pitch) * ry * grow, math.sin(pitch) * math.cos(yaw) * rz * grow);

  void cap(double hairline, {double grow = 1.08, Color? tint}) {
    m.ellipsoid(c, rx * grow, ry * grow, rz * grow, tint ?? color, lat: 6, lon: 12, from: 0, to: math.pi * .62, kind: kHair,
        skip: (t) => t.z > rz * .1 && t.y < c.y + hairline);
  }

  void lock(double yaw, double pitch, V3 tipOffset, double width) {
    final root = scalp(yaw, pitch);
    m.wedge(root, root + tipOffset, width, color, kind: kHair);
  }

  m.bias = 0;
  switch (style) {
    case 'buzz':
      cap(.26, grow: 1.025, tint: _mix(color, cfg.color('skin', color), .25));
    case 'short':
      cap(.24);
      m.bias = .7;
      for (var i = -2; i <= 2; i++) {
        lock(i * .22, .55, V3(i * .03, -.14, .1), .1);
      }
    case 'swept':
      cap(.3, grow: 1.12);
      // Chunky locks over the crown, combed back.
      for (var i = 0; i < 6; i++) {
        lock(-1.2 + i * .48, .3, V3(math.sin(-1.2 + i * .48) * .08, .06, -.22), .17);
      }
      m.bias = .7;
      // Long angular fringe sweeping across the forehead.
      for (var i = 0; i < 5; i++) {
        final yaw = -.55 + i * .26;
        lock(yaw, .32 + i * .04, V3(-.12 - i * .015, -.32 + i * .02, .13), .15);
      }
      m.bias = 0;
      for (final sx in [-1.0, 1.0]) {
        lock(sx * 1.35, .9, V3(sx * .05, -.3, .02), .12);
        lock(sx * 1.9, .95, V3(sx * .03, -.28, -.06), .12);
      }
      lock(math.pi, 1.0, const V3(0, -.3, -.1), .16);
    case 'spiky':
      cap(.28);
      for (var i = 0; i < 9; i++) {
        final yaw = -1.6 + i * .4;
        lock(yaw, .45, V3(math.sin(yaw) * .12, .32, math.cos(yaw) * .08 - .05), .11);
      }
      lock(0, .1, const V3(0, .36, -.02), .12);
    case 'quiff':
      cap(.24);
      m.bias = .2;
      for (var i = -2; i <= 2; i++) {
        lock(i * .2, .35, V3(i * .02, .3, -.12), .13);
      }
    case 'curly':
      cap(.24);
      for (var i = 0; i < 22; i++) {
        final yaw = i * 2.4;
        final pitch = .25 + (i % 5) * .2;
        final p = scalp(yaw, pitch, 1.12);
        if (p.z > rz * .2 && p.y < c.y + .26) continue;
        m.ellipsoid(p, .09, .09, .09, _mix(color, const Color(0xFFFFFFFF), (i % 3) * .03), lat: 3, lon: 5, kind: kHair);
      }
    case 'wavy':
      cap(.26);
      for (final sx in [-1.0, 1.0]) {
        lock(sx * 1.25, .85, V3(sx * .08, -.45, .02), .14);
        lock(sx * 1.7, .9, V3(sx * .05, -.5, -.05), .14);
        lock(sx * 2.4, .9, V3(sx * .02, -.48, -.08), .15);
      }
      m.bias = .22;
      lock(-.3, .4, const V3(.06, -.18, .12), .12);
    case 'long':
    case 'bob':
      cap(.26);
      final end = style == 'long' ? 2.55 : 3.15;
      m.loft([
        (V3(0, c.y + .1, -rz * .55), rx * 1.05, rz * .5),
        (V3(0, (c.y + end) / 2, -rz * .5), rx * 1.1, rz * .45),
        (V3(0, end, -rz * .4), rx * (style == 'long' ? 1.05 : 1.12), rz * .35),
      ], color, seg: 8, kind: kHair, capStart: false);
      for (final sx in [-1.0, 1.0]) {
        lock(sx * 1.2, .8, V3(sx * .06, end - c.y - .05, .0), .14);
      }
      m.bias = .2;
      lock(.2, .38, const V3(-.08, -.2, .1), .13);
    case 'bun':
      cap(.24);
      m.ellipsoid(scalp(math.pi, .5, 1.25), .2, .18, .2, color, lat: 4, lon: 8, kind: kHair);
    case 'ponytail':
      cap(.24);
      final root = scalp(math.pi, .7, 1.05);
      m.loft([(root, .12, .12), (root + const V3(0, -.35, -.18), .14, .12), (root + const V3(0, -.95, -.2), .06, .05)], color,
          seg: 6, kind: kHair);
    case 'pigtails':
      cap(.24);
      for (final sx in [-1.0, 1.0]) {
        final root = scalp(sx * 1.6, .85, 1.05);
        m.loft([(root, .1, .1), (root + V3(sx * .12, -.4, 0), .12, .1), (root + V3(sx * .08, -.85, .02), .05, .05)], color,
            seg: 6, kind: kHair);
      }
    case 'afro':
      m.ellipsoid(c + const V3(0, .18, -.05), rx * 1.45, ry * 1.25, rz * 1.4, color, lat: 7, lon: 14, kind: kHair,
          skip: (t) => t.z > rz * .35 && t.y < c.y + .3 && t.x.abs() < rx * 1.1);
    case 'mohawk':
      cap(.26, grow: 1.02, tint: _mix(color, cfg.color('skin', color), .55));
      // A ridge of spikes from the forehead over the top to the back.
      for (var i = 0; i < 6; i++) {
        final (yaw, pitch) = i < 3 ? (0.0, .55 - i * .2) : (math.pi, .15 + (i - 3) * .32);
        final root = scalp(yaw, pitch, 1.03);
        m.wedge(root, root + (root - c).unit * .3 + const V3(0, .05, 0), .08, color, kind: kHair, flat: .35);
      }
    case 'side':
      cap(.28);
      m.bias = .7;
      for (var i = 0; i < 5; i++) {
        lock(-.6 + i * .2, .45, V3(.16 + i * .01, -.12 - i * .02, .1), .12);
      }
  }
  m.bias = 0;
}

// ---------------------------------------------------------------- glasses

void _glasses(MeshBuilder m, AvatarConfig cfg, double rx, double Function(double, double) surfZ) {
  final style = cfg.s('glasses');
  if (style == 'none') return;
  final ey = _headC.y + .02;
  m.bias = .6;
  final z = surfZ(.165, ey) + .05;
  final frame = style == 'aviator' ? const Color(0xFFC9A64A) : const Color(0xFF15171C);
  final frameKind = style == 'aviator' ? kMetal : kMatte;
  if (style == 'visor') {
    m.decal([Offset(-.36, ey + .08), Offset(.36, ey + .08), Offset(.32, ey - .07), Offset(-.32, ey - .07)], z,
        const Color(0xCC4CC9F0), kind: kGlass);
    m.stroke([Offset(-.36, ey + .08), Offset(.36, ey + .08)], .025, z + .002, frame, kind: kMatte);
  } else {
    for (final sx in [-1.0, 1.0]) {
      final c = Offset(sx * .165, ey);
      final lens = switch (style) {
        'square' => [c.translate(-.11, .07), c.translate(.11, .07), c.translate(.1, -.07), c.translate(-.1, -.07)],
        'aviator' => [c.translate(-.11, .07), c.translate(.11, .07), c.translate(.09, -.05), c.translate(0, -.1), c.translate(-.1, -.05)],
        'sun' => [c.translate(-.12, .07), c.translate(.12, .07), c.translate(.1, -.07), c.translate(-.1, -.07)],
        _ => ellipsePts(c, .095, .09, 12),
      };
      final tint = switch (style) {
        'sun' => const Color(0xE8121418),
        'round_tint' => const Color(0xB8F2A33A),
        'aviator' => const Color(0x8834453F),
        _ => const Color(0x22B8D8FF),
      };
      m.decal(lens, z, tint, kind: kGlass);
      m.stroke([...lens, lens.first], .022, z + .003, frame, kind: frameKind, bias: .66);
    }
    m.stroke([Offset(-.07, ey + .02), Offset(.07, ey + .02)], .02, z + .003, frame, kind: frameKind);
  }
  // Temples back to the ears.
  m.bias = 0;
  for (final sx in [-1.0, 1.0]) {
    m.loft([(V3(sx * .27, ey + .03, z - .02), .012, .012), (V3(sx * rx * .93, ey + .01, -.1), .012, .012)], frame, seg: 4,
        kind: frameKind);
  }
}

// ---------------------------------------------------------------- extras

void _extras(MeshBuilder m, AvatarConfig cfg, Color top, Color accent, double rx, double ry, double rz,
    double Function(double, double) surfZ) {
  final c = _headC;
  const gold = Color(0xFFF2C14E);
  switch (cfg.s('accessory')) {
    case 'earrings':
      for (final sx in [-1.0, 1.0]) {
        m.ellipsoid(V3(sx * rx * .98, c.y - .16, -.01), .035, .035, .035, gold, lat: 3, lon: 6, kind: kMetal);
      }
    case 'bindi':
      m.bias = .2;
      m.decal(ellipsePts(Offset(0, c.y + .2), .022, .022, 8), surfZ(0, c.y + .2) + .02, const Color(0xFFD7263D), kind: kMatte);
    case 'nose_ring':
      m.bias = .2;
      final z = surfZ(.04, c.y - .17) + .06;
      m.stroke(arcPts(Offset(.045, c.y - .17), .025, .025, -1.2, 3.4, 8), .01, z, gold, kind: kMetal);
    case 'cap':
      m.ellipsoid(c + const V3(0, .04, 0), rx * 1.16, ry * 1.12, rz * 1.16, top, lat: 4, lon: 12, from: 0, to: math.pi * .45);
      m.bias = .1;
      final brimY = c.y + ry * .2;
      final brim = [
        V3(-rx * .95, brimY, rz * .7), V3(rx * .95, brimY, rz * .7),
        V3(rx * .8, brimY - .04, rz * 1.55), V3(-rx * .8, brimY - .04, rz * 1.55),
      ];
      m.tri(brim[0], brim[1], brim[2], _cDark(top), out: const V3(0.0, 1, .1), twoSided: true);
      m.tri(brim[0], brim[2], brim[3], _cDark(top), out: const V3(0.0, 1, .1), twoSided: true);
      m.ellipsoid(c + V3(0, ry * 1.12 + .02, 0), .05, .03, .05, accent, lat: 2, lon: 6);
    case 'beanie':
      m.ellipsoid(c + const V3(0, .06, 0), rx * 1.14, ry * 1.12, rz * 1.14, top, lat: 5, lon: 12, from: 0, to: math.pi * .5);
      m.loft([(c + V3(0, ry * .05, 0), rx * 1.17, rz * 1.17), (c + V3(0, ry * .28, 0), rx * 1.16, rz * 1.16)], _cDark(top), seg: 12,
          capStart: false, capEnd: false);
      m.ellipsoid(c + V3(0, ry * 1.2 + .04, 0), .1, .1, .1, accent, lat: 3, lon: 7);
    case 'headphones':
      const band = Color(0xFF1C1F26);
      final pts = <(V3, double, double)>[
        for (var k = 0; k <= 8; k++)
          (c + V3(-math.cos(math.pi * k / 8) * rx * 1.12, math.sin(math.pi * k / 8) * ry * 1.14 - .05, 0), .035, .05)
      ];
      m.loft(pts, band, seg: 5);
      for (final sx in [-1.0, 1.0]) {
        m.ellipsoid(c + V3(sx * rx * 1.08, -.05, 0), .08, .13, .12, accent, lat: 4, lon: 8);
      }
    case 'scarf':
      m.group = gBody;
      m.loft([(const V3(0.0, 2.78, -.01), .32, .26), (const V3(0.0, 2.95, -.01), .29, .23)], accent, seg: 9, capStart: false, capEnd: false);
      m.loft([(const V3(.14, 2.82, .24), .08, .03), (const V3(.18, 2.3, .33), .09, .03)], _cDark(accent), seg: 4);
      m.group = gHead;
    case 'cape':
      // A long cape from the shoulders (visible from both sides) with a
      // tall collar: dark outside, accent lining facing forward.
      m.group = gBody;
      final rows = [
        [const V3(-.58, 2.8, -.26), const V3(0.0, 2.86, -.34), const V3(.58, 2.8, -.26)],
        [const V3(-.78, 1.7, -.46), const V3(0.0, 1.7, -.56), const V3(.78, 1.7, -.46)],
        [const V3(-.9, .55, -.6), const V3(0.0, .55, -.72), const V3(.9, .55, -.6)],
      ];
      for (var r = 0; r < rows.length - 1; r++) {
        for (var k = 0; k < 2; k++) {
          final a = rows[r][k], b = rows[r][k + 1], d = rows[r + 1][k], e = rows[r + 1][k + 1];
          m.tri(a, b, e, _cDark(top), out: const V3(0.0, 0, -1), twoSided: true);
          m.tri(a, e, d, _cDark(top), out: const V3(0.0, 0, -1), twoSided: true);
        }
      }
      for (final sx in [-1.0, 1.0]) {
        final q = [V3(sx * .14, 2.84, -.16), V3(sx * .5, 2.8, -.1), V3(sx * .56, 3.22, -.26), V3(sx * .18, 3.26, -.32)];
        m.tri(q[0], q[1], q[2], accent, out: const V3(0.0, .2, 1));
        m.tri(q[0], q[2], q[3], accent, out: const V3(0.0, .2, 1));
        m.tri(q[0], q[1], q[2], _cDark(top), out: const V3(0.0, -.2, -1));
        m.tri(q[0], q[2], q[3], _cDark(top), out: const V3(0.0, -.2, -1));
      }
      m.group = gHead;
    case 'crown':
      final base = c + V3(0, ry * .82, 0);
      m.loft([(base, rx * .62, rz * .62), (base + const V3(0, .08, 0), rx * .64, rz * .64)], gold, seg: 10, kind: kMetal,
          capStart: false, capEnd: false);
      for (var k = 0; k < 5; k++) {
        final a = (k - 2) * .55; // around the front of the head
        final p = base + V3(math.sin(a) * rx * .62, .08, math.cos(a) * rz * .62);
        m.wedge(p, p + const V3(0, .14, 0), .05, gold, kind: kMetal);
      }
  }
  m.bias = 0;
}

Color _cDark(Color c) => _dark(c, .22);
