// Ready-made themes for profiles and DMs.
//
// "Hacker" is an original Phlio design in a zine / hacker-collage style:
// halftone sonar rings, a torn accent strip, CRT scanlines and glitch slices
// (assets/shaders/hacker_theme.frag), with retro pop-up windows, a comic
// burst sticker, a terminal ticker and a pixel hooded Foxy on top. It comes
// in four accents. The other themes are listed as "coming soon".

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'appearance.dart';

@immutable
class AppearanceTheme {
  const AppearanceTheme({
    required this.id,
    required this.name,
    required this.icon,
    required this.colors,
    this.accent = const Color(0xFF3BFF5C),
    this.effect = AppearanceEffect.none,
    this.available = false,
  });

  final String id;
  final String name;
  final IconData icon;

  /// Card gradient (for "coming soon" cards).
  final List<Color> colors;
  final Color accent;

  /// The effect the theme starts with.
  final AppearanceEffect effect;
  final bool available;

  /// The appearance that applies this theme.
  Appearance get appearance => Appearance(
        template: id,
        background: const Color(0xFF050605),
        effect: effect,
        effectColor: accent,
        intensity: 0.55,
      );
}

const appearanceThemes = <AppearanceTheme>[
  AppearanceTheme(
    id: 'hacker_green',
    name: 'Hacker · Green',
    icon: Icons.terminal_rounded,
    colors: [Color(0xFF050605), Color(0xFF113A12)],
    accent: Color(0xFF3BFF5C),
    effect: AppearanceEffect.matrix,
    available: true,
  ),
  AppearanceTheme(
    id: 'hacker_violet',
    name: 'Hacker · Violet',
    icon: Icons.terminal_rounded,
    colors: [Color(0xFF07040A), Color(0xFF3A1350)],
    accent: Color(0xFFB45CFF),
    effect: AppearanceEffect.glitch,
    available: true,
  ),
  AppearanceTheme(
    id: 'hacker_red',
    name: 'Hacker · Red',
    icon: Icons.terminal_rounded,
    colors: [Color(0xFF0A0404), Color(0xFF4A1013)],
    accent: Color(0xFFFF3B47),
    effect: AppearanceEffect.glitch,
    available: true,
  ),
  AppearanceTheme(
    id: 'hacker_mono',
    name: 'Hacker · Mono',
    icon: Icons.terminal_rounded,
    colors: [Color(0xFF050505), Color(0xFF2B2B2B)],
    accent: Color(0xFFE6E6E6),
    effect: AppearanceEffect.matrix,
    available: true,
  ),
  AppearanceTheme(
    id: 'gaming',
    name: 'Gaming',
    icon: Icons.sports_esports_rounded,
    colors: [Color(0xFF1B0B3A), Color(0xFF00C2FF)],
  ),
  AppearanceTheme(
    id: 'space_crew',
    name: 'Space crew',
    icon: Icons.rocket_launch_rounded,
    colors: [Color(0xFF0B1030), Color(0xFFE53935)],
  ),
  AppearanceTheme(
    id: 'arcade',
    name: 'Retro arcade',
    icon: Icons.videogame_asset_rounded,
    colors: [Color(0xFF2A0845), Color(0xFFFF6A00)],
  ),
  AppearanceTheme(
    id: 'anime',
    name: 'Anime',
    icon: Icons.auto_awesome_rounded,
    colors: [Color(0xFFFFB6D9), Color(0xFF7B8CFF)],
  ),
  AppearanceTheme(
    id: 'cyberpunk',
    name: 'Cyberpunk',
    icon: Icons.location_city_rounded,
    colors: [Color(0xFFFF2A6D), Color(0xFF05D9E8)],
  ),
  AppearanceTheme(
    id: 'lofi',
    name: 'Lo-fi café',
    icon: Icons.local_cafe_rounded,
    colors: [Color(0xFF3E2723), Color(0xFFD7A86E)],
  ),
  AppearanceTheme(
    id: 'nature',
    name: 'Nature',
    icon: Icons.forest_rounded,
    colors: [Color(0xFF0B3D2E), Color(0xFF9BC53D)],
  ),
];

