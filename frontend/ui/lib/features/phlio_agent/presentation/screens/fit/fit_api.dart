// Phlio Fit — data, colours, the step sensor, and the animated charts shared
// by the Fit screen and the profile dashboard's Foxy tab.
//
// Backend: backend/app/api/v1/fitness.py.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/design_system/colors.dart';

final fitDio = getIt<ApiClient>().dio;

// Phlio palette, one colour per measure.
const fitSteps = Color(0xFF68D7CD);
const fitWater = Color(0xFF72A7FF);
const fitCalories = Color(0xFFFFB58F);
const fitActive = Color(0xFF8D78FF);
const fitProtein = Color(0xFF8D78FF);
const fitCarbs = Color(0xFFF6B93B);
const fitFat = Color(0xFFE795D7);

String fitNum(num v) {
  final n = v.round();
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b';
}

String fitMl(num ml) => ml >= 1000 ? '${(ml / 1000).toStringAsFixed(ml % 1000 == 0 ? 0 : 2)} L' : '${ml.round()} ml';

String fitYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// -- Step sensor --------------------------------------------------------------

/// Listens to the phone's step counter and reports its running total to the
/// server (which turns it into today's steps). One instance for the app.
class FitStepTracker {
  FitStepTracker._();
  static final instance = FitStepTracker._();

  StreamSubscription<StepCount>? _sub;
  int? _lastSent;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  final ValueNotifier<String> status = ValueNotifier('off'); // off | denied | live | unavailable
  final ValueNotifier<int?> steps = ValueNotifier(null); // today's steps after a sync

  bool get live => status.value == 'live';

  Future<void> start() async {
    if (_sub != null) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      status.value = 'unavailable';
      return;
    }
    // Android asks for "Physical activity"; iOS shows its Motion prompt
    // itself the first time the step counter is read.
    if (Platform.isAndroid && !(await Permission.activityRecognition.request()).isGranted) {
      status.value = 'denied';
      return;
    }
    _sub = Pedometer.stepCountStream.listen(_onSteps, onError: (_) {
      status.value = 'unavailable';
      _sub?.cancel();
      _sub = null;
    });
    status.value = 'live';
  }

  Future<void> _onSteps(StepCount e) async {
    final now = DateTime.now();
    // Don't flood the server: every 20 steps or 30 seconds.
    if (_lastSent != null && (e.steps - _lastSent!).abs() < 20 && now.difference(_lastAt).inSeconds < 30) return;
    _lastSent = e.steps;
    _lastAt = now;
    try {
      final res = await fitDio.post('/fitness/steps', data: {'total': e.steps});
      steps.value = ((res.data as Map)['steps'] as num?)?.toInt();
    } catch (_) {}
  }
}

// -- Rings ---------------------------------------------------------------------

/// A progress ring that fills in when shown (or when [value] changes).
class FitRing extends StatelessWidget {
  const FitRing({required this.value, required this.color, this.size = 92, this.stroke = 10, this.child, super.key});
  final double value;
  final Color color;
  final double size, stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (_, t, c) => CustomPaint(painter: _RingPainter(t, color, stroke), child: Center(child: c)),
          child: child,
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color, this.stroke);
  final double t, stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: .14));
    if (t <= 0) return;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * t, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [Color.lerp(color, Colors.white, .25)!, color],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color;
}

// -- Interactive bar chart -------------------------------------------------------

/// Bars that grow in; tap or drag across to read a day. A dashed line marks
/// the goal. [format] turns a value into text for the readout.
class FitBarChart extends StatefulWidget {
  const FitBarChart({
    required this.values,
    required this.labels,
    required this.color,
    required this.format,
    this.goal,
    this.height = 150,
    this.secondary,
    this.secondaryColor,
    super.key,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final String Function(int index) format;
  final double? goal;
  final double height;

  /// Optional second series drawn as a thinner bar beside each (e.g. burned).
  final List<double>? secondary;
  final Color? secondaryColor;

  @override
  State<FitBarChart> createState() => _FitBarChartState();
}

class _FitBarChartState extends State<FitBarChart> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    if (n == 0) return const SizedBox.shrink();
    final all = [...widget.values, ...?widget.secondary, if (widget.goal != null) widget.goal!];
    final hi = math.max(1.0, all.fold<double>(0, math.max)) * 1.08;
    final sel = _sel ?? n - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: Text(
          key: ValueKey(sel),
          '${widget.labels[sel]} · ${widget.format(sel)}',
          style: TextStyle(color: _sel == null ? Colors.white60 : Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / n;
        void at(Offset p) {
          final i = (p.dx / w).floor().clamp(0, n - 1);
          if (i != _sel) HapticFeedback.selectionClick();
          setState(() => _sel = i);
        }

        return GestureDetector(
          onTapDown: (d) => at(d.localPosition),
          onHorizontalDragUpdate: (d) => at(d.localPosition),
          onHorizontalDragEnd: (_) {},
          child: SizedBox(
            height: widget.height,
            child: Stack(children: [
              if (widget.goal != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: widget.height * (widget.goal! / hi),
                  child: CustomPaint(size: Size(box.maxWidth, 1), painter: _Dash(widget.color.withValues(alpha: .5))),
                ),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: n > 14 ? 1 : 4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 520 + 30 * i),
                        curve: Interval((30 * i) / (520 + 30 * i), 1, curve: Curves.easeOutBack),
                        builder: (_, t, __) {
                          final dim = i != sel;
                          Widget bar(double v, Color c, {double radius = 7}) => AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                height: math.max(4.0, (widget.height - 4) * (v / hi) * t.clamp(0.0, 1.2)),
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: v <= 0 ? .14 : (dim ? .38 : 1)),
                                  borderRadius: BorderRadius.circular(radius),
                                ),
                              );
                          final second = widget.secondary;
                          if (second == null) return bar(widget.values[i], widget.color);
                          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Expanded(child: bar(widget.values[i], widget.color, radius: 5)),
                            const SizedBox(width: 2),
                            Expanded(child: bar(second[i], widget.secondaryColor ?? Colors.white54, radius: 5)),
                          ]);
                        },
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
        );
      }),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: Text(
              n > 10 && i % (n ~/ 7 + 1) != 0 && i != n - 1 ? '' : widget.labels[i].split(' ').first,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: i == sel ? Colors.white : Colors.white38),
            ),
          ),
      ]),
    ]);
  }
}

class _Dash extends CustomPainter {
  _Dash(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 4, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}

/// A soft card in the Fit style.
class FitCard extends StatelessWidget {
  const FitCard({required this.child, this.padding = const EdgeInsets.all(16), this.onTap, super.key});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: .06)),
            ),
            child: child,
          ),
        ),
      );
}

String weekdayLabel(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  const wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${wk[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}
