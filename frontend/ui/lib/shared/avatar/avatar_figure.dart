// Phlio avatar: a customisable character (like Bitmoji) drawn as layered
// vector parts — back hair, body, neck, ears, head, face, beard, front
// hair, glasses, accessories — each filled with the `avatar_shade`
// fragment shader for a soft 2.5D toon-lit look (cool shadows, rim light,
// hair sheen). It breathes and blinks. Without shader support it falls
// back to flat colours.
//
// The look is a small config ([AvatarConfig]) saved to the account
// (/social/avatar); [myAvatarProvider] loads yours.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

Color _c(Object? hex, Color fallback) {
  if (hex is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }
  return fallback;
}

String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Choices offered in the builder (same as the server's lists).
const avatarOptions = <String, List<String>>{
  'face': ['oval', 'round', 'square', 'heart', 'long'],
  'hair': ['none', 'buzz', 'short', 'quiff', 'curly', 'wavy', 'long', 'bun', 'ponytail', 'afro', 'side'],
  'eyes': ['round', 'almond', 'sleepy', 'happy', 'wink'],
  'brows': ['soft', 'straight', 'arched', 'bold'],
  'mouth': ['smile', 'grin', 'open', 'smirk', 'neutral'],
  'beard': ['none', 'stubble', 'short', 'full', 'goatee', 'moustache'],
  'glasses': ['none', 'round', 'square', 'aviator', 'sun'],
  'top': ['tee', 'hoodie', 'shirt', 'jacket', 'kurta', 'dress'],
  'accessory': ['none', 'earrings', 'cap', 'beanie', 'headphones', 'bindi', 'nose_ring'],
  'background': ['none', 'gradient', 'sunset', 'mint', 'night'],
};

const avatarSkinTones = [
  Color(0xFFFFE0C4), Color(0xFFF3C9A5), Color(0xFFE0AC88), Color(0xFFC68A62),
  Color(0xFFA86D45), Color(0xFF8D5524), Color(0xFF6B3E1F), Color(0xFF4A2A16),
];
const avatarHairColors = [
  Color(0xFF111111), Color(0xFF2B1B12), Color(0xFF5A3825), Color(0xFF8B5A2B), Color(0xFFC89B5A),
  Color(0xFFE8C77A), Color(0xFFB0412E), Color(0xFF9AA0A6), Color(0xFFF2F2F2), Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFF4CC9F0),
];
const avatarEyeColors = [
  Color(0xFF3B2416), Color(0xFF1B1B1B), Color(0xFF5B7F3A), Color(0xFF3F6FB5), Color(0xFF8A6A3C), Color(0xFF6B6F7A),
];
const avatarClothColors = [
  Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F), Color(0xFF4CC9F0), Color(0xFF39D98A), Color(0xFFF6D365),
  Color(0xFFF5636B), Color(0xFF111925), Color(0xFFF2F2F2), Color(0xFF2E4A7D), Color(0xFF7A4B2A), Color(0xFF0E7A3A),
];

class AvatarConfig {
  AvatarConfig(Map<String, dynamic>? json) : values = {..._defaults, ...?json};

  static const _defaults = <String, dynamic>{
    'skin': '#C68A62', 'face': 'oval', 'hair': 'short', 'hair_color': '#2B1B12', 'eyes': 'round',
    'eye_color': '#3B2416', 'brows': 'soft', 'mouth': 'smile', 'beard': 'none', 'glasses': 'none',
    'top': 'tee', 'top_color': '#8D78FF', 'accessory': 'none', 'background': 'gradient', 'blush': true, 'freckles': false,
  };

  final Map<String, dynamic> values;

  String s(String k) => '${values[k] ?? _defaults[k]}';
  Color skin() => _c(values['skin'], const Color(0xFFC68A62));
  Color hairColor() => _c(values['hair_color'], const Color(0xFF2B1B12));
  Color eyeColor() => _c(values['eye_color'], const Color(0xFF3B2416));
  Color topColor() => _c(values['top_color'], const Color(0xFF8D78FF));
  bool get blush => values['blush'] == true;
  bool get freckles => values['freckles'] == true;