AppearanceTheme? appearanceThemeById(String id) {
  for (final t in appearanceThemes) {
    if (t.id == id) return t;
  }
  return null;
}

// -- Hacker backdrop --------------------------------------------------------------------

class _HackerShader {
  static Future<ui.FragmentProgram?>? _loading;
  static Future<ui.FragmentProgram?> load() => _loading ??= () async {
        try {
          return await ui.FragmentProgram.fromAsset(
              'assets/shaders/hacker_theme.frag');
        } catch (e) {
          debugPrint('hacker_theme shader unavailable: $e');
          return null;
        }
      }();
}

/// A theme's base layer (behind the effect and the page content).
class ThemeBackdrop extends StatefulWidget {
  const ThemeBackdrop({
    required this.theme,
    this.animate = true,
    this.decorate = true,
    super.key,
  });

  final AppearanceTheme theme;
  final bool animate;
  final bool decorate;

  @override
  State<ThemeBackdrop> createState() => _ThemeBackdropState();
}

class _ThemeBackdropState extends State<ThemeBackdrop>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _a, _b;
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(4);

  @override
  void initState() {
    super.initState();
    _HackerShader.load().then((p) {
      if (p != null && mounted) {
        setState(() {
          _a = p.fragmentShader();
          _b = p.fragmentShader();
        });
      }
    });
    _ticker = createTicker((e) => _time.value = 4 + e.inMicroseconds / 1e6);
    if (widget.animate) _ticker.start();
  }

  @override
  void didUpdateWidget(ThemeBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _a?.dispose();
    _b?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.theme.accent;
    if (MediaQuery.disableAnimationsOf(context) && _ticker.isActive) {
      _ticker.stop();
    }
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Color(0xFF050605)),
      if (_a != null && _b != null)
        RepaintBoundary(
          child: CustomPaint(
            painter: _HackerPainter(_a!, _b!, accent, _time),
          ),
        )
      else
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.15),
              radius: 1.1,
              colors: [accent.withValues(alpha: 0.18), const Color(0xFF050605)],
            ),
          ),
        ),
      if (widget.decorate)
        _HackerDecorations(accent: accent, time: _time),
    ]);
  }
}

class _HackerPainter extends CustomPainter {
  _HackerPainter(this.a, this.b, this.accent, this.time) : super(repaint: time);
  final ui.FragmentShader a, b;
  final Color accent;
  final ValueNotifier<double> time;
  bool _flip = false;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _flip = !_flip;
    final shader = _flip ? b : a;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, accent.r)
      ..setFloat(4, accent.g)
      ..setFloat(5, accent.b)
      ..setFloat(6, 1);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_HackerPainter old) => old.accent != accent || old.a != a;
}

/// Pop-up window, comic burst, pixel hooded Foxy and a terminal ticker.
/// Kept to the edges and translucent so the page stays readable.
class _HackerDecorations extends StatelessWidget {
  const _HackerDecorations({required this.accent, required this.time});
  final Color accent;
  final ValueNotifier<double> time;

