// Draws story effects (story_fx_catalog.dart) on the GPU and lets people
// pick them.
//
//   * [StoryFxLayer] wraps any picture or video: first the Adjust sliders
//     (a colour grade), then the chosen effect, each an ImageFilter.shader
//     pass with one of assets/shaders/story_*.frag. Animated effects keep
//     ticking. Without Impeller (no shader image filters) the child is
//     shown as-is.
//   * [StoryFxPicker] is the effects strip: category tabs, live thumbnails
//     of your own photo, and "Soon" tiles for AR / AI effects that say
//     "coming soon" when tapped.
//   * [openStoryFxSheet] shows the picker with an intensity slider.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'story_fx_catalog.dart';

class StoryFxShaders {
  static final _programs = <FxShader, ui.FragmentProgram>{};
  static final _loading = <FxShader, Future<ui.FragmentProgram?>>{};

  static bool get supported {
    try {
      return ui.ImageFilter.isShaderFilterSupported;
    } catch (_) {
      return false;
    }
  }

  static ui.FragmentProgram? program(FxShader s) => _programs[s];

  static Future<ui.FragmentProgram?> load(FxShader s) => _loading[s] ??= () async {
        try {
          return _programs[s] = await ui.FragmentProgram.fromAsset('assets/shaders/story_${s.name}.frag');
        } catch (_) {
          return null;
        }
      }();
}

/// Says "<name> is coming soon" for AR and AI effects.
void storyFxComingSoon(BuildContext context, StoryFxDef fx) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('${fx.name} is coming soon — ${fx.kind == FxKind.ar ? 'AR' : 'AI'} effects are on the way.'),
      duration: const Duration(seconds: 2),
    ));
}

class StoryFxLayer extends StatefulWidget {
  const StoryFxLayer({
    required this.child,
    this.fx,
    this.amount = 1,
    this.adjust = const {},
    this.stamp,
    this.animate = true,
    super.key,
  });

  /// Effect id from the catalogue (null / unknown: none).
  final String? fx;
  final double amount;

  /// Adjust sliders (exposure, contrast, warmth…), each -1..1.
  final Map<String, double> adjust;

  /// When the photo was taken (date stamps on Disposable, Y2K, Camcorder).
  final DateTime? stamp;

  /// Thumbnails pass false: a still frame, no ticker.
  final bool animate;
  final Widget child;

  @override
  State<StoryFxLayer> createState() => _StoryFxLayerState();
}

class _StoryFxLayerState extends State<StoryFxLayer> with SingleTickerProviderStateMixin {
  // Two instances per pass, swapped every frame while animating: a filter
  // built from the same shader object compares equal and Flutter would
  // skip the repaint (the effect would freeze).
  final _shaders = <String, ui.FragmentShader>{};
  Ticker? _ticker;
  double _time = 1.7;
  bool _flip = false;

  StoryFxDef? get _def {
    final d = storyFxById[widget.fx];
    return d == null || d.shader == null ? null : d;
  }

  bool get _hasAdjust => widget.adjust.values.any((v) => v.abs() > 1e-4);

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(StoryFxLayer old) {
    super.didUpdateWidget(old);
    if (old.fx != widget.fx || old.animate != widget.animate || old.adjust != widget.adjust) _prepare();
  }

