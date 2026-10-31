// Phlio Looks — Instagram-style colour grades and effects, shared by the
// Moments composer / viewer and the DM Studio.
//
// A look is a 3x4 colour matrix (saturation, contrast, warmth, tint,
// brightness) followed by a per-channel tone curve
//     out = lift + (gain - lift) * pow(in, gamma)
// plus vignette and grain. The GPU shader (assets/shaders/phlio_look.frag)
// and the Studio's server renderer (colorchannelmixer + lutrgb) use exactly
// this maths, so previews match exports.
//
// Pure Dart (no Flutter imports) so the Studio's project model can use it.

import 'dart:math' as math;

class LookGrade {
  const LookGrade({
    this.matrix = identityMatrix,
    this.lift = const [0, 0, 0],
    this.gamma = const [1, 1, 1],
    this.gain = const [1, 1, 1],
    this.vignette = 0,
    this.grain = 0,
  });

  /// Row-major 3x4: r' = m0 r + m1 g + m2 b + m3 (0-1 units).
  final List<double> matrix;
  final List<double> lift, gamma, gain;
  final double vignette, grain;

  static const identityMatrix = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0];
  static const none = LookGrade();

  bool get toneIsIdentity =>
      lift.every((v) => v.abs() < 1e-4) &&
      gamma.every((v) => (v - 1).abs() < 1e-4) &&
      gain.every((v) => (v - 1).abs() < 1e-4);

  /// Blend towards "no look" by [t] (0 = none, 1 = full).
  LookGrade scaled(double t) {
    double lerp(double a, double b) => a + (b - a) * t;
    return LookGrade(
      matrix: [for (var i = 0; i < 12; i++) lerp(identityMatrix[i], matrix[i])],
      lift: [for (final v in lift) lerp(0, v)],
      gamma: [for (final v in gamma) lerp(1, v)],
      gain: [for (final v in gain) lerp(1, v)],
      vignette: vignette * t,
      grain: grain * t,
    );
  }

  /// Server tone spec: [liftR, liftG, liftB, gammaR, gammaG, gammaB, gainR, gainG, gainB].
  List<double> get tone => [...lift, ...gamma, ...gain];
}

// -- matrix helpers ------------------------------------------------------------------

