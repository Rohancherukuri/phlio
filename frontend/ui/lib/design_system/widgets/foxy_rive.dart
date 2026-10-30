// Foxy, animated: the Rive state machine in assets/rive/foxy.riv, with a
// hand-tuned Flutter fallback.
//
// [FoxyRive] drives the `Foxy` state machine (see assets/rive/README.md):
//   mood   (number)  what he's doing — [FoxyMood] index
//   outfit (number)  what he's wearing — [FoxyOutfit] index
//   lean   (number)  -100…100, follows whatever is being typed
//   hop / shake / poof (triggers)
// If the .riv can't be loaded, the same inputs drive a small motion rig over
// the original pose PNGs, GIF loops and costume stickers, so screens never
// care which one is running. Foxy's artwork is never redrawn.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:rive/rive.dart' as rive;

/// What Foxy is doing. The index is the Rive `mood` number input.
enum FoxyMood {
  wave('Wave', 'assets/animations/foxy_wave.gif', loop: true),
  think('Thinking', 'assets/animations/foxy_think.gif', loop: true),
  celebrate('Celebrate', 'assets/animations/foxy_celebrate.gif', loop: true),
  explore('Explore', 'assets/animations/foxy_explore.gif', loop: true),
  sleep('Sleepy', 'assets/animations/foxy_sleep.gif', loop: true),
  hello('Hello', 'assets/images/foxy/foxy_hello.png'),
  curious('Curious', 'assets/images/foxy/foxy_curious.png'),
  // Smiling with eyes shut — used while a password is being typed.
  noPeeking('No peeking', 'assets/images/foxy/foxy_happy.png'),
  focused('Focused', 'assets/images/foxy/foxy_focused.png'),
  cozy('Cozy', 'assets/images/foxy/foxy_cozy.png'),
  love('Love', 'assets/emoji/emoji_foxy_love.png');

  const FoxyMood(this.label, this.fallbackAsset, {this.loop = false});
  final String label;
  final String fallbackAsset;

  /// GIF loops ship on a solid backdrop, so their edges are feathered out.
  final bool loop;

  static FoxyMood? byName(String name) {
    for (final mood in values) {
      if (mood.name == name) return mood;
    }
    return null;
  }
}

/// What Foxy is wearing. The index is the Rive `outfit` number input;
/// [classic] is his everyday look (the mood poses).
enum FoxyOutfit {
  classic('Classic'),
  explorer('Explorer'),
  hoodie('Hoodie'),
  space('Space'),
  samurai('Samurai'),
  wizard('Wizard'),
  chef('Chef'),
  student('Student'),
  business('Business'),
  rainy('Rainy day'),
  winter('Winter'),
  traveler('Traveler');

  const FoxyOutfit(this.label);
  final String label;

  String? get stickerAsset => this == classic
      ? null
      : 'assets/stickers/sticker_costume_$name.png';

  static FoxyOutfit? byName(String name) {
    for (final outfit in values) {
      if (outfit.name == name) return outfit;
    }
    return null;
  }
}

class FoxyRive extends StatefulWidget {
  const FoxyRive({
    super.key,
    this.mood = FoxyMood.wave,
    this.outfit = FoxyOutfit.classic,
    this.size = 140,
    this.lean = 0,
    this.hopSignal = 0,
    this.shakeSignal = 0,
    this.entrance = true,
    this.hopOnEnter = false,
    this.tapToHop = false,
    this.poofOnOutfitChange = true,
  });

  final FoxyMood mood;
  final FoxyOutfit outfit;
  final double size;

  /// -1 (leans left) … 1 (leans right).
  final double lean;

  /// Increment to make Foxy hop once (a success beat).
  final int hopSignal;

  /// Increment to make Foxy shake his head (an error beat).
  final int shakeSignal;

  /// Fade/scale in on first build.
  final bool entrance;

  /// Hop once as he appears.
  final bool hopOnEnter;

