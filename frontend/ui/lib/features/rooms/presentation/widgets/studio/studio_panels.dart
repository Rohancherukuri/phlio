// Bottom panels for Phlio Studio (CapCut-style: a titled sheet that
// replaces the toolbar, with a ✓ to close).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/colors.dart';
import '../../../../../design_system/widgets/foxy_pack.dart';
import 'studio_model.dart';

const studioViolet = PhlioColors.brandViolet;
const studioPanelBg = Color(0xFF111722);

/// Panel chrome: title, optional "Apply to all", ✓.
class StudioPanel extends StatelessWidget {
  const StudioPanel({
    required this.title,
    required this.child,
    required this.onDone,
    this.onApplyAll,
    this.height = 196,
    super.key,
  });
  final String title;
  final Widget child;
  final VoidCallback onDone;
  final VoidCallback? onApplyAll;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        color: studioPanelBg,
        child: Column(children: [
          SizedBox(
            height: 44,
            child: Row(children: [
              const SizedBox(width: 6),
              if (onApplyAll != null)
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onApplyAll!();
                  },
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Apply to all'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Done',
                onPressed: onDone,
                icon: const Icon(Icons.check_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 4),
            ]),
          ),
          Expanded(child: child),
        ]),
      );
}

/// A labelled slider with a value bubble.
class StudioSlider extends StatelessWidget {
  const StudioSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.label,
    this.format,
    this.divisions,
    super.key,
  });
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;
  final String Function(double)? format;
  final int? divisions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          if (label != null)
            SizedBox(
                width: 76,
                child: Text(label!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white12,
                valueIndicatorColor: studioViolet,
                showValueIndicator: ShowValueIndicator.always,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: format?.call(value) ?? value.toStringAsFixed(1),
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(format?.call(value) ?? value.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// Horizontal option strip (transitions, animations, ratios, effects…).
class StudioOptionStrip extends StatelessWidget {
  const StudioOptionStrip({
    required this.options,
    required this.selected,
    required this.onPick,
    this.icon,
    this.tile = 64,
    super.key,
  });
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onPick;
  final Widget Function(String id, bool selected)? icon;
  final double tile;

  @override
  Widget build(BuildContext context) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (id, label) = options[i];
          final on = id == selected;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onPick(id);
            },
            child: SizedBox(
              width: tile,
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2433),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: on ? Colors.white : Colors.transparent, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: icon?.call(id, on) ??
                      Icon(id == 'none' ? Icons.block_rounded : Icons.auto_awesome_rounded,
                          color: on ? Colors.white : Colors.white60),
                ),
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: on ? Colors.white : Colors.white60,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
              ]),
            ),
          );
        },
      );
}

/// Filter strip using the clip's own thumbnail through each matrix.
class StudioFilterPanel extends StatelessWidget {
  const StudioFilterPanel({
    required this.thumb,
    required this.filter,
    required this.amount,
    required this.onFilter,
    required this.onAmount,
    super.key,
  });
  final Widget thumb;
  final String filter;
  final double amount;
  final ValueChanged<String> onFilter;
  final ValueChanged<double> onAmount;

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: StudioOptionStrip(
            options: [for (final e in studioFilterNames.entries) (e.key, e.value)],
            selected: filter,
            onPick: onFilter,
            icon: (id, _) => id == 'none'
                ? const Icon(Icons.block_rounded, color: Colors.white60)
                : ColorFiltered(
                    colorFilter: ColorFilter.matrix(
                        flutterColorMatrix(studioColorMatrix(id, 1, const {}))),
                    child: thumb),
          ),
        ),
        if (filter != 'none')
          StudioSlider(
            value: amount,
            min: 0,
            max: 1,
            onChanged: onAmount,
            format: (v) => '${(v * 100).round()}',
          ),
        const SizedBox(height: 6),
      ]);
}

class StudioAdjustPanel extends StatefulWidget {
  const StudioAdjustPanel({required this.adjust, required this.onChanged, required this.onCommit, super.key});
  final Map<String, double> adjust;
  final void Function(String key, double value) onChanged;
  final VoidCallback onCommit;
  @override
  State<StudioAdjustPanel> createState() => _StudioAdjustPanelState();
}