List<double> _mul(List<double> a, List<double> b) {
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

List<double> _sat(double s) {
  final lr = .2126 * (1 - s), lg = .7152 * (1 - s), lb = .0722 * (1 - s);
  return [lr + s, lg, lb, 0, lr, lg + s, lb, 0, lr, lg, lb + s, 0];
}

List<double> _con(double k) {
  final o = .5 * (1 - k);
  return [k, 0, 0, o, 0, k, 0, o, 0, 0, k, o];
}

List<double> _scale(double r, double g, double b) => [r, 0, 0, 0, 0, g, 0, 0, 0, 0, b, 0];

List<double> _offset(double r, double g, double b) => [1, 0, 0, r, 0, 1, 0, g, 0, 0, 1, b];

/// sat → contrast → warmth/tint → brightness, as one matrix.
List<double> lookMatrix({
  double saturation = 1,
  double contrast = 1,
  double warmth = 0,
  double tint = 0,
  double brightness = 0,
}) {
  var m = _sat(saturation);
  m = _mul(_con(contrast), m);
  if (warmth != 0 || tint != 0) {
    m = _mul(_scale(1 + .1 * warmth + .03 * tint, 1 - .08 * tint, 1 - .1 * warmth + .03 * tint), m);
  }
  if (brightness != 0) m = _mul(_offset(brightness, brightness, brightness), m);
  return m;
}

LookGrade _look({
  double saturation = 1,
  double contrast = 1,
  double warmth = 0,
  double tint = 0,
  double brightness = 0,
  List<double> lift = const [0, 0, 0],
  List<double> gamma = const [1, 1, 1],
  List<double> gain = const [1, 1, 1],
  double vignette = 0,
  double grain = 0,
}) =>
    LookGrade(
      matrix: lookMatrix(
          saturation: saturation, contrast: contrast, warmth: warmth, tint: tint, brightness: brightness),
      lift: lift,
      gamma: gamma,
      gain: gain,
      vignette: vignette,
      grain: grain,
    );

// -- catalogue -----------------------------------------------------------------------

/// Instagram-style looks (our own grades, named for the familiar feel).
final Map<String, LookGrade> phlioLooks = {
  'normal': LookGrade.none,
  'clarendon': _look(saturation: 1.35, contrast: 1.18, lift: [0, .01, .045], gain: [1.02, 1.02, 1]),
  'gingham': _look(saturation: .82, contrast: .92, warmth: .25, lift: [.07, .07, .06], gain: [.97, .96, .93]),
  'juno': _look(saturation: 1.3, contrast: 1.1, warmth: .45, gamma: [.96, 1, 1.06]),
  'lark': _look(saturation: .9, brightness: .03, lift: [.02, .03, .05], gain: [1.05, 1.07, 1.08]),
  'ludwig': _look(saturation: 1.12, contrast: 1.06, warmth: .3, vignette: .25),
  'valencia': _look(saturation: 1.05, contrast: .94, warmth: .7, lift: [.05, .03, .02], gain: [1.02, .98, .88]),
  'xpro2': _look(saturation: 1.22, contrast: 1.3, gamma: [.9, 1, 1.12], lift: [0, 0, .07], vignette: .5),
  'lofi': _look(saturation: 1.35, contrast: 1.5, vignette: .35),
  'aden': _look(saturation: .82, contrast: .9, tint: .4, lift: [.07, .04, .05], gain: [1, .97, .96]),
  'perpetua': _look(saturation: 1.1, gamma: [1.02, .95, 1], lift: [0, .04, .05], gain: [.98, 1.03, 1]),
  'reyes': _look(saturation: .75, contrast: .82, warmth: .3, lift: [.12, .11, .1], gain: [1.02, 1, .97]),
  'slumber': _look(saturation: .62, warmth: .4, lift: [.06, .04, .04], gain: [.93, .9, .86]),
  'crema': _look(saturation: .8, contrast: .95, warmth: .2, lift: [.05, .045, .04]),
  'moon': _look(saturation: 0, contrast: 1.12, lift: [.05, .05, .05], gain: [1.05, 1.05, 1.05]),
  'inkwell': _look(saturation: 0, contrast: 1.25),
  'willow': _look(saturation: 0, contrast: .92, lift: [.08, .075, .08], gain: [.94, .93, .95]),
  'hefe': _look(saturation: 1.3, contrast: 1.3, warmth: .5, vignette: .4),
  'nashville': _look(saturation: 1.1, contrast: .9, lift: [.12, .04, .1], gain: [1.02, .98, .86]),
  'amaro': _look(saturation: 1.2, contrast: 1.05, warmth: -.2, lift: [.05, .05, .07], gain: [1.08, 1.08, 1.06]),
  'rise': _look(saturation: .9, contrast: .95, warmth: .45, lift: [.07, .05, .03], gain: [1.05, 1.03, .98]),
  'sierra': _look(saturation: .85, contrast: .88, lift: [.07, .06, .06], vignette: .3),
  'phlio': _look(saturation: 1.15, contrast: 1.05, tint: .35, lift: [.04, .01, .07], gain: [1.03, .99, 1.02]),
};

const phlioLookNames = {
  'normal': 'Normal',
  'clarendon': 'Clarendon',
  'gingham': 'Gingham',
  'juno': 'Juno',
  'lark': 'Lark',
  'ludwig': 'Ludwig',
  'valencia': 'Valencia',
  'xpro2': 'X-Pro II',
  'lofi': 'Lo-Fi',
  'aden': 'Aden',
  'perpetua': 'Perpetua',
  'reyes': 'Reyes',
  'slumber': 'Slumber',
  'crema': 'Crema',
  'moon': 'Moon',
  'inkwell': 'Inkwell',
  'willow': 'Willow',
  'hefe': 'Hefe',
  'nashville': 'Nashville',
  'amaro': 'Amaro',
  'rise': 'Rise',
  'sierra': 'Sierra',
  'phlio': 'Phlio',
};

/// GPU effects (shader ids). Studio exports the ones the server can render.
const phlioEffects = <(String, String, int)>[
  ('none', 'None', 0),
  ('grain', 'Grain', 1),
  ('light_leak', 'Light leak', 2),
  ('chromatic', 'Chromatic', 3),
  ('glitch', 'Glitch', 4),
  ('vhs', 'VHS', 5),
  ('dreamy', 'Dreamy', 6),
  ('prism', 'Prism', 7),
  ('film', 'Old film', 8),
  ('sparkle', 'Sparkle', 9),
  ('retro3d', '3D', 10),
  ('blur', 'Blur', 11),
];

int phlioEffectId(String? name) {
  for (final (key, _, id) in phlioEffects) {
    if (key == name) return id;
  }
  return 0;
}

/// Legacy moment filter names → looks.
const _legacy = {'warm': 'juno', 'cool': 'lark', 'mono': 'inkwell', 'vivid': 'clarendon', 'fade': 'reyes'};

String normalizeLook(String? name) {
  final n = _legacy[name] ?? name ?? 'normal';
  return phlioLooks.containsKey(n) ? n : 'normal';
}

/// Moments store "look" or "look+effect" in their filter field.
(String look, String effect) splitMomentFilter(String? value) {
  final parts = (value ?? 'normal').split('+');
  final effect = parts.length > 1 ? parts[1] : 'none';
  return (normalizeLook(parts.first), phlioEffectId(effect) == 0 ? 'none' : effect);
}

String joinMomentFilter(String look, String effect) => effect == 'none' ? look : '$look+$effect';

/// Flutter ColorFilter.matrix list (offsets in 0-255) for the fallback path.
List<double> lookFlutterMatrix(List<double> m) => [
      m[0], m[1], m[2], 0, m[3] * 255, //
      m[4], m[5], m[6], 0, m[7] * 255,
      m[8], m[9], m[10], 0, m[11] * 255,
      0, 0, 0, 1, 0,
    ];

/// Applies the tone curve on the CPU (used to approximate it in the
/// fallback colour matrix: linearised around mid-grey).
List<double> toneAsMatrix(LookGrade g) {
  final out = List<double>.of(LookGrade.identityMatrix);
  for (var c = 0; c < 3; c++) {
    // Slope/intercept of the curve's chord through 0.25..0.75.
    double f(double x) => g.lift[c] + (g.gain[c] - g.lift[c]) * math.pow(x, g.gamma[c]).toDouble();
    final slope = (f(.75) - f(.25)) / .5;
    out[c * 4 + c] = slope;
    out[c * 4 + 3] = f(.5) - slope * .5;
  }
  return out;
}

List<double> mulLook(List<double> a, List<double> b) => _mul(a, b);