  void _prepare() {
    if (!StoryFxShaders.supported) return;
    final need = <FxShader>{if (_hasAdjust) FxShader.grade, if (_def != null) _def!.shader!};
    for (final s in need) {
      if (StoryFxShaders.program(s) == null) {
        StoryFxShaders.load(s).then((_) {
          if (mounted) setState(() {});
        });
      }
    }
    final animate = widget.animate && (_def?.animated ?? false);
    if (animate && _ticker == null) {
      _ticker = createTicker((elapsed) {
        _time = 1.7 + elapsed.inMicroseconds / 1e6;
        _flip = !_flip;
        if (mounted) setState(() {});
      })
        ..start();
    } else if (!animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  ui.FragmentShader? _shader(FxShader s, String pass) {
    final program = StoryFxShaders.program(s);
    if (program == null) return null;
    final key = '$pass-${s.name}-${_ticker != null && _flip ? 'b' : 'a'}';
    return _shaders[key] ??= program.fragmentShader();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    for (final s in _shaders.values) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    if ((def == null && !_hasAdjust) || !StoryFxShaders.supported) return widget.child;
    return LayoutBuilder(builder: (context, box) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      final w = box.maxWidth.isFinite ? box.maxWidth * dpr : 1080.0;
      final h = box.maxHeight.isFinite ? box.maxHeight * dpr : 1920.0;
      final stamp = widget.stamp ?? DateTime.now();
      Widget out = widget.child;
      if (_hasAdjust) {
        final s = _shader(FxShader.grade, 'adjust');
        if (s != null) {
          _set(s, <double>[w, h, _time, 1.0, ...FxGrade.fromAdjust(widget.adjust).uniforms(stamp)]);
          out = ImageFiltered(imageFilter: ui.ImageFilter.shader(s), child: out);
        }
      }
      if (def != null) {
        final s = _shader(def.shader!, 'fx');
        if (s != null) {
          final amount = widget.amount.clamp(0.0, 1.0);
          final List<double> values = switch (def.shader!) {
            FxShader.grade => <double>[w, h, _time, amount, ...(def.grade ?? const FxGrade()).uniforms(stamp)],
            FxShader.lens => <double>[w, h, _time, def.index.toDouble(), amount, .5, .5],
            // Duotone / tritone inks: Phlio violet and peach.
            FxShader.art => <double>[w, h, _time, def.index.toDouble(), amount, .12, .05, .35, 1.0, .72, .5],
            _ => <double>[w, h, _time, def.index.toDouble(), amount],
          };
          _set(s, values);
          out = ImageFiltered(imageFilter: ui.ImageFilter.shader(s), child: out);
        }
      }
      return out;
    });
  }

  static void _set(ui.FragmentShader s, List<double> values) {
    for (var i = 0; i < values.length; i++) {
      s.setFloat(i, values[i].isFinite ? values[i] : 0);
    }
  }
}

/// Category tabs + a strip of effect thumbnails.
class StoryFxPicker extends StatefulWidget {
  const StoryFxPicker({
    required this.selected,
    required this.thumb,
    required this.onPick,
    this.isVideo = false,
    this.motion,
    super.key,
  });

  /// Current effect id (null: none).
  final String? selected;

  /// Current video time effect (boomerang, slow motion…).
  final String? motion;

  /// Your photo, small (thumbnails draw each effect on it).
  final Widget thumb;
  final bool isVideo;

  /// Called with null for "None". AR / AI effects never reach it.
  final ValueChanged<StoryFxDef?> onPick;

  @override
  State<StoryFxPicker> createState() => _StoryFxPickerState();
}

class _StoryFxPickerState extends State<StoryFxPicker> {
  late String category = storyFxById[widget.selected]?.category ??
      (widget.motion != null ? 'motion' : storyFxCategories.first.$1);

  @override
  Widget build(BuildContext context) {
    final items = [for (final e in storyFxEffects) if (e.category == category) e];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            for (final (id, label) in storyFxCategories)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label),
                    if (id == 'ar' || id == 'ai') ...[
                      const SizedBox(width: 4),
                      const _SoonDot(),
                    ],
                  ]),
                  selected: id == category,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => category = id),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _Tile(
                label: 'None',
                on: widget.selected == null && widget.motion == null,
                onTap: () => widget.onPick(null),
                child: Stack(fit: StackFit.expand, children: [
                  widget.thumb,
                  const ColoredBox(color: Color(0x55000000), child: Icon(Icons.block_rounded, color: Colors.white70)),
                ]),
              );
            }
            final e = items[i - 1];
            final on = e.id == widget.selected || (e.motion != null && e.motion == widget.motion);
            return _Tile(
              label: e.name,
              on: on,
              soon: e.comingSoon,
              video: e.kind == FxKind.video,
              onTap: () {
                if (e.comingSoon) return storyFxComingSoon(context, e);
                if (e.videoOnly && !widget.isVideo) {
                  ScaffoldMessenger.maybeOf(context)
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text('${e.name} works on videos.')));
                  return;
                }
                widget.onPick(e);
              },
              child: e.comingSoon
                  ? _SoonTile(e)
                  : e.videoOnly
                      ? Stack(fit: StackFit.expand, children: [
                          widget.thumb,
                          ColoredBox(
                            color: const Color(0x66000000),
                            child: Icon(_motionIcon(e.motion), color: Colors.white),
                          ),
                        ])
                      : StoryFxLayer(fx: e.id, animate: false, child: widget.thumb),
            );
          },
        ),
      ),
    ]);
  }

  static IconData _motionIcon(String? motion) => switch (motion) {
        'boomerang' => Icons.all_inclusive_rounded,
        'slow_motion' => Icons.slow_motion_video_rounded,
        'hyperlapse' => Icons.fast_forward_rounded,
        'freeze_frame' => Icons.pause_circle_outline_rounded,
        'stop_motion' => Icons.animation_rounded,
        _ => Icons.movie_filter_rounded,
      };
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.on,
    required this.onTap,
    required this.child,
    this.soon = false,
    this.video = false,
  });
  final String label;
  final bool on, soon, video;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: SizedBox(
            width: 66,
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: on ? Colors.white : Colors.transparent, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(fit: StackFit.expand, children: [
                    child,
                    if (soon)
                      const Positioned(top: 4, right: 4, child: _Badge('Soon')),
                    if (video)
                      const Positioned(top: 4, right: 4, child: _Badge('Video')),
                  ]),
                ),
              ),
              const SizedBox(height: 5),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: on ? Colors.white : Colors.white70,
                      fontSize: 11,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
            ]),
          ),
        ),
      );
}

