// Shake to scan: while Phlio Pay is on screen and the setting is on (Pay
// profile → Shake to scan), a quick shake opens the QR scanner.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'pay_profile_screen.dart' show payProfileProvider;

class ShakeToScan extends ConsumerStatefulWidget {
  const ShakeToScan({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<ShakeToScan> createState() => _ShakeToScanState();
}

class _ShakeToScanState extends ConsumerState<ShakeToScan> {
  /// Off for the rest of the run once the sensor plugin isn't there (an app
  /// hot-restarted after adding sensors_plus, or a phone without the sensor):
  /// no retries, no error spam.
  static bool _unavailable = false;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  bool _wanted = false;
  final _peaks = <DateTime>[];
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static const _threshold = 14.0; // m/s², gravity removed
  static const _window = Duration(milliseconds: 700);

  void _listen(bool on) {
    if (on == _wanted) return; // only act on changes, not on every build
    _wanted = on;
    if (on && _sub == null && !_unavailable) {
      try {
        // Default sampling period: asking for another one is a separate
        // platform call that throws on its own when the plugin is missing.
        _sub = userAccelerometerEventStream().listen(
          _onEvent,
          onError: (Object _) => _giveUp(),
          cancelOnError: true,
        );
      } catch (_) {
        _giveUp();
      }
    } else if (!on) {
      _stop();
    }
  }

  void _stop() {
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel().catchError((Object _) {}));
  }

  void _giveUp() {
    _unavailable = true;
    _sub = null; // cancelOnError already closed it
  }

  void _onEvent(UserAccelerometerEvent e) {
    final force = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (force < _threshold) return;
    final now = DateTime.now();
    _peaks
      ..removeWhere((t) => now.difference(t) > _window)
      ..add(now);
    // Two strong jolts close together = a shake; then rest for 2 s.
    if (_peaks.length >= 2 && now.difference(_last) > const Duration(seconds: 2)) {
      _last = now;
      _peaks.clear();
      HapticFeedback.mediumImpact();
      if (mounted) context.push('/qr-scanner');
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only while Pay is the visible platform (TickerMode) and the setting is on.
    final visible = TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    final enabled = ref.watch(payProfileProvider).valueOrNull?['settings']?['shake_to_scan'] != false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listen(visible && enabled);
    });
    return widget.child;
  }
}