  AvatarConfig copyWith(String key, Object value) => AvatarConfig({...values, key: value});
  Map<String, dynamic> toJson() => {...values};
}

/// Your saved avatar (null until you make one).
final myAvatarProvider = FutureProvider<AvatarConfig?>((ref) async {
  final res = await getIt<ApiClient>().dio.get<dynamic>('/social/avatar');
  final a = (res.data as Map)['avatar'];
  return a is Map ? AvatarConfig(Map<String, dynamic>.from(a)) : null;
});

Future<void> saveMyAvatar(AvatarConfig config) =>
    getIt<ApiClient>().dio.put<dynamic>('/social/avatar', data: config.toJson());

/// The avatar, animated (breathing + blinking). [size] is the width; the
/// figure is 6:7.
class AvatarFigure extends StatefulWidget {
  const AvatarFigure({required this.config, super.key, this.size = 160, this.animate = true, this.background = true});
  final AvatarConfig config;
  final double size;
  final bool animate, background;

  @override
  State<AvatarFigure> createState() => _AvatarFigureState();
}

class _AvatarFigureState extends State<AvatarFigure> with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      _t = e.inMicroseconds / 1e6;
      if (mounted) setState(() {});
    });
    if (widget.animate) _ticker.start();
    if (_program == null) {
      _loading ??= () async {
        try {
          _program = await ui.FragmentProgram.fromAsset('assets/shaders/avatar_shade.frag');
        } catch (_) {}
      }();
      _loading!.then((_) {
        if (mounted) setState(() {});
      });
    }
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
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size * 7 / 6,
        child: CustomPaint(painter: AvatarPainter(widget.config, _t, _program, background: widget.background)),
      );
}

/// Paints the avatar in a 240 × 280 design box, scaled to fit.
class AvatarPainter extends CustomPainter {
  AvatarPainter(this.cfg, this.t, this.program, {this.background = true});
  final AvatarConfig cfg;
  final double t;
  final ui.FragmentProgram? program;
  final bool background;

  late Canvas _canvas;
  late double _scale;
  final _shaders = <ui.FragmentShader>[];

