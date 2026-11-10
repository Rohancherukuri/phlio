// Appearance: the look behind a profile or a DM conversation.
//
// One model ([Appearance]) for both: a background colour, a wallpaper (a
// live shader wallpaper from the moment-template backdrops, or an uploaded
// photo), a dim for legibility, and an animated GPU effect drawn on top
// (assets/shaders/profile_fx.frag: sparkles, snow, aurora, stars, bokeh,
// fireflies).
//
// Server: GET/PUT /appearance/me, GET /appearance/users/{username},
// GET/PUT /appearance/chats/{username}, POST /appearance/wallpaper.
// [AppearanceBackdrop] paints any of it behind a child.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../moments/templates/template_canvas.dart';
import '../moments/templates/template_model.dart';
import 'themes.dart';

/// Animated effects (index = uEffect in the shader).
enum AppearanceEffect {
  none('None', Icons.block_rounded),
  sparkles('Sparkles', Icons.auto_awesome_rounded),
  snow('Snow', Icons.ac_unit_rounded),
  aurora('Aurora', Icons.waves_rounded),
  stars('Stars', Icons.nights_stay_rounded),
  bokeh('Bokeh', Icons.bubble_chart_rounded),
  fireflies('Fireflies', Icons.flare_rounded),
  hearts('Hearts', Icons.favorite_rounded),
  confetti('Confetti', Icons.celebration_rounded),
  rain('Rain', Icons.water_drop_rounded),
  petals('Petals', Icons.local_florist_rounded),
  bubbles('Bubbles', Icons.bubble_chart_outlined),
  galaxy('Galaxy', Icons.blur_on_rounded),
  matrix('Code rain', Icons.terminal_rounded),
  glitch('Glitch', Icons.broken_image_outlined);

  const AppearanceEffect(this.label, this.icon);
  final String label;
  final IconData icon;

  static AppearanceEffect byName(String? name) => AppearanceEffect.values
      .firstWhere((e) => e.name == name, orElse: () => AppearanceEffect.none);
}

enum WallpaperType { none, live, photo }

/// Colours offered for backgrounds and effect tints.
const appearanceSwatches = <Color>[
  Color(0xFF080E16),
  Color(0xFF1B1530),
  Color(0xFF26113A),
  Color(0xFF0E2A3B),
  Color(0xFF0F3B2E),
  Color(0xFF3A1A1F),
  Color(0xFF3B2A12),
  Color(0xFF2B2F36),
  Color(0xFF8D78FF),
  Color(0xFFE795D7),
  Color(0xFFFFB58F),
  Color(0xFF72A7FF),
  Color(0xFF68D7CD),
  Color(0xFFFFD27A),
  Color(0xFFF5636B),
  Color(0xFFF7F7FA),
];

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? _color(Object? value) {
  if (value is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
    return null;
  }
  return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
}

@immutable
class Appearance {
  const Appearance({
    this.background,
    this.wallpaper = WallpaperType.none,
    this.liveStyle = BackdropStyle.mesh,
    this.palette = 0,
    this.photoUrl,
    this.dim = 0.35,
    this.effect = AppearanceEffect.none,
    this.effectColor = const Color(0xFFFFD27A),
    this.intensity = 0.7,
    this.template,
  });

  /// A ready-made theme id (see themes.dart, e.g. `hacker_green`). When set
  /// it replaces the background and wallpaper; the effect still applies.
  final String? template;

  final Color? background;
  final WallpaperType wallpaper;
  final BackdropStyle liveStyle;
  final int palette;
  final String? photoUrl;
  final double dim;
  final AppearanceEffect effect;
  final Color effectColor;
  final double intensity;

  static const plain = Appearance();

  bool get isPlain =>
      template == null &&
      background == null &&
      wallpaper == WallpaperType.none &&
      effect == AppearanceEffect.none;

