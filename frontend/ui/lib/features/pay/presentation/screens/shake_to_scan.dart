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
  StreamSubscription<UserAccelerometerEvent>? _sub;
  final _peaks = <DateTime>[];
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static const _threshold = 14.0; // m/s², gravity removed
  static const _window = Duration(milliseconds: 700);

  void _listen(bool on) {
    if (on && _sub == null) {
      _sub = userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_onEvent, onError: (_) {});
    } else if (!on && _sub != null) {
      _sub!.cancel();
      _sub = null;
    }
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
    _sub?.cancel();
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