  /// A fill for [rect] (design units) shaded as [kind] (0 skin, 1 hair, 2 cloth).
  Paint _fill(Color color, Rect rect, int kind) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    final p = program;
    if (p == null) return paint;
    final shader = p.fragmentShader();
    _shaders.add(shader);
    // FlutterFragCoord is in the paint's local (design) coordinates.
    final r = rect;
    shader
      ..setFloat(0, r.left)
      ..setFloat(1, r.top)
      ..setFloat(2, r.width)
      ..setFloat(3, r.height)
      ..setFloat(4, color.r)
      ..setFloat(5, color.g)
      ..setFloat(6, color.b)
      ..setFloat(7, kind.toDouble())
      ..setFloat(8, t)
      ..setFloat(9, 1)
      ..setFloat(10, .86)
      ..setFloat(11, .78);
    return paint..shader = shader;
  }

  Paint _flat(Color c, {double stroke = 0}) => Paint()
    ..color = c
    ..isAntiAlias = true
    ..style = stroke > 0 ? PaintingStyle.stroke : PaintingStyle.fill
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Color _darker(Color c, double f) => Color.lerp(c, Colors.black, f)!;
  Color _lighter(Color c, double f) => Color.lerp(c, Colors.white, f)!;

  @override
  void paint(Canvas canvas, Size size) {
    _canvas = canvas;
    _scale = size.width / 240;
    canvas.save();
    canvas.scale(_scale);
    if (background) _background();
    // Breathing: the whole figure bobs a little; the head a little more.
    final breathe = math.sin(t * 2.1) * 1.6;
    canvas.translate(0, breathe * .5);
    _hairBack();
    _body();
    canvas.save();
    canvas.translate(0, breathe * .4);
    _neckAndEars();
    _head();
    _face();
    _beard();
    _hairFront();
    _glasses();
    _accessory();
    canvas.restore();
    canvas.restore();
    // Recorded pictures still use these shaders; let them be collected.
    _shaders.clear();
  }

  // ------------------------------------------------------------ background

  void _background() {
    final style = cfg.s('background');
    if (style == 'none') return;
    final colors = switch (style) {
      'sunset' => [const Color(0xFFFFB58F), const Color(0xFFE795D7)],
      'mint' => [const Color(0xFF68D7CD), const Color(0xFF9DF2C8)],
      'night' => [const Color(0xFF1B1F4B), const Color(0xFF4A3B8F)],
      _ => [const Color(0xFF8D78FF), const Color(0xFFE795D7)],
    };
    final rect = const Rect.fromLTWH(10, 20, 220, 250);
    _canvas.drawCircle(const Offset(120, 140), 112,
        Paint()..shader = LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(rect));
  }

  // ------------------------------------------------------------ geometry

  /// Head box (design units) for the face shape.
  Rect get _headRect => switch (cfg.s('face')) {
        'round' => const Rect.fromLTWH(74, 52, 92, 100),
        'square' => const Rect.fromLTWH(76, 50, 88, 104),
        'heart' => const Rect.fromLTWH(74, 50, 92, 104),
        'long' => const Rect.fromLTWH(80, 44, 80, 114),
        _ => const Rect.fromLTWH(77, 48, 86, 108),
      };

  Path get _headPath {
    final r = _headRect;
    switch (cfg.s('face')) {
      case 'square':
        return Path()..addRRect(RRect.fromRectAndCorners(r,
            topLeft: const Radius.circular(36), topRight: const Radius.circular(36),
            bottomLeft: const Radius.circular(26), bottomRight: const Radius.circular(26)));
      case 'heart':
        return Path()
          ..moveTo(r.left, r.top + r.height * .38)
          ..cubicTo(r.left, r.top - 4, r.right, r.top - 4, r.right, r.top + r.height * .38)
          ..cubicTo(r.right, r.top + r.height * .72, r.center.dx + 14, r.bottom, r.center.dx, r.bottom)
          ..cubicTo(r.center.dx - 14, r.bottom, r.left, r.top + r.height * .72, r.left, r.top + r.height * .38)
          ..close();
      default:
        return Path()
          ..moveTo(r.center.dx, r.top)
          ..cubicTo(r.right + 2, r.top, r.right + 1, r.top + r.height * .62, r.right - 8, r.top + r.height * .8)
          ..cubicTo(r.right - 18, r.bottom, r.left + 18, r.bottom, r.left + 8, r.top + r.height * .8)
          ..cubicTo(r.left - 1, r.top + r.height * .62, r.left - 2, r.top, r.center.dx, r.top)
          ..close();
    }
  }

  // ------------------------------------------------------------ body

  void _body() {
    final top = cfg.s('top');
    final color = cfg.topColor();
    final body = Path()
      ..moveTo(52, 280)
      ..cubicTo(52, 214, 78, 196, 104, 192)
      ..lineTo(136, 192)
      ..cubicTo(162, 196, 188, 214, 188, 280)
      ..close();
    const bodyRect = Rect.fromLTWH(52, 190, 136, 90);
    if (top == 'hoodie') {
      // Hood behind the neck.
      _canvas.drawPath(
          Path()..addOval(const Rect.fromLTWH(84, 172, 72, 40)), _fill(_darker(color, .15), const Rect.fromLTWH(84, 172, 72, 40), 2));
    }
    if (top == 'dress') {
      final dress = Path()
        ..moveTo(72, 280)
        ..cubicTo(74, 230, 88, 204, 102, 200)
        ..lineTo(138, 200)
        ..cubicTo(152, 204, 166, 230, 168, 280)
        ..close();
      // Shoulders show skin with thin straps.
      _canvas.drawPath(body, _fill(cfg.skin(), bodyRect, 0));
      _canvas.drawPath(dress, _fill(color, bodyRect, 2));
      _canvas.drawLine(const Offset(104, 200), const Offset(98, 192), _flat(color, stroke: 4));
      _canvas.drawLine(const Offset(136, 200), const Offset(142, 192), _flat(color, stroke: 4));
      return;
    }
    _canvas.drawPath(body, _fill(color, bodyRect, 2));
    final line = _flat(_darker(color, .28), stroke: 2.2);
    switch (top) {
      case 'tee':
        _canvas.drawArc(const Rect.fromLTWH(104, 180, 32, 26), .2, math.pi - .4, false, line);
      case 'hoodie':
        _canvas.drawLine(const Offset(112, 204), const Offset(110, 232), _flat(Colors.white70, stroke: 2));
        _canvas.drawLine(const Offset(128, 204), const Offset(130, 232), _flat(Colors.white70, stroke: 2));
        _canvas.drawRRect(RRect.fromLTRBR(92, 246, 148, 272, const Radius.circular(8)), line);
      case 'shirt':
        _canvas.drawPath(Path()..moveTo(104, 192)..lineTo(120, 214)..lineTo(136, 192), line);
        _canvas.drawPath(Path()..moveTo(104, 192)..lineTo(98, 206)..lineTo(116, 208), _flat(_lighter(color, .3)));
        _canvas.drawPath(Path()..moveTo(136, 192)..lineTo(142, 206)..lineTo(124, 208), _flat(_lighter(color, .3)));
        for (var y = 222.0; y < 276; y += 16) {
          _canvas.drawCircle(Offset(120, y), 2, _flat(_darker(color, .35)));
        }
      case 'jacket':
        _canvas.drawPath(
            Path()..moveTo(108, 192)..lineTo(120, 230)..lineTo(132, 192)..close(), _flat(const Color(0xFFF2F2F2)));
        _canvas.drawPath(Path()..moveTo(104, 192)..lineTo(116, 236)..lineTo(108, 280), _flat(_darker(color, .3), stroke: 3));
        _canvas.drawPath(Path()..moveTo(136, 192)..lineTo(124, 236)..lineTo(132, 280), _flat(_darker(color, .3), stroke: 3));
      case 'kurta':
        _canvas.drawLine(const Offset(120, 196), const Offset(120, 240), line);
        for (var y = 204.0; y < 240; y += 10) {
          _canvas.drawCircle(Offset(120, y), 1.8, _flat(const Color(0xFFF6D365)));
        }
        _canvas.drawArc(const Rect.fromLTWH(106, 184, 28, 20), .3, math.pi - .6, false, _flat(const Color(0xFFF6D365), stroke: 2));
    }
  }

  void _neckAndEars() {
    final skin = cfg.skin();
    final r = _headRect;
    _canvas.drawRRect(RRect.fromLTRBR(106, r.bottom - 22, 134, 198, const Radius.circular(10)),
        _fill(_darker(skin, .08), Rect.fromLTRB(106, r.bottom - 22, 134, 198), 0));
    final earY = r.top + r.height * .52;
    for (final x in [r.left - 6, r.right - 8]) {
      final ear = Rect.fromLTWH(x, earY - 12, 14, 24);
      _canvas.drawOval(ear, _fill(skin, ear, 0));
    }
  }

  void _head() {
    _canvas.drawPath(_headPath, _fill(cfg.skin(), _headRect, 0));
  }

  // ------------------------------------------------------------ face

  void _face() {
    final r = _headRect;
    final skin = cfg.skin();
    final cx = r.center.dx;
    final eyeY = r.top + r.height * .5;
    final dx = r.width * .2;
    // Blink every ~4 s.
    final cycle = t % 4.2;
    final open = cycle > 4.05 ? (1 - ((cycle - 4.05) / .15 - .5).abs() * 2).clamp(0.0, 1.0) : 0.0;
    final lid = 1 - open; // 1 open, 0 closed
    if (cfg.blush) {
      for (final x in [cx - dx - 4, cx + dx + 4]) {
        _canvas.drawOval(Rect.fromCenter(center: Offset(x, eyeY + 18), width: 18, height: 9),
            Paint()..color = const Color(0x44FF6B81)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
    }
    if (cfg.freckles) {
      final f = _flat(_darker(skin, .35));
      for (final (x, y) in const [(-10.0, 12.0), (-4.0, 15.0), (-12.0, 18.0), (10.0, 12.0), (4.0, 15.0), (12.0, 18.0)]) {
        _canvas.drawCircle(Offset(cx + (x < 0 ? -dx : dx) + x * .4, eyeY + y), 1.1, f);
      }
    }
    // Brows.
    final browC = _darker(cfg.hairColor(), .1);
    final browW = switch (cfg.s('brows')) { 'bold' => 4.6, 'straight' => 3.2, _ => 3.0 };
    for (final side in [-1.0, 1.0]) {
      final bx = cx + side * dx;
      final by = eyeY - 16;
      final path = switch (cfg.s('brows')) {
        'straight' => Path()..moveTo(bx - 9, by)..lineTo(bx + 9, by - side * .5),
        'arched' => Path()..moveTo(bx - 10, by + 2)..quadraticBezierTo(bx, by - 7, bx + 10, by + 1),
        _ => Path()..moveTo(bx - 9, by + 1)..quadraticBezierTo(bx, by - 4, bx + 9, by),
      };
      _canvas.drawPath(path, _flat(browC, stroke: browW));
    }
    // Eyes.
    final eyes = cfg.s('eyes');
    for (final side in [-1.0, 1.0]) {
      final ex = cx + side * dx;
      final winking = eyes == 'wink' && side > 0;
      if (eyes == 'happy' || winking || lid < .15) {
        _canvas.drawArc(Rect.fromCenter(center: Offset(ex, eyeY + 2), width: 16, height: 10), math.pi + .2, math.pi - .4, false,
            _flat(const Color(0xFF231A15), stroke: 2.6));
        continue;
      }
      final h = (eyes == 'sleepy' ? 9.0 : eyes == 'almond' ? 10.0 : 13.0) * lid;
      final w = eyes == 'almond' ? 17.0 : 14.0;
      final white = Rect.fromCenter(center: Offset(ex, eyeY), width: w, height: h);
      _canvas.drawOval(white, _flat(Colors.white));
      _canvas.save();
      _canvas.clipPath(Path()..addOval(white));
      _canvas.drawCircle(Offset(ex + 1, eyeY + .5), 5.2, _flat(cfg.eyeColor()));
      _canvas.drawCircle(Offset(ex + 1, eyeY + .5), 2.6, _flat(const Color(0xFF0B0B0B)));
      _canvas.drawCircle(Offset(ex - .8, eyeY - 1.6), 1.5, _flat(Colors.white));
      if (eyes == 'sleepy') {
        _canvas.drawRect(Rect.fromLTWH(ex - w / 2, eyeY - h / 2, w, h * .45), _flat(_darker(skin, .05)));
      }
      _canvas.restore();
      _canvas.drawArc(white, math.pi + .15, math.pi - .3, false, _flat(const Color(0xFF231A15), stroke: 1.8));
    }
    // Nose.
    final noseY = eyeY + 16;
    _canvas.drawPath(Path()..moveTo(cx - 1, noseY - 10)..quadraticBezierTo(cx + 5, noseY, cx - 3, noseY + 2),
        _flat(_darker(skin, .25), stroke: 2));
    // Mouth.
    final my = r.top + r.height * .8;
    final ink = const Color(0xFF7A2E2E);
    switch (cfg.s('mouth')) {
      case 'grin':
        final m = Path()
          ..moveTo(cx - 14, my - 3)
          ..quadraticBezierTo(cx, my + 14, cx + 14, my - 3)
          ..close();
        _canvas.drawPath(m, _flat(const Color(0xFF5A1F22)));
        _canvas.save();
        _canvas.clipPath(m);
        _canvas.drawRect(Rect.fromLTWH(cx - 14, my - 4, 28, 5), _flat(Colors.white));
        _canvas.restore();
      case 'open':
        _canvas.drawOval(Rect.fromCenter(center: Offset(cx, my + 2), width: 14, height: 12), _flat(const Color(0xFF5A1F22)));
        _canvas.drawOval(Rect.fromCenter(center: Offset(cx, my + 5), width: 8, height: 4), _flat(const Color(0xFFE5737F)));
      case 'smirk':
        _canvas.drawPath(Path()..moveTo(cx - 10, my + 1)..quadraticBezierTo(cx + 2, my + 5, cx + 12, my - 4), _flat(ink, stroke: 2.6));
      case 'neutral':
        _canvas.drawLine(Offset(cx - 9, my + 1), Offset(cx + 9, my + 1), _flat(ink, stroke: 2.6));
      default:
        _canvas.drawPath(Path()..moveTo(cx - 12, my - 2)..quadraticBezierTo(cx, my + 9, cx + 12, my - 2), _flat(ink, stroke: 2.8));
    }
  }

  void _beard() {
    final style = cfg.s('beard');
    if (style == 'none') return;
    final r = _headRect;
    final color = cfg.hairColor();
    final cx = r.center.dx, my = r.top + r.height * .8;
    switch (style) {
      case 'stubble':
        _canvas.save();
        _canvas.clipPath(_headPath);
        _canvas.drawPath(
            Path()
              ..moveTo(r.left, r.top + r.height * .6)
              ..quadraticBezierTo(cx, r.bottom + 30, r.right, r.top + r.height * .6)
              ..lineTo(r.right, r.bottom)
              ..lineTo(r.left, r.bottom)
              ..close(),
            Paint()..color = color.withValues(alpha: .22));
        _canvas.restore();
      case 'moustache':
        _canvas.drawPath(
            Path()..moveTo(cx - 15, my - 2)..quadraticBezierTo(cx, my - 12, cx + 15, my - 2)..quadraticBezierTo(cx, my - 6, cx - 15, my - 2),
            _fill(color, Rect.fromLTWH(cx - 15, my - 12, 30, 10), 1));
      case 'goatee':
        final g = Path()
          ..moveTo(cx - 9, my + 7)
          ..quadraticBezierTo(cx, my + 26, cx + 9, my + 7)
          ..quadraticBezierTo(cx, my + 12, cx - 9, my + 7);
        _canvas.drawPath(g, _fill(color, Rect.fromLTWH(cx - 9, my + 5, 18, 22), 1));
        _canvas.drawPath(
            Path()..moveTo(cx - 13, my - 2)..quadraticBezierTo(cx, my - 10, cx + 13, my - 2)..quadraticBezierTo(cx, my - 5, cx - 13, my - 2),
            _fill(color, Rect.fromLTWH(cx - 13, my - 10, 26, 8), 1));
      default: // short / full: around the jaw, with a gap for the mouth
        final depth = style == 'full' ? 22.0 : 12.0;
        final beard = Path()
          ..moveTo(r.left + 2, r.top + r.height * .55)
          ..quadraticBezierTo(r.left + 4, r.bottom + depth * .4, cx, r.bottom + depth)
          ..quadraticBezierTo(r.right - 4, r.bottom + depth * .4, r.right - 2, r.top + r.height * .55)
          ..quadraticBezierTo(r.right - 10, my + 14, cx, my + 12)
          ..quadraticBezierTo(r.left + 10, my + 14, r.left + 2, r.top + r.height * .55)
          ..close();
        _canvas.drawPath(beard, _fill(color, Rect.fromLTWH(r.left, my - 10, r.width, r.bottom + depth - my + 10), 1));
        _canvas.drawPath(
            Path()..moveTo(cx - 15, my - 2)..quadraticBezierTo(cx, my - 11, cx + 15, my - 2)..quadraticBezierTo(cx, my - 5, cx - 15, my - 2),
            _fill(color, Rect.fromLTWH(cx - 15, my - 11, 30, 9), 1));
    }
  }

  // ------------------------------------------------------------ hair

  void _hairBack() {
    final style = cfg.s('hair');
    final r = _headRect;
    final color = _darker(cfg.hairColor(), .12);
    switch (style) {
      case 'long':
      case 'wavy':
        final back = Rect.fromLTRB(r.left - 14, r.top - 6, r.right + 14, r.bottom + (style == 'long' ? 64 : 40));
        _canvas.drawRRect(RRect.fromRectAndRadius(back, const Radius.circular(46)), _fill(color, back, 1));
      case 'afro':
        final back = Rect.fromCenter(center: Offset(r.center.dx, r.top + 30), width: r.width + 70, height: r.height + 40);
        _canvas.drawOval(back, _fill(color, back, 1));
      case 'ponytail':
        final tail = Rect.fromLTWH(r.right - 10, r.top + 30, 30, 90);
        _canvas.drawRRect(RRect.fromRectAndRadius(tail, const Radius.circular(16)), _fill(color, tail, 1));
    }
  }

  void _hairFront() {
    final style = cfg.s('hair');
    if (style == 'none' || cfg.s('accessory') == 'beanie') {
      return; // a beanie covers the hair
    }
    final r = _headRect;
    final color = cfg.hairColor();
    final cap = Rect.fromLTRB(r.left - 4, r.top - 8, r.right + 4, r.top + r.height * .42);
    Path capPath({double fringe = .36, double side = .5}) => Path()
      ..moveTo(r.left - 3, r.top + r.height * side)
      ..cubicTo(r.left - 6, r.top - 14, r.right + 6, r.top - 14, r.right + 3, r.top + r.height * side)
      ..quadraticBezierTo(r.right - 6, r.top + r.height * fringe * .5, r.center.dx + 10, r.top + r.height * fringe * .55)
      ..quadraticBezierTo(r.center.dx - 16, r.top + r.height * fringe, r.left - 3, r.top + r.height * side)
      ..close();
    switch (style) {
      case 'buzz':
        _canvas.save();
        _canvas.clipPath(_headPath);
        _canvas.drawRect(Rect.fromLTRB(r.left, r.top - 4, r.right, r.top + r.height * .22), _fill(color.withValues(alpha: 1), cap, 1));
        _canvas.restore();
      case 'quiff':
        final q = capPath(fringe: .3, side: .42);
        q.addOval(Rect.fromLTWH(r.center.dx - 26, r.top - 26, 52, 36));
        _canvas.drawPath(q, _fill(color, Rect.fromLTRB(cap.left, r.top - 26, cap.right, cap.bottom), 1));
      case 'curly':
      case 'afro':
        final p = capPath(fringe: .3, side: .45);
        final big = style == 'afro' ? 15.0 : 11.0;
        for (var i = 0; i < 9; i++) {
          final a = math.pi + i * math.pi / 8;
          p.addOval(Rect.fromCircle(
              center: Offset(r.center.dx + math.cos(a) * (r.width / 2 + 2), r.top + 26 + math.sin(a) * 34), radius: big));
        }
        _canvas.drawPath(p, _fill(color, Rect.fromLTRB(cap.left - 14, r.top - 22, cap.right + 14, cap.bottom), 1));
      case 'side':
        final p = Path()
          ..moveTo(r.left - 4, r.top + r.height * .5)
          ..cubicTo(r.left - 8, r.top - 16, r.right + 8, r.top - 12, r.right + 4, r.top + r.height * .4)
          ..quadraticBezierTo(r.right - 20, r.top + 8, r.left + 18, r.top + r.height * .34)
          ..close();
        _canvas.drawPath(p, _fill(color, cap, 1));
      case 'bun':
        _canvas.drawPath(capPath(fringe: .28), _fill(color, cap, 1));
        final bun = Rect.fromCircle(center: Offset(r.center.dx, r.top - 12), radius: 20);
        _canvas.drawOval(bun, _fill(color, bun, 1));
      case 'wavy':
      case 'long':
        final p = capPath(fringe: .34, side: .62);
        _canvas.drawPath(p, _fill(color, Rect.fromLTRB(cap.left, cap.top, cap.right, r.top + r.height * .62), 1));
        // Locks falling past the cheeks.
        for (final side in [-1.0, 1.0]) {
          final x = side < 0 ? r.left - 4 : r.right - 10;
          final lock = Rect.fromLTWH(x, r.top + r.height * .3, 14, r.height * .75);
          _canvas.drawRRect(RRect.fromRectAndRadius(lock, const Radius.circular(8)), _fill(color, lock, 1));
        }
      case 'ponytail':
        _canvas.drawPath(capPath(fringe: .3), _fill(color, cap, 1));
      default: // short
        _canvas.drawPath(capPath(), _fill(color, cap, 1));
    }
  }

  // ------------------------------------------------------------ extras

  void _glasses() {
    final style = cfg.s('glasses');
    if (style == 'none') return;
    final r = _headRect;
    final cx = r.center.dx, ey = r.top + r.height * .5, dx = r.width * .2;
    final frame = _flat(style == 'aviator' ? const Color(0xFFC9A64A) : const Color(0xFF15171C), stroke: 2.8);
    final tint = Paint()..color = style == 'sun' ? const Color(0xE0101114) : const Color(0x22B8D8FF);
    for (final side in [-1.0, 1.0]) {
      final c = Offset(cx + side * dx, ey);
      final shape = switch (style) {
        'round' => Rect.fromCircle(center: c, radius: 11),
        'aviator' => Rect.fromCenter(center: c.translate(0, 2), width: 24, height: 20),
        _ => Rect.fromCenter(center: c, width: 25, height: 18),
      };
      final rr = style == 'square' || style == 'sun'
          ? RRect.fromRectAndRadius(shape, const Radius.circular(5))
          : RRect.fromRectAndRadius(shape, Radius.circular(shape.height / 2));
      _canvas.drawRRect(rr, tint);
      _canvas.drawRRect(rr, frame);
    }
    _canvas.drawLine(Offset(cx - dx + 12, ey - 2), Offset(cx + dx - 12, ey - 2), frame);
    _canvas.drawLine(Offset(r.left, ey - 4), Offset(cx - dx - 12, ey - 3), frame);
    _canvas.drawLine(Offset(r.right, ey - 4), Offset(cx + dx + 12, ey - 3), frame);
  }

  void _accessory() {
    final r = _headRect;
    final cx = r.center.dx;
    switch (cfg.s('accessory')) {
      case 'earrings':
        for (final x in [r.left - 0.0, r.right - 2]) {
          _canvas.drawCircle(Offset(x, r.top + r.height * .66), 3.5, _flat(const Color(0xFFF6D365)));
        }
      case 'bindi':
        _canvas.drawCircle(Offset(cx, r.top + r.height * .36), 3.2, _flat(const Color(0xFFD7263D)));
      case 'nose_ring':
        _canvas.drawArc(Rect.fromCircle(center: Offset(cx - 5, r.top + r.height * .68), radius: 3.5), -.5, 4.2, false,
            _flat(const Color(0xFFF6D365), stroke: 1.6));
      case 'cap':
        final crown = Rect.fromLTRB(r.left - 6, r.top - 18, r.right + 6, r.top + r.height * .3);
        _canvas.drawPath(
            Path()
              ..moveTo(crown.left, crown.bottom)
              ..cubicTo(crown.left, crown.top, crown.right, crown.top, crown.right, crown.bottom)
              ..close(),
            _fill(cfg.topColor(), crown, 2));
        _canvas.drawRRect(RRect.fromLTRBR(cx - 8, crown.bottom - 8, r.right + 26, crown.bottom + 2, const Radius.circular(6)),
            _fill(_darker(cfg.topColor(), .2), Rect.fromLTRB(cx, crown.bottom - 8, r.right + 26, crown.bottom + 2), 2));
      case 'beanie':
        final hat = Rect.fromLTRB(r.left - 6, r.top - 24, r.right + 6, r.top + r.height * .36);
        _canvas.drawRRect(RRect.fromRectAndCorners(hat, topLeft: const Radius.circular(44), topRight: const Radius.circular(44)),
            _fill(cfg.topColor(), hat, 2));
        _canvas.drawRRect(RRect.fromLTRBR(hat.left - 2, hat.bottom - 14, hat.right + 2, hat.bottom + 2, const Radius.circular(6)),
            _fill(_darker(cfg.topColor(), .18), hat, 2));
        _canvas.drawCircle(Offset(cx, hat.top + 2), 10, _fill(_lighter(cfg.topColor(), .3), Rect.fromCircle(center: Offset(cx, hat.top), radius: 10), 2));
      case 'headphones':
        final band = _flat(const Color(0xFF1C1F26), stroke: 6);
        _canvas.drawArc(Rect.fromLTRB(r.left - 10, r.top - 18, r.right + 10, r.top + r.height * .9), math.pi, math.pi, false, band);
        for (final x in [r.left - 14, r.right]) {
          final cup = Rect.fromLTWH(x, r.top + r.height * .4, 16, 30);
          _canvas.drawRRect(RRect.fromRectAndRadius(cup, const Radius.circular(8)), _fill(const Color(0xFF2A2E37), cup, 2));
        }
    }
  }

  @override
  bool shouldRepaint(AvatarPainter old) => old.t != t || old.cfg != cfg || old.program != program;
}