  Appearance copyWith({
    Color? background,
    bool clearBackground = false,
    WallpaperType? wallpaper,
    BackdropStyle? liveStyle,
    int? palette,
    String? photoUrl,
    double? dim,
    AppearanceEffect? effect,
    Color? effectColor,
    double? intensity,
    String? template,
    bool clearTemplate = false,
  }) =>
      Appearance(
        template: clearTemplate ? null : (template ?? this.template),
        background: clearBackground ? null : (background ?? this.background),
        wallpaper: wallpaper ?? this.wallpaper,
        liveStyle: liveStyle ?? this.liveStyle,
        palette: palette ?? this.palette,
        photoUrl: photoUrl ?? this.photoUrl,
        dim: dim ?? this.dim,
        effect: effect ?? this.effect,
        effectColor: effectColor ?? this.effectColor,
        intensity: intensity ?? this.intensity,
      );

  factory Appearance.fromJson(Map<String, dynamic> json) {
    final wall = (json['wallpaper'] as Map?)?.cast<String, dynamic>() ?? {};
    final type = WallpaperType.values.firstWhere(
        (t) => t.name == wall['type'],
        orElse: () => WallpaperType.none);
    return Appearance(
      background: _color(json['background']),
      wallpaper: type,
      liveStyle: BackdropStyle.values.firstWhere(
          (s) => s.name == wall['style'],
          orElse: () => BackdropStyle.mesh),
      palette: ((wall['palette'] as num?)?.toInt() ?? 0)
          .clamp(0, backdropPalettes.length - 1),
      photoUrl: wall['url'] as String?,
      dim: (json['dim'] as num?)?.toDouble() ?? 0.35,
      effect: AppearanceEffect.byName(json['effect'] as String?),
      effectColor: _color(json['effect_color']) ?? const Color(0xFFFFD27A),
      intensity: (json['intensity'] as num?)?.toDouble() ?? 0.7,
      template: json['template'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'background': background == null ? null : _hex(background!),
        'wallpaper': {
          'type': wallpaper == WallpaperType.photo && photoUrl == null
              ? 'none'
              : wallpaper.name,
          'style': liveStyle.name,
          'palette': palette,
          if (wallpaper == WallpaperType.photo) 'url': photoUrl,
        },
        'dim': dim,
        'effect': effect.name,
        'effect_color': _hex(effectColor),
        'intensity': intensity,
        'template': template,
      };

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.background == background &&
      other.wallpaper == wallpaper &&
      other.liveStyle == liveStyle &&
      other.palette == palette &&
      other.photoUrl == photoUrl &&
      other.dim == dim &&
      other.effect == effect &&
      other.effectColor == effectColor &&
      other.intensity == intensity &&
      other.template == template;

  @override
  int get hashCode => Object.hash(background, wallpaper, liveStyle, palette,
      photoUrl, dim, effect, effectColor, intensity, template);
}

// -- API -------------------------------------------------------------------------------

class AppearanceApi {
  Dio get _dio => getIt<ApiClient>().dio;

  Future<Appearance> mine() async => Appearance.fromJson(
      ((await _dio.get('/appearance/me')).data as Map).cast());

  Future<Appearance> saveMine(Appearance a) async => Appearance.fromJson(
      ((await _dio.put('/appearance/me', data: a.toJson())).data as Map)
          .cast());

  Future<Appearance> ofUser(String username) async => Appearance.fromJson(
      ((await _dio.get('/appearance/users/${Uri.encodeComponent(username)}'))
              .data as Map)
          .cast());

  Future<Appearance> chat(String username) async => Appearance.fromJson(
      ((await _dio.get('/appearance/chats/${Uri.encodeComponent(username)}'))
              .data as Map)
          .cast());

  Future<Appearance> saveChat(String username, Appearance a) async =>
      Appearance.fromJson(((await _dio.put(
                  '/appearance/chats/${Uri.encodeComponent(username)}',
                  data: a.toJson()))
              .data as Map)
          .cast());

  /// Uploads a wallpaper photo; returns its `/media/wallpapers/…` url.
  Future<String> uploadWallpaper(String path) async {
    final response = await _dio.post('/appearance/wallpaper',
        data: FormData.fromMap({'file': await MultipartFile.fromFile(path)}));
    return (response.data as Map)['url'] as String;
  }

  /// Saves the bio (and optionally the display name); returns the user json.
  Future<Map<String, dynamic>> saveProfileText(
          {required String bio, String? fullName}) async =>
      ((await _dio.put('/auth/me/profile', data: {
        'bio': bio,
        if (fullName != null) 'full_name': fullName,
      }))
              .data as Map)
          .cast();
}

final appearanceApiProvider = Provider((ref) => AppearanceApi());

/// Local copy of looks (this device), so a saved look shows at once and
/// survives offline or an API that doesn't have /appearance yet. Entries
/// marked `pending` are pushed to the server the next time they load.
class AppearanceCache {
  static Map<String, dynamic>? _data;

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}appearance_cache.json');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _all() async {
    if (_data != null) return _data!;
    try {
      final f = await _file();
      if (f != null && f.existsSync()) {
        return _data = (jsonDecode(await f.readAsString()) as Map)
            .cast<String, dynamic>();
      }
    } catch (_) {}
    return _data = {};
  }

