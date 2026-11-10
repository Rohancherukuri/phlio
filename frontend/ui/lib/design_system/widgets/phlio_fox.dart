import 'foxy_stickers.dart';
// Phlio design system — Foxy, the product mascot.
//
// Foxy (v2 art: blue button shorts, cream tufts) is the face of Phlio
// Agent and the warmth across onboarding and empty states. Static poses
// live in `assets/images/foxy/`; the rigged live puppet in
// `assets/foxy_puppet/` (see foxy_puppet.dart).
//
// [PhlioFox] shows a pose: live and rigged (blinks, ear twitches, tail
// wag, tap to hop) when `animate` is on and the pose is rigged, otherwise
// the static art with a gentle bob. [PhlioFoxAnimation] plays a looping act
// on the puppet. [PhlioStickers] is the chat sticker catalog.

import 'package:flutter/material.dart';
import '../colors.dart';
import 'foxy_puppet.dart';

/// Foxy's poses. [act] is the live puppet act for rigged poses.
enum PhlioFoxPose {
  happy('assets/images/foxy/foxy_happy.png', FoxyAct.happy),
  explorer('assets/images/foxy/foxy_explorer.png', FoxyAct.ready),
  cozy('assets/images/foxy/foxy_cozy.png'),
  adventurous('assets/images/foxy/foxy_adventurous.png', FoxyAct.ready),
  sleepy('assets/images/foxy/foxy_sleepy.png', FoxyAct.sleep),
  focused('assets/images/foxy/foxy_focused.png', FoxyAct.think),
  coffee('assets/images/foxy/foxy_coffee.png'),
  curious('assets/images/foxy/foxy_curious.png', FoxyAct.phone),
  hello('assets/images/foxy/foxy_hello.png', FoxyAct.idle),
  journey('assets/images/foxy/foxy_journey.png', FoxyAct.ready),

  /// Head-and-shoulders crop for small avatars (app bars, chat).
  face('assets/images/foxy/foxy_face.png');

  const PhlioFoxPose(this.assetPath, [this.act]);
  final String assetPath;
  final FoxyAct? act;
}

/// Looping mascot animations, played live on the rigged puppet.
enum PhlioFoxLoop {
  wave(FoxyAct.wave),
  think(FoxyAct.think),
  sleep(FoxyAct.sleep),
  celebrate(FoxyAct.cheer),
  explore(FoxyAct.ready),
  moods(FoxyAct.love);

  const PhlioFoxLoop(this.act);
  final FoxyAct act;
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
    final act = pose.act;
    if (animate && act != null) {
      // Live, rigged Foxy. The puppet canvas is square; he fills ~85% of
      // its height, so it is sized up slightly to match the static art.
      return SizedBox(
        height: size,
        width: size,
        child: OverflowBox(
          maxWidth: size * 1.15,
          maxHeight: size * 1.15,
          child: FoxyPuppet(act: act, size: size * 1.15, entrance: false),
        ),
      );
    }
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

/// Foxy's face in a soft brand-tinted circle — for app bars, chat rows
/// and anywhere he needs to read at avatar size.
class FoxyAvatar extends StatelessWidget {
  const FoxyAvatar({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PhlioColors.brandOrange.withValues(alpha: 0.30),
            PhlioColors.brandOrange.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(
            color: PhlioColors.brandOrange.withValues(alpha: 0.45), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        PhlioFoxPose.face.assetPath,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.2),
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _FoxyPlaceholder(size: size),
      ),
    );
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
  Widget build(BuildContext context) =>
      FoxyPuppet(act: animation.act, size: size, entrance: false);
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

/// A Foxy chat sticker sized for message bubbles. Accepts every sticker id
/// the app knows (animated `foxy:` stickers, the Foxy pack, the original
/// set and GIPHY references) — see [FoxyStickerView].
class PhlioStickerView extends StatelessWidget {
  const PhlioStickerView(
      {super.key,
      required this.stickerId,
      this.size = 64,
      this.interactive = true});

  final String stickerId;
  final double size;

  /// Animated stickers hop when tapped.
  final bool interactive;

  @override
  Widget build(BuildContext context) =>
      FoxyStickerView(id: stickerId, size: size, interactive: interactive);
}