class _SoonTile extends StatelessWidget {
  const _SoonTile(this.fx);
  final StoryFxDef fx;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: fx.kind == FxKind.ar
                ? const [Color(0xFF3A2A5C), Color(0xFF8D78FF)]
                : const [Color(0xFF14323A), Color(0xFF4CC9F0)],
          ),
        ),
        child: Icon(fx.kind == FxKind.ar ? Icons.face_retouching_natural_rounded : Icons.auto_awesome_rounded,
            color: Colors.white70, size: 26),
      );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
      );
}

class _SoonDot extends StatelessWidget {
  const _SoonDot();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: const Color(0x338D78FF), borderRadius: BorderRadius.circular(6)),
        child: const Text('Soon', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
      );
}

/// The picked effect (or video time effect) and its intensity.
class StoryFxChoice {
  const StoryFxChoice({this.fx, this.motion, this.amount = 1});
  final String? fx;
  final String? motion;
  final double amount;
}

/// Bottom sheet: effects picker + intensity. [onChanged] fires live so the
/// preview behind the sheet updates as you browse.
Future<void> openStoryFxSheet(
  BuildContext context, {
  required Widget thumb,
  required StoryFxChoice current,
  required ValueChanged<StoryFxChoice> onChanged,
  bool isVideo = false,
}) {
  var choice = current;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xF0101722),
    barrierColor: Colors.black12,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) {
        final def = storyFxById[choice.fx];
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(children: [
                const Text('Effects', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  choice.motion != null
                      ? '${storyFxEffects.firstWhere((e) => e.motion == choice.motion).name} · applied when you share'
                      : def?.name ?? '$storyFxLiveCount effects',
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
              ]),
            ),
            StoryFxPicker(
              selected: choice.fx,
              motion: choice.motion,
              thumb: thumb,
              isVideo: isVideo,
              onPick: (e) {
                if (e == null) {
                  choice = StoryFxChoice(amount: choice.amount);
                } else if (e.kind == FxKind.video && isVideo) {
                  // Time effects are rendered into the clip by the server.
                  choice = StoryFxChoice(motion: e.motion, amount: choice.amount);
                } else {
                  choice = StoryFxChoice(fx: e.id, amount: choice.amount);
                }
                onChanged(choice);
                setSheet(() {});
              },
            ),
            if (def != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(children: [
                  const Icon(Icons.tune_rounded, color: Colors.white60, size: 18),
                  Expanded(
                    child: Slider(
                      value: choice.amount,
                      onChanged: (v) {
                        choice = StoryFxChoice(fx: choice.fx, motion: choice.motion, amount: v);
                        onChanged(choice);
                        setSheet(() {});
                      },
                    ),
                  ),
                  Text('${(choice.amount * 100).round()}',
                      style: const TextStyle(color: Colors.white70, fontFeatures: [ui.FontFeature.tabularFigures()])),
                ]),
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    ),
  );
}