  static Future<(Appearance, bool)?> read(String key) async {
    final entry = (await _all())[key];
    if (entry is! Map) return null;
    return (
      Appearance.fromJson((entry['look'] as Map).cast()),
      entry['pending'] == true
    );
  }

  static Future<void> write(String key, Appearance look,
      {bool pending = false}) async {
    final all = await _all();
    all[key] = {'look': look.toJson(), 'pending': pending};
    try {
      await (await _file())?.writeAsString(jsonEncode(all));
    } catch (_) {}
  }
}

/// Loads a look: server first, falling back to this device's copy; a
/// pending local save is pushed (or kept if the server can't take it yet).
Future<Appearance> _loadLook(
  String cacheKey,
  Future<Appearance> Function() fetch,
  Future<Appearance> Function(Appearance)? push,
) async {
  final local = await AppearanceCache.read(cacheKey);
  if (local != null && local.$2 && push != null) {
    try {
      final saved = await push(local.$1);
      await AppearanceCache.write(cacheKey, saved);
      return saved;
    } catch (_) {
      return local.$1;
    }
  }
  try {
    final remote = await fetch();
    await AppearanceCache.write(cacheKey, remote);
    return remote;
  } catch (e) {
    debugPrint('Appearance: using the copy on this device ($e)');
    return local?.$1 ?? Appearance.plain;
  }
}

/// Saves a look: on this device first (so it applies immediately), then on
/// the server. Returns true when the server has it too.
Future<bool> saveLook(String cacheKey, Appearance look,
    Future<Appearance> Function(Appearance) push) async {
  await AppearanceCache.write(cacheKey, look, pending: true);
  try {
    final saved = await push(look);
    await AppearanceCache.write(cacheKey, saved);
    return true;
  } catch (e) {
    debugPrint('Appearance: saved on this device only ($e)');
    return false;
  }
}

/// The signed-in person's profile look.
final myAppearanceProvider = FutureProvider<Appearance>((ref) async {
  final me = ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final api = ref.watch(appearanceApiProvider);
  return _loadLook('me:$me', api.mine, api.saveMine);
});

/// Someone's profile look (their profile page).
final userAppearanceProvider =
    FutureProvider.family<Appearance, String>((ref, username) async {
  final api = ref.watch(appearanceApiProvider);
  return _loadLook('user:$username', () => api.ofUser(username), null);
});

/// The shared theme of a DM conversation with [username].
final chatAppearanceProvider =
    FutureProvider.family<Appearance, String>((ref, username) async {
  final me = ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final api = ref.watch(appearanceApiProvider);
  return _loadLook('chat:$me:$username', () => api.chat(username),
      (a) => api.saveChat(username, a));
});