class _StudioAdjustPanelState extends State<StudioAdjustPanel> {
  String _key = 'brightness';
  static const _icons = {
    'brightness': Icons.wb_sunny_outlined,
    'contrast': Icons.contrast_rounded,
    'saturation': Icons.water_drop_outlined,
    'exposure': Icons.exposure_rounded,
    'temperature': Icons.thermostat_rounded,
    'tint': Icons.colorize_rounded,
    'hue': Icons.palette_outlined,
    'fade': Icons.gradient_rounded,
    'vignette': Icons.vignette_outlined,
    'sharpen': Icons.details_rounded,
    'grain': Icons.grain_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final uni = studioUnipolar.contains(_key);
    final value = widget.adjust[_key] ?? 0;
    return Column(children: [
      SizedBox(
        height: 76,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            for (final (key, label) in studioAdjustments)
              GestureDetector(
                onTap: () => setState(() => _key = key),
                child: SizedBox(
                  width: 66,
                  child: Column(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: key == _key ? Colors.white : const Color(0xFF1C2433),
                        border: (widget.adjust[key] ?? 0) != 0 && key != _key
                            ? Border.all(color: studioViolet, width: 2)
                            : null,
                      ),
                      child: Icon(_icons[key], size: 20,
                          color: key == _key ? const Color(0xFF0B0F17) : Colors.white70),
                    ),
                    const SizedBox(height: 5),
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            color: key == _key ? Colors.white : Colors.white60,
                            fontWeight: key == _key ? FontWeight.w800 : FontWeight.w500)),
                  ]),
                ),
              ),
          ],
        ),
      ),
      StudioSlider(
        value: value,
        min: uni ? 0 : -1,
        max: 1,
        onChanged: (v) => widget.onChanged(_key, v.abs() < .03 ? 0 : v),
        onChangeEnd: (_) => widget.onCommit(),
        format: (v) => '${(v * 100).round()}',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            for (final (key, _) in studioAdjustments) {
              widget.onChanged(key, 0);
            }
            widget.onCommit();
          },
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Reset'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      ),
    ]);
  }
}

/// Visual tiles for effects / transitions (no assets needed).
Widget studioEffectTile(String id, bool on) {
  const icons = {
    'none': Icons.block_rounded,
    'vignette': Icons.vignette_outlined,
    'grain': Icons.grain_rounded,
    'blur': Icons.blur_on_rounded,
    'soft': Icons.flare_rounded,
    'glitch': Icons.broken_image_outlined,
    'rgb_split': Icons.filter_tilt_shift_rounded,
    'vhs': Icons.videocam_outlined,
    'film': Icons.movie_filter_outlined,
    'mirror': Icons.flip_rounded,
    'shake': Icons.vibration_rounded,
    'flash': Icons.flash_on_rounded,
    'pixelate': Icons.grid_on_rounded,
  };
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: id == 'none'
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HSLColor.fromAHSL(1, (id.hashCode % 360).toDouble(), .55, .42).toColor(),
                const Color(0xFF1C2433),
              ]),
    ),
    child: Icon(icons[id] ?? Icons.auto_awesome_rounded, color: Colors.white, size: 26),
  );
}

Widget studioTransitionTile(String id, bool on) {
  const icons = {
    'none': Icons.block_rounded,
    'fade': Icons.gradient_rounded,
    'fadeblack': Icons.dark_mode_outlined,
    'fadewhite': Icons.light_mode_outlined,
    'dissolve': Icons.blur_linear_rounded,
    'slideleft': Icons.west_rounded,
    'slideright': Icons.east_rounded,
    'slideup': Icons.north_rounded,
    'slidedown': Icons.south_rounded,
    'wipeleft': Icons.swipe_left_rounded,
    'circleopen': Icons.radio_button_unchecked_rounded,
    'circleclose': Icons.adjust_rounded,
    'radial': Icons.rotate_right_rounded,
    'zoomin': Icons.zoom_in_rounded,
    'pixelize': Icons.grid_4x4_rounded,
    'hblur': Icons.blur_on_rounded,
    'smoothleft': Icons.waves_rounded,
    'squeezeh': Icons.compress_rounded,
    'distance': Icons.open_in_full_rounded,
  };
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: id == 'none'
          ? null
          : const LinearGradient(colors: [Color(0xFF3B2F7A), Color(0xFF1C2433)]),
    ),
    child: Icon(icons[id] ?? Icons.auto_awesome_motion_rounded,
        color: on ? Colors.white : Colors.white70, size: 24),
  );
}