  static const _lines = [
    '> ssh foxy@phlio-node-07',
    '> handshake ......... ok',
    '> decrypting feed ... 100%',
    '> hello, world',
    '> stay curious_',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final small = h < 300;
      return ValueListenableBuilder<double>(
        valueListenable: time,
        builder: (context, t, _) {
          // A glitch "jump" every few seconds.
          final jitter = (t % 4.0) < 0.12 ? (math.sin(t * 90) * 6) : 0.0;
          final line = _lines[(t ~/ 2.4) % _lines.length];
          final typed = ((t % 2.4) / 1.4).clamp(0.0, 1.0);
          return Stack(children: [
            if (!small)
              Positioned(
                left: 14 + jitter,
                top: h * 0.12,
                child: Opacity(
                  opacity: 0.55,
                  child: _RetroWindow(
                    accent: accent,
                    title: 'SYS_ALERT.EXE',
                    message: 'ACCESS GRANTED',
                  ),
                ),
              ),
            if (!small)
              Positioned(
                right: -10,
                top: h * 0.46,
                child: Opacity(
                  opacity: 0.3,
                  child: CustomPaint(
                    size: Size.square(math.min(150, w * 0.38)),
                    painter: _PixelHoodPainter(accent),
                  ),
                ),
              ),
            Positioned(
              right: small ? 6 : 12,
              bottom: small ? 30 : h * 0.16,
              child: Transform.rotate(
                angle: -0.2,
                child: Opacity(
                  opacity: 0.82,
                  child: _Burst(
                      accent: accent, text: '#ROOT\nACCESS!', size: small ? 70 : 108),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(
                  line.substring(0, (line.length * typed).round()) +
                      ((t * 2).floor().isEven ? '█' : ' '),
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: small ? 9 : 11,
                    color: accent,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ]);
        },
      );
    });
  }
}

class _RetroWindow extends StatelessWidget {
  const _RetroWindow(
      {required this.accent, required this.title, required this.message});
  final Color accent;
  final String title, message;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 10, letterSpacing: 1);
    return Container(
      width: 168,
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          color: const Color(0xFF3A3A3A),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(title,
                    style: mono.copyWith(color: Colors.white, fontSize: 9))),
            Container(
              width: 12,
              height: 12,
              alignment: Alignment.center,
              color: accent,
              child: const Text('×',
                  style: TextStyle(fontSize: 10, height: 1, color: Colors.black)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: const Text('i',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: Colors.black)),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style: mono.copyWith(
                        color: Colors.black, fontWeight: FontWeight.w700))),
          ]),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black),
            color: const Color(0xFFEDEDED),
          ),
          child: Text('OK', style: mono.copyWith(color: Colors.black)),
        ),
      ]),
    );
  }
}

/// A comic starburst sticker with shouty text.
class _Burst extends StatelessWidget {
  const _Burst({required this.accent, required this.text, required this.size});
  final Color accent;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BurstPainter(accent),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * 0.15,
              height: 1.0,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path();
    const spikes = 14;
    for (var i = 0; i < spikes * 2; i++) {
      final r = (i.isEven ? 0.5 : 0.36) * size.width * (i % 4 == 0 ? 1.0 : 0.94);
      final a = i * math.pi / spikes;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path.shift(const Offset(3, 3)), Paint()..color = accent);
    canvas.drawPath(path, Paint()..color = const Color(0xFFD6D6D6));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black);
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.accent != accent;
}

/// An 8-bit hooded Foxy: hood with fox ears, a dark face and glowing eyes.
class _PixelHoodPainter extends CustomPainter {
  _PixelHoodPainter(this.accent);
  final Color accent;

  // 16×16: H = hood, F = face shadow, E = eye, . = empty.
  static const _art = [
    '..H..........H..',
    '.HHH........HHH.',
    '.HHHH......HHHH.',
    '.HHHHHHHHHHHHHH.',
    'HHHHHHHHHHHHHHHH',
    'HHHFFFFFFFFFFHHH',
    'HHFFFFFFFFFFFFHH',
    'HHFFEEFFFFEEFFHH',
    'HHFFEEFFFFEEFFHH',
    'HHFFFFFFFFFFFFHH',
    'HHHFFFFFFFFFFHHH',
    'HHHHFFFFFFFFHHHH',
    '.HHHHHFFFFHHHHH.',
    'HHHHHHHHHHHHHHHH',
    'HHHHHHHHHHHHHHHH',
    'HHHHHHHHHHHHHHHH',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / 16;
    final hood = Paint()..color = const Color(0xFFE8E8E8);
    final face = Paint()..color = const Color(0xFF0B0B0B);
    final eye = Paint()..color = accent;
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final ch = _art[y][x];
        if (ch == '.') continue;
        final rect = Rect.fromLTWH(x * px, y * px, px * 0.9, px * 0.9);
        canvas.drawRect(rect, ch == 'H' ? hood : ch == 'F' ? face : eye);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelHoodPainter old) => old.accent != accent;
}