/// Cache key helpers for saving.
String myLookKey(String userId) => 'me:$userId';
String chatLookKey(String userId, String username) => 'chat:$userId:$username';

/// Whether an account is private (lock on the profile).
final accountPrivateProvider = FutureProvider<bool>((ref) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  try {
    final r = await getIt<ApiClient>().dio.get('/account/privacy');
    return (r.data as Map)['private'] == true;
  } catch (_) {
    return false;
  }
});

Future<void> setAccountPrivate(bool value) =>
    getIt<ApiClient>().dio.put('/account/privacy', data: {'private': value});

// -- Rendering ---------------------------------------------------------------------------

/// Loads assets/shaders/profile_fx.frag once.
class AppearanceShader {
  static ui.FragmentProgram? program;
  static Future<ui.FragmentProgram?>? _loading;

  static Future<ui.FragmentProgram?> load() => _loading ??= () async {
        try {
          return program = await ui.FragmentProgram.fromAsset(
              'assets/shaders/profile_fx.frag');
        } catch (e) {
          // Drawn on the CPU instead (see _ParticlePainter).
          debugPrint('profile_fx shader unavailable: $e');
          return null;
        }
      }();
}

/// Paints [appearance] behind [child]: colour → wallpaper (+dim) → effect.
/// Cross-fades when the appearance changes, so edits feel smooth.
class AppearanceBackdrop extends StatelessWidget {
  const AppearanceBackdrop({
    required this.appearance,
    this.child,
    this.fallback,
    this.animate = true,
    this.decorate = true,
    super.key,
  });

  final Appearance appearance;
  final Widget? child;

  /// Theme decorations (pop-up windows, stickers, ticker). Off behind chat
  /// messages so they stay readable.
  final bool decorate;