  /// Tapping Foxy makes him hop.
  final bool tapToHop;

  /// A puff of smoke while he changes clothes.
  final bool poofOnOutfitChange;

  static const riveAsset = 'assets/rive/foxy.riv';
  static const stateMachine = 'Foxy';

  static Future<rive.RiveFile?>? _riveFile;
  static rive.RiveFile? _riveReady;
  static bool _riveMissing = false;

  /// Loads and parses foxy.riv once per launch (null when it can't be read,
  /// in which case the fallback rig is used).
  static Future<rive.RiveFile?> riveFile() =>
      _riveFile ??= rootBundle.load(riveAsset).then<rive.RiveFile?>(
        (data) async {
          await rive.RiveFile.initialize();
          return _riveReady = rive.RiveFile.import(data);
        },
        onError: (Object _) {
          _riveMissing = true;
          return null;
        },
      ).catchError((Object _) {
        _riveMissing = true;
        return null;
      });

  /// Whether Foxy's Rive file is available.
  static Future<bool> riveBundled() => riveFile().then((file) => file != null);

  /// Starts loading the Rive file and warms the fallback artwork.
  static void precache(BuildContext context) {
    riveFile();
    for (final mood in FoxyMood.values) {
      precacheImage(AssetImage(mood.fallbackAsset), context);
    }
  }

  @override
  State<FoxyRive> createState() => _FoxyRiveState();
}

