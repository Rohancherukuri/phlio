// Applies a Phlio Look (colour grade + optional animated effect) to any
// widget subtree on the GPU, via ImageFilter.shader with
// assets/shaders/phlio_look.frag. Without Impeller (where shader image
// filters aren't available) it falls back to the look's colour matrix.
//
// Because it's a layer filter, RepaintBoundary.toImage captures it too, so
// flattened photo moments bake the look in.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'phlio_look_data.dart';

class PhlioLookShader {
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  static bool get supported {
    try {
      return ui.ImageFilter.isShaderFilterSupported;
    } catch (_) {
      return false;
    }
  }

  static ui.FragmentProgram? get program => _program;

  static Future<ui.FragmentProgram?> load() => _loading ??= () async {
        try {
          return _program = await ui.FragmentProgram.fromAsset('assets/shaders/phlio_look.frag');
        } catch (_) {
          return null;
        }
      }();
}

class PhlioLook extends StatefulWidget {
  const PhlioLook({
    required this.child,
    this.look = 'normal',
    this.grade,
    this.strength = 1,
    this.effect = 'none',
    this.effectAmount = 1,
    super.key,
  });

  /// Named look from [phlioLooks] (ignored when [grade] is given).
  final String look;

  /// Explicit grade (the Studio passes its own filter + adjustments).
  final LookGrade? grade;
  final double strength;
  final String effect;
  final double effectAmount;
  final Widget child;

  @override
  State<PhlioLook> createState() => _PhlioLookState();
}

class _PhlioLookState extends State<PhlioLook> with TickerProviderStateMixin {
  // Two shader instances used on alternate frames: an ImageFilter built from
  // the same shader compares equal to the last one, so Flutter would skip
  // the repaint and animated effects (glitch, VHS, leaks…) froze on one frame.
  ui.FragmentShader? _shader, _shaderB;
  bool _flip = false;
  Ticker? _ticker;
  double _time = 0;

  static const _animated = {2, 4, 5, 7, 8, 9, 1};

  @override
  void initState() {
    super.initState();
    final program = PhlioLookShader.program;
    if (program != null) {
      _shader = program.fragmentShader();
      _shaderB = program.fragmentShader();
    } else if (PhlioLookShader.supported) {
      PhlioLookShader.load().then((p) {
        if (p != null && mounted) {
          setState(() {
            _shader = p.fragmentShader();
            _shaderB = p.fragmentShader();
          });
        }
      });
    }
    _syncTicker();
  }

  @override
  void didUpdateWidget(PhlioLook old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    final animate = _animated.contains(phlioEffectId(widget.effect)) && widget.effectAmount > 0;
    if (animate && _ticker == null) {
      _ticker = createTicker((elapsed) {
        _time = elapsed.inMicroseconds / 1e6;
        _flip = !_flip;
        if (mounted) setState(() {});
      })
        ..start();
    } else if (!animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _shader?.dispose();
    _shaderB?.dispose();
    super.dispose();
  }

  LookGrade get _grade {
    final base = widget.grade ?? phlioLooks[normalizeLook(widget.look)] ?? LookGrade.none;
    return widget.strength >= .999 ? base : base.scaled(widget.strength.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final g = _grade;
    final fx = phlioEffectId(widget.effect);
    final plain = fx == 0 &&
        g.toneIsIdentity &&
        g.vignette == 0 &&
        g.grain == 0 &&
        _isIdentity(g.matrix);
    if (plain) return widget.child;
    final shader = _ticker != null && _flip ? _shaderB : _shader;
    if (shader == null || !PhlioLookShader.supported) {
      // Fallback: matrix + linearised tone curve.
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(lookFlutterMatrix(mulLook(toneAsMatrix(g), g.matrix))),
        child: widget.child,
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      final m = g.matrix;
      final values = <double>[
        box.maxWidth * dpr, box.maxHeight * dpr, _time, //
        m[0], m[1], m[2], m[3],
        m[4], m[5], m[6], m[7],
        m[8], m[9], m[10], m[11],
        ...g.lift, ...g.gamma, ...g.gain,
        g.vignette, g.grain,
        fx.toDouble(), widget.effectAmount,
      ];
      for (var i = 0; i < values.length; i++) {
        shader.setFloat(i, values[i].isFinite ? values[i] : 0);
      }
      return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: widget.child);
    });
  }

  static bool _isIdentity(List<double> m) {
    for (var i = 0; i < 12; i++) {
      if ((m[i] - LookGrade.identityMatrix[i]).abs() > 1e-4) return false;
    }
    return true;
  }
}

/// A row of look thumbnails (Instagram's filter strip).
class PhlioLookStrip extends StatelessWidget {
  const PhlioLookStrip({
    required this.selected,
    required this.onPick,
    required this.thumb,
    this.effect = false,
    super.key,
  });
  final String selected;
  final ValueChanged<String> onPick;
  final Widget thumb;

  /// Show effects instead of looks.
  final bool effect;

  @override
  Widget build(BuildContext context) {
    final items = effect
        ? [for (final (id, label, _) in phlioEffects) (id, label)]
        : [for (final e in phlioLookNames.entries) (e.key, e.value)];
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final (id, label) = items[i];
        final on = id == selected;
        return GestureDetector(
          onTap: () => onPick(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      color: on ? Colors.white : Colors.white60,
                      fontSize: 11.5,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: on ? Colors.white : Colors.transparent, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: effect
                      ? PhlioLook(effect: id, child: thumb)
                      : PhlioLook(look: id, child: thumb),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