  /// Shown when the appearance is plain (the screen's normal background).
  final Color? fallback;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final a = appearance;
    final theme = a.template == null ? null : appearanceThemeById(a.template!);
    final layers = theme != null && theme.available
        ? KeyedSubtree(
            key: ValueKey('theme-${theme.id}-$decorate'),
            child: ThemeBackdrop(
                theme: theme, animate: animate, decorate: decorate),
          )
        : Stack(
      // Cross-fade only when the base changes; dim, tint and intensity
      // update in place so sliders stay smooth.
      key: ValueKey(Object.hash(
          a.background, a.wallpaper, a.liveStyle, a.palette, a.photoUrl)),
      fit: StackFit.expand,
      children: [
        ColoredBox(color: a.background ?? fallback ?? Colors.transparent),
        if (a.wallpaper == WallpaperType.live)
          TemplateBackdrop(
            backdrop: TBackdrop(a.liveStyle, [...backdropPalettes[a.palette]],
                grain: .15),
            animate: animate,
          ),
        if (a.wallpaper == WallpaperType.photo && a.photoUrl != null)
          Image.network(
            AppConfig.mediaUrl(a.photoUrl!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (a.wallpaper != WallpaperType.none && a.dim > 0)
          ColoredBox(color: Colors.black.withValues(alpha: a.dim)),
      ],
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              child: layers,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: a.effect == AppearanceEffect.none
                  ? const SizedBox.expand(key: ValueKey('no-fx'))
                  : EffectLayer(
                      key: ValueKey(a.effect),
                      effect: a.effect,
                      color: a.effectColor,
                      intensity: a.intensity,
                      animate: animate,
                    ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// The animated GPU effect alone (transparent elsewhere).
class EffectLayer extends StatefulWidget {
  const EffectLayer({
    required this.effect,
    required this.color,
    this.intensity = 0.7,
    this.animate = true,
    super.key,
  });

  final AppearanceEffect effect;
  final Color color;
  final double intensity;
  final bool animate;

  @override
  State<EffectLayer> createState() => _EffectLayerState();
}

class _EffectLayerState extends State<EffectLayer>
    with SingleTickerProviderStateMixin {
  // Two instances, alternated each frame so the picture always repaints.
  ui.FragmentShader? _shader, _shaderB;
  bool _noShader = false;
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(3);

  @override
  void initState() {
    super.initState();
    AppearanceShader.load().then((p) {
      if (!mounted) return;
      setState(() {
        if (p == null) {
          _noShader = true;
        } else {
          _shader = p.fragmentShader();
          _shaderB = p.fragmentShader();
        }
      });
    });
    _ticker = createTicker((e) => _time.value = 3 + e.inMicroseconds / 1e6);
    if (widget.animate) _ticker.start();
  }

  @override
  void didUpdateWidget(EffectLayer old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    _shaderB?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader, shaderB = _shaderB;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && _ticker.isActive) _ticker.stop();
    if (widget.effect == AppearanceEffect.none) return const SizedBox.expand();
    if (shader == null || shaderB == null) {
      if (!_noShader) return const SizedBox.expand();
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ParticlePainter(
              widget.effect, widget.color, widget.intensity, _time),
        ),
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _EffectPainter(shader, shaderB, widget.effect, widget.color,
            widget.intensity, _time),
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  _EffectPainter(this.shaderA, this.shaderB, this.effect, this.color,
      this.intensity, this.time)
      : super(repaint: time);
  final ui.FragmentShader shaderA, shaderB;
  bool _flip = false;
  final AppearanceEffect effect;
  final Color color;
  final double intensity;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _flip = !_flip;
    final shader = _flip ? shaderB : shaderA;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, effect.index.toDouble())
      ..setFloat(4, color.r)
      ..setFloat(5, color.g)
      ..setFloat(6, color.b)
      ..setFloat(7, intensity);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_EffectPainter old) =>
      old.effect != effect ||
      old.color != color ||
      old.intensity != intensity ||
      old.shaderA != shaderA;
}

/// CPU version of the effects, for devices where the shader can't load:
/// the same looks drawn as particles with Canvas.
class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.effect, this.color, this.intensity, this.time)
      : super(repaint: time);
  final AppearanceEffect effect;
  final Color color;
  final double intensity;
  final ValueNotifier<double> time;

  static double _h(int i, int salt) {
    final x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  static const _confetti = [
    Color(0xFFFFB58F), Color(0xFF8D78FF), Color(0xFF68D7CD),
    Color(0xFFE795D7), Color(0xFFFFD27A), Color(0xFF72A7FF),
  ];

  Path _heart(double r) => Path()
    ..moveTo(0, r * 0.35)
    ..cubicTo(-r * 1.2, -r * 0.45, -r * 0.4, -r * 1.2, 0, -r * 0.45)
    ..cubicTo(r * 0.4, -r * 1.2, r * 1.2, -r * 0.45, 0, r * 0.35)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;
    final w = size.width, hgt = size.height;
    final paint = Paint();
    if (effect == AppearanceEffect.aurora || effect == AppearanceEffect.galaxy) {
      for (var b = 0; b < 3; b++) {
        final path = Path();
        final y0 = hgt * (effect == AppearanceEffect.galaxy ? 0.35 + b * 0.12 : 0.15 + b * 0.08);
        path.moveTo(0, y0);
        for (var x = 0.0; x <= w; x += w / 24) {
          path.lineTo(x, y0 + math.sin(x / w * 6 + t * 0.4 + b * 2) * hgt * 0.05);
        }
        canvas.drawPath(
            path,
            paint
              ..color = color.withValues(alpha: 0.18 * intensity + 0.05)
              ..style = PaintingStyle.stroke
              ..strokeWidth = hgt * 0.06
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
      }
      paint
        ..style = PaintingStyle.fill
        ..maskFilter = null;
      if (effect == AppearanceEffect.aurora) return;
    }
    final count = (18 + 46 * intensity).round();
    for (var i = 0; i < count; i++) {
      final a = _h(i, 1), b = _h(i, 2), c = _h(i, 3);
      double x = a * w, y;
      switch (effect) {
        case AppearanceEffect.snow:
        case AppearanceEffect.rain:
        case AppearanceEffect.confetti:
        case AppearanceEffect.petals:
          final speed = effect == AppearanceEffect.rain ? 0.9 + b : 0.08 + b * 0.1;
          y = ((c + t * speed) % 1.0) * (hgt + 40) - 20;
          x += math.sin(t * (0.6 + b) + i) * (effect == AppearanceEffect.rain ? 0 : 14);
        case AppearanceEffect.hearts:
        case AppearanceEffect.bubbles:
        case AppearanceEffect.sparkles:
          y = hgt - ((c + t * (0.04 + b * 0.06)) % 1.0) * (hgt + 40) + 20;
          x += math.sin(t * (0.5 + b) + i) * 12;
        default:
          y = c * hgt + math.cos(t * (0.3 + b) + i) * 10;
          x += math.sin(t * (0.25 + a) + i) * 10;
      }
      final pulse = 0.5 + 0.5 * math.sin(t * (1 + 2 * b) + i * 3);
      canvas.save();
      canvas.translate(x, y);
      switch (effect) {
        case AppearanceEffect.snow:
          paint.color = Colors.white.withValues(alpha: 0.85);
          canvas.drawCircle(Offset.zero, 1.5 + b * 2.5, paint);
        case AppearanceEffect.rain:
          paint
            ..color = Color.lerp(Colors.white, color, 0.3)!.withValues(alpha: 0.5)
            ..strokeWidth = 1.2;
          canvas.drawLine(Offset.zero, Offset(-3, 14 + b * 10), paint);
        case AppearanceEffect.confetti:
          paint.color = i.isEven ? color : _confetti[i % _confetti.length];
          canvas.rotate(t * (1 + b * 2) + i);
          canvas.scale(math.cos(t * 3 + i), 1);
          canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), paint);
        case AppearanceEffect.petals:
          paint.color = Color.lerp(const Color(0xFFFFC1D9), color, 0.35)!
              .withValues(alpha: 0.85);
          canvas.rotate(t * (0.8 + b) + i);
          canvas.drawOval(const Rect.fromLTWH(-5, -3, 10, 6), paint);
        case AppearanceEffect.hearts:
          paint.color = Color.lerp(const Color(0xFFFF6FA5), color, 0.4)!
              .withValues(alpha: 0.75);
          canvas.drawPath(_heart(5 + b * 6), paint);
        case AppearanceEffect.bubbles:
          paint
            ..color = Colors.white.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;
          canvas.drawCircle(Offset.zero, 4 + b * 10, paint);
          paint.style = PaintingStyle.fill;
        case AppearanceEffect.bokeh:
          paint
            ..color = color.withValues(alpha: 0.12 + 0.1 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawCircle(Offset.zero, 14 + b * 26, paint);
          paint.maskFilter = null;
        case AppearanceEffect.fireflies:
          paint
            ..color = color.withValues(alpha: 0.9 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
          canvas.drawCircle(Offset.zero, 2.5 + b * 2, paint);
          paint.maskFilter = null;
        default: // sparkles, stars, galaxy
          paint.color = Color.lerp(Colors.white, color, 0.4)!
              .withValues(alpha: (0.25 + 0.75 * pulse) * 0.9);
          final r = 1.0 + b * 2.2;
          canvas.drawCircle(Offset.zero, r, paint);
          if (effect == AppearanceEffect.sparkles && b > 0.5) {
            paint.strokeWidth = 1;
            canvas.drawLine(Offset(-r * 3, 0), Offset(r * 3, 0), paint);
            canvas.drawLine(Offset(0, -r * 3), Offset(0, r * 3), paint);
          }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.effect != effect || old.color != color || old.intensity != intensity;
}