class _FoxyRiveState extends State<FoxyRive> with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _hop;
  late final AnimationController _shake;
  late final AnimationController _enter;

  rive.SMIInput<double>? _riveMood;
  rive.SMIInput<double>? _riveOutfit;
  rive.SMIInput<double>? _riveLean;
  rive.SMIInput<bool>? _riveHop;
  rive.SMIInput<bool>? _riveShake;
  rive.SMIInput<bool>? _rivePoof;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat(reverse: true);
    _hop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 560));
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _enter = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 620),
        value: widget.entrance ? 0 : 1)
      ..forward();
    if (widget.hopOnEnter) {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted) _doHop();
      });
    }
  }

  @override
  void didUpdateWidget(FoxyRive old) {
    super.didUpdateWidget(old);
    if (widget.hopSignal != old.hopSignal) _doHop();
    if (widget.shakeSignal != old.shakeSignal) {
      _shake.forward(from: 0);
      _fire(_riveShake);
    }
    if (widget.outfit != old.outfit && widget.poofOnOutfitChange) {
      _fire(_rivePoof);
    }
    _riveMood?.value = widget.mood.index.toDouble();
    _riveOutfit?.value = widget.outfit.index.toDouble();
    _riveLean?.value = widget.lean.clamp(-1.0, 1.0) * 100;
  }

  void _doHop() {
    _hop.forward(from: 0);
    _fire(_riveHop);
  }

  void _fire(rive.SMIInput<bool>? input) {
    if (input is rive.SMITrigger) {
      input.fire();
    } else {
      input?.value = true;
    }
  }

  void _onRiveInit(rive.Artboard artboard) {
    var controller = rive.StateMachineController.fromArtboard(
        artboard, FoxyRive.stateMachine);
    if (controller == null && artboard.stateMachines.isNotEmpty) {
      controller = rive.StateMachineController.fromArtboard(
          artboard, artboard.stateMachines.first.name);
    }
    if (controller == null) return;
    artboard.addController(controller);
    _riveMood = controller.findInput<double>('mood')
      ?..value = widget.mood.index.toDouble();
    _riveOutfit = controller.findInput<double>('outfit')
      ?..value = widget.outfit.index.toDouble();
    _riveLean = controller.findInput<double>('lean')
      ?..value = widget.lean.clamp(-1.0, 1.0) * 100;
    _riveHop = controller.findInput<bool>('hop');
    _riveShake = controller.findInput<bool>('shake');
    _rivePoof = controller.findInput<bool>('poof');
  }

  @override
  void dispose() {
    _breath.dispose();
    _hop.dispose();
    _shake.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget content = Builder(builder: (context) {
      final ready = FoxyRive._riveReady;
      if (ready != null) return _riveView(ready);
      if (FoxyRive._riveMissing) return _rig(size);
      return FutureBuilder<rive.RiveFile?>(
        future: FoxyRive.riveFile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          final file = snapshot.data;
          return file == null ? _rig(size) : _riveView(file);
        },
      );
    });
    if (widget.entrance) {
      content = AnimatedBuilder(
        animation: _enter,
        child: content,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_enter.value);
          return Opacity(
            opacity: t,
            child: Transform.scale(
                scale: 0.82 + 0.18 * t,
                alignment: Alignment.bottomCenter,
                child: child),
          );
        },
      );
    }
    if (widget.tapToHop) {
      content = GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: _doHop, child: content);
    }
    return SizedBox(width: size, height: size, child: content);
  }

  Widget _riveView(rive.RiveFile file) {
    return rive.RiveAnimation.direct(
      file,
      stateMachines: const [FoxyRive.stateMachine],
      fit: BoxFit.contain,
      onInit: _onRiveInit,
    );
  }

  /// The motion rig around the static/GIF artwork.
  Widget _rig(double size) {
    final art = AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(animation),
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previous, if (current != null) current]),
      child: _Artwork(
          key: ValueKey((widget.mood, widget.outfit)),
          mood: widget.mood,
          outfit: widget.outfit,
          size: size),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _hop, _shake]),
      child: art,
      builder: (context, child) {
        final breath = Curves.easeInOut.transform(_breath.value);
        // Hop: rise, fall, then a squash on landing.
        final h = _hop.value;
        final lift = h < 0.75 ? math.sin(h / 0.75 * math.pi) : 0.0;
        final squash = h >= 0.75 ? math.sin((h - 0.75) / 0.25 * math.pi) : 0.0;
        final stretch = h < 0.2 ? math.sin(h / 0.2 * math.pi) * 0.5 : 0.0;
        // Shake: a decaying head-shake.
        final s = _shake.value;
        final shake = math.sin(s * math.pi * 6) * (1 - s) * 0.07;

        final scaleY = 1 + breath * 0.016 + stretch * 0.06 - squash * 0.07;
        final scaleX = 1 - breath * 0.006 - stretch * 0.03 + squash * 0.06;
        final shadowScale = 1 - lift * 0.35;

        return Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: size * 0.04,
              child: Transform.scale(
                scale: shadowScale,
                child: Container(
                  width: size * 0.5,
                  height: size * 0.07,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size),
                    gradient: RadialGradient(colors: [
                      Colors.black.withValues(alpha: 0.45 * shadowScale),
                      Colors.black.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(end: widget.lean.clamp(-1.0, 1.0)),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, lean, child) => Transform.translate(
                offset: Offset(lean * size * 0.02, -lift * size * 0.12),
                child: Transform.rotate(
                  angle: lean * 0.07 + shake,
                  alignment: Alignment.bottomCenter,
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
                    child: child,
                  ),
                ),
              ),
              child: child,
            ),
          ],
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork(
      {super.key, required this.mood, required this.outfit, required this.size});

  final FoxyMood mood;
  final FoxyOutfit outfit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final costume = outfit.stickerAsset;
    final path = costume ?? mood.fallbackAsset;
    Widget image = Padding(
      padding: EdgeInsets.all(costume == null ? 0 : size * 0.12),
      child: Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
      ),
    );
    if (costume == null && mood.loop) {
      // Feather the GIF's square backdrop into whatever is behind it.
      image = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const RadialGradient(
          center: Alignment(0, 0.05),
          radius: 0.56,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.74, 1],
        ).createShader(rect),
        child: image,
      );
    }
    return image;
  }
}