Widget studioRatioTile(String id, bool on) {
  const sizes = {
    'original': (30.0, 38.0),
    '9:16': (22.0, 38.0),
    '1:1': (32.0, 32.0),
    '4:5': (28.0, 35.0),
    '16:9': (40.0, 22.5),
    '3:4': (27.0, 36.0),
    '4:3': (38.0, 28.5),
    '2:1': (42.0, 21.0),
  };
  final (w, h) = sizes[id] ?? (30.0, 30.0);
  return Center(
    child: Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        border: Border.all(color: on ? Colors.white : Colors.white54, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: id == 'original'
          ? const Icon(Icons.crop_original_rounded, size: 14, color: Colors.white54)
          : null,
    ),
  );
}

/// Speed: 0.25x – 4x on a log scale, CapCut "Normal" speed.
class StudioSpeedPanel extends StatelessWidget {
  const StudioSpeedPanel({required this.speed, required this.onChanged, required this.onCommit, super.key});
  final double speed;
  final ValueChanged<double> onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final pos = (math.log(speed) / math.ln2 + 2) / 4; // 0.25..4 → 0..1
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('${speed.toStringAsFixed(speed < 1 ? 2 : 1)}x',
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      StudioSlider(
        value: pos,
        min: 0,
        max: 1,
        onChanged: (v) {
          var s = math.pow(2, v * 4 - 2).toDouble();
          for (final snap in const [.25, .5, 1.0, 1.5, 2.0, 3.0, 4.0]) {
            if ((s - snap).abs() / snap < .04) s = snap;
          }
          onChanged(double.parse(s.toStringAsFixed(2)));
        },
        onChangeEnd: (_) => onCommit(),
        format: (v) => '${math.pow(2, v * 4 - 2).toStringAsFixed(2)}x',
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 30),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0.25x', style: TextStyle(color: Colors.white38, fontSize: 11)),
          Text('1x', style: TextStyle(color: Colors.white38, fontSize: 11)),
          Text('4x', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ),
    ]);
  }
}

/// Sticker picker: everyday emoji + the Foxy pack.
class StudioStickerPanel extends StatefulWidget {
  const StudioStickerPanel({required this.onEmoji, required this.onAsset, super.key});
  final ValueChanged<String> onEmoji;
  final ValueChanged<String> onAsset;
  @override
  State<StudioStickerPanel> createState() => _StudioStickerPanelState();
}

class _StudioStickerPanelState extends State<StudioStickerPanel> {
  int _tab = 0;
  static const _emoji = [
    '😂', '😍', '🥹', '😎', '🤯', '🥳', '😭', '🔥', '✨', '💜', '🧡', '💯', '👏', '🙌',
    '👀', '🎉', '🌈', '⭐', '🌸', '☀️', '🌙', '⚡', '🎬', '🎵', '📍', '✈️', '🍕', '☕',
    '🐾', '🦊', '💫', '🫶', '👋', '😮', '🤩', '😴',
  ];

  @override
  Widget build(BuildContext context) {
    final foxy = [...FoxyPack.emoji, ...FoxyPack.stickers];
    return Column(children: [
      Row(children: [
        for (final (i, label) in const [(0, 'Emoji'), (1, 'Foxy')])
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: ChoiceChip(
              label: Text(label),
              selected: _tab == i,
              onSelected: (_) => setState(() => _tab = i),
              selectedColor: studioViolet,
              backgroundColor: const Color(0xFF1C2433),
              labelStyle: TextStyle(color: _tab == i ? Colors.white : Colors.white70),
              side: BorderSide.none,
            ),
          ),
      ]),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 56, mainAxisSpacing: 6, crossAxisSpacing: 6),
          itemCount: _tab == 0 ? _emoji.length : foxy.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _tab == 0 ? widget.onEmoji(_emoji[i]) : widget.onAsset(foxy[i].assetPath),
            child: Center(
              child: _tab == 0
                  ? Text(_emoji[i], style: const TextStyle(fontSize: 30))
                  : Image.asset(foxy[i].assetPath, width: 46, height: 46, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    ]);
  }
}
