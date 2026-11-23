// Screen orientation policy: Phlio is portrait-only, except while a video
// is being watched (Social videos, Stream movies & shows, videos shared in
// Rooms, live video and watch-together).
//
//   PhlioOrientation.init()        portrait at startup (main.dart)
//   LandscapeAllowed(child: …)     the phone may rotate while this is shown
//   PhlioOrientation.allowRotation() / releaseRotation()
//                                  the same, for non-widget owners (the
//                                  global video player)
//   PhlioOrientation.forceLandscape(true/false)
//                                  a fullscreen button: landscape only
//
// Requests are counted, so nested or overlapping owners (a watch party
// opening the player, a fullscreen clip inside the videos tab) restore the
// right state when each one goes away.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class PhlioOrientation {
  static int _rotate = 0;
  static int _landscape = 0;

  static Future<void> init() => _apply();

  static void allowRotation() {
    _rotate++;
    _apply();
  }

  static void releaseRotation() {
    if (_rotate > 0) _rotate--;
    _apply();
  }

  static void forceLandscape(bool on) {
    if (on) {
      _landscape++;
    } else if (_landscape > 0) {
      _landscape--;
    }
    _apply();
  }

  static Future<void> _apply() => SystemChrome.setPreferredOrientations(
        _landscape > 0
            ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : _rotate > 0
                ? const [
                    DeviceOrientation.portraitUp,
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]
                : const [DeviceOrientation.portraitUp],
      );
}

/// Lets the phone rotate to landscape while [child] is on screen.
class LandscapeAllowed extends StatefulWidget {
  const LandscapeAllowed({required this.child, super.key});

  final Widget child;

  @override
  State<LandscapeAllowed> createState() => _LandscapeAllowedState();
}

class _LandscapeAllowedState extends State<LandscapeAllowed> {
  @override
  void initState() {
    super.initState();
    PhlioOrientation.allowRotation();
  }

  @override
  void dispose() {
    PhlioOrientation.releaseRotation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
