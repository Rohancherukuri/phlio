// Phlio design system — Foxy, the product mascot.
//
// Foxy is a curious orange fox with pilot goggles and a knit scarf: the
// face of Phlio Agent and the warmth across onboarding. All artwork is
// bundled under `assets/images/foxy/` (poses), `assets/stickers/`
// (expression stickers) and `assets/animations/` (looping GIFs), generated
// from the brand pose sheet.
//
// [PhlioFox] renders a static pose; [PhlioFoxLoop] renders a looping
// GIF (Flutter plays animated GIFs natively via Image.asset); [PhlioSticker]
// is the chat sticker catalog.

import 'package:flutter/material.dart';
import '../colors.dart';

/// Static poses extracted from the brand pose sheet.
enum PhlioFoxPose {
  happy('assets/images/foxy/foxy_happy.png'),
  explorer('assets/images/foxy/foxy_explorer.png'),
  cozy('assets/images/foxy/foxy_cozy.png'),
  adventurous('assets/images/foxy/foxy_adventurous.png'),
  sleepy('assets/images/foxy/foxy_sleepy.png'),
  focused('assets/images/foxy/foxy_focused.png'),
  coffee('assets/images/foxy/foxy_coffee.png'),
  curious('assets/images/foxy/foxy_curious.png'),
  hello('assets/images/foxy/foxy_hello.png'),
  journey('assets/images/foxy/foxy_journey.png');

  const PhlioFoxPose(this.assetPath);
  final String assetPath;
}

/// Looping mascot animations (animated GIF assets).
enum PhlioFoxLoop {
  wave('assets/animations/foxy_wave.gif'),
  think('assets/animations/foxy_think.gif'),
  sleep('assets/animations/foxy_sleep.gif'),
  celebrate('assets/animations/foxy_celebrate.gif'),
  explore('assets/animations/foxy_explore.gif'),
  moods('assets/animations/foxy_moods.gif');

  const PhlioFoxLoop(this.assetPath);
  final String assetPath;
}

/// A gentle idle bob so static poses feel alive without a full GIF.
class _FoxyIdleBob extends StatefulWidget {
  const _FoxyIdleBob({required this.child});

  final Widget child;

  @override
  State<_FoxyIdleBob> createState() => _FoxyIdleBobState();
}

class _FoxyIdleBobState extends State<_FoxyIdleBob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final Animation<double> _bob = Tween<double>(begin: -3, end: 3).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  late final Animation<double> _tilt = Tween(begin: -0.015, end: 0.015).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _bob.value),
        child: Transform.rotate(angle: _tilt.value, child: child),
      ),
      child: widget.child,
    );
  }
}

class PhlioFox extends StatelessWidget {
  const PhlioFox({
    super.key,
    this.size = 96,
    this.pose = PhlioFoxPose.happy,
    this.animate = true,
  });

  final double size;

  /// Displayed height. Width follows the asset's aspect ratio.
  final PhlioFoxPose pose;

  /// Whether the pose gets the subtle idle bob. Turn off inside scrolling
  /// lists or when composing with other motion.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      pose.assetPath,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      // A missing/broken asset must degrade to a quiet on-brand placeholder
      // — Image.asset's default error widget is a wide block of text that
      // overflows Rows (and reads as broken).
      errorBuilder: (_, __, ___) => _FoxyPlaceholder(size: size),
    );
    if (!animate) return image;
    return _FoxyIdleBob(child: image);
  }
}

class PhlioFoxAnimation extends StatelessWidget {
  const PhlioFoxAnimation({
    super.key,
    this.size = 120,
    this.animation = PhlioFoxLoop.wave,
  });

  final double size;
  final PhlioFoxLoop animation;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      animation.assetPath,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => _FoxyPlaceholder(size: size),
    );
  }
}

/// Compact fallback shown if a Foxy asset ever fails to load.
class _FoxyPlaceholder extends StatelessWidget {
  const _FoxyPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Icon(
        Icons.pets_rounded,
        size: size * 0.4,
        color: PhlioColors.brandOrange,
      ),
    );
  }
}

/// The chat sticker catalog: Foxy expressions + mini poses, mirrored by the
/// backend's `/stickers` endpoint so both sides agree on ids.
abstract final class PhlioStickers {
  static const String basePath = 'assets/stickers/sticker_foxy_';

  static const List<({String id, String label})> catalog = [
    (id: 'idle', label: 'Foxy'),
    (id: 'happy', label: 'Happy'),
    (id: 'hello', label: 'Hello!'),
    (id: 'wave', label: 'Wave'),
    (id: 'excited', label: 'Excited'),
    (id: 'thinking', label: 'Thinking'),
    (id: 'listening', label: 'Listening'),
    (id: 'surprised', label: 'Surprised'),
    (id: 'sad', label: 'Sad'),
    (id: 'determined', label: 'Determined'),
    (id: 'coffee', label: 'Coffee break'),
    (id: 'sleepy', label: 'Sleepy'),
  ];

  static String assetFor(String id) => '$basePath$id.png';
}

/// A Foxy chat sticker sized for message bubbles.
class PhlioStickerView extends StatelessWidget {
  const PhlioStickerView({super.key, required this.stickerId, this.size = 64});

  final String stickerId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        PhlioStickers.assetFor(stickerId),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Container(
          color: PhlioColors.surfaceElevated,
          alignment: Alignment.center,
          child: const Icon(Icons.pets, size: 20, color: PhlioColors.brandOrange),
        ),
      ),
    );
  }
}
