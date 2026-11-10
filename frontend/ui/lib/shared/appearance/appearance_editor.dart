// The appearance controls shared by the profile editor and the DM chat
// theme sheet: background colour, wallpaper (none / photo / live shader
// presets), dim, and animated effects with tint and intensity.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/config/app_config.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../moments/templates/template_canvas.dart';
import '../moments/templates/template_model.dart';
import 'appearance.dart';
import 'themes.dart';

/// Live wallpaper presets offered (moment-backdrop shader styles).
const liveWallpaperStyles = [
  BackdropStyle.mesh,
  BackdropStyle.aurora,
  BackdropStyle.holo,
  BackdropStyle.sunburst,
  BackdropStyle.film,
  BackdropStyle.grid,
  BackdropStyle.halftone,
  BackdropStyle.linear,
];

/// Picks a photo from the gallery and uploads it; null if cancelled.
Future<String?> pickAndUploadWallpaper(
    BuildContext context, AppearanceApi api) async {
  final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery, maxWidth: 2160, imageQuality: 88);
  if (picked == null) return null;
  try {
    return await api.uploadWallpaper(picked.path);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not upload that photo. Try another one.')));
    }
    return null;
  }
}

class AppearanceEditor extends StatefulWidget {
  const AppearanceEditor({
    required this.value,
    required this.onChanged,
    required this.onPickPhoto,
    this.onInteract,
    super.key,
  });

  final Appearance value;
  final ValueChanged<Appearance> onChanged;

  /// Picks + uploads a wallpaper photo, returning its url.
  final Future<String?> Function() onPickPhoto;

  /// Told what kind of control was touched ('color', 'wallpaper', 'effect'),
  /// so a mascot can react.
  final ValueChanged<String>? onInteract;

  @override
  State<AppearanceEditor> createState() => _AppearanceEditorState();
}

class _AppearanceEditorState extends State<AppearanceEditor> {
  bool _uploading = false;

  Appearance get v => widget.value;

  void _set(Appearance next, String what) {
    // A colour or wallpaper of your own replaces a ready-made theme.
    if (what == 'color' || what == 'wallpaper') {
      next = next.copyWith(clearTemplate: true);
    }
    HapticFeedback.selectionClick();
    widget.onInteract?.call(what);
    widget.onChanged(next);
  }

  Future<void> _photo() async {
    setState(() => _uploading = true);
    try {
      final url = await widget.onPickPhoto();
      if (url != null && mounted) {
        _set(v.copyWith(wallpaper: WallpaperType.photo, photoUrl: url),
            'wallpaper');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back to the normal page theme in one tap.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          child: v.isPlain
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => _set(Appearance.plain, 'reset'),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Use the default theme'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PhlioColors.textPrimary,
                      side: const BorderSide(color: PhlioColors.border),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
        ),
        _header('Themes'),
        SizedBox(
          height: 128,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final theme in appearanceThemes) _themeTile(theme),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _header('Background colour'),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _swatch(
                null,
                selected: v.background == null,
                onTap: () =>
                    _set(v.copyWith(clearBackground: true), 'color'),
              ),
              for (final c in appearanceSwatches)
                _swatch(c,
                    selected: v.background == c,
                    onTap: () => _set(v.copyWith(background: c), 'color')),
            ],
          ),
        ),
        _HueSlider(
          // Continuous drag: no haptic tick per frame.
          onChanged: (color) {
            widget.onInteract?.call('color');
            widget.onChanged(
                v.copyWith(background: color, clearTemplate: true));
          },
        ),
        const SizedBox(height: 18),
        _header('Wallpaper'),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _wallTile(
                selected: v.wallpaper == WallpaperType.none,
                label: 'None',
                onTap: () =>
                    _set(v.copyWith(wallpaper: WallpaperType.none), 'wallpaper'),
                child: const Icon(Icons.hide_image_outlined,
                    color: PhlioColors.textMuted),
              ),
              _wallTile(
                selected: v.wallpaper == WallpaperType.photo,
                label: 'Photo',
                onTap: _uploading ? null : _photo,
                child: _uploading
                    ? const Center(
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : v.photoUrl != null
                        ? Image.network(AppConfig.mediaUrl(v.photoUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.add_photo_alternate_outlined))
                        : const Icon(Icons.add_photo_alternate_outlined,
                            color: PhlioColors.textSecondary),
              ),
              for (final style in liveWallpaperStyles)
                _wallTile(
                  selected: v.wallpaper == WallpaperType.live &&
                      v.liveStyle == style,
                  label: backdropNames[style]!,
                  onTap: () => _set(
                      v.copyWith(wallpaper: WallpaperType.live, liveStyle: style),
                      'wallpaper'),
                  child: TemplateBackdrop(
                    backdrop: TBackdrop(
                        style, [...backdropPalettes[v.palette]],
                        grain: .1),
                    animate: v.wallpaper == WallpaperType.live &&
                        v.liveStyle == style,
                    time: v.wallpaper == WallpaperType.live &&
                            v.liveStyle == style
                        ? null
                        : 4,
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: v.wallpaper == WallpaperType.none
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (v.wallpaper == WallpaperType.live) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final (i, palette) in backdropPalettes.indexed)
                              _paletteChip(i, palette),
                          ],
                        ),
                      ),
                    ],
                    _slider('Dim', v.dim, 0, 0.8,
                        (x) => widget.onChanged(v.copyWith(dim: x))),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        _header('Effects'),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
          children: [
            for (final effect in AppearanceEffect.values) _effectTile(effect),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: v.effect == AppearanceEffect.none
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final c in appearanceSwatches.skip(8))
                            _swatch(c,
                                size: 30,
                                selected: v.effectColor == c,
                                onTap: () => _set(
                                    v.copyWith(effectColor: c), 'effect')),
                        ],
                      ),
                    ),
                    _slider(
                        'Intensity',
                        v.intensity,
                        0.1,
                        1,
                        (x) => widget.onChanged(v.copyWith(intensity: x))),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _themeTile(AppearanceTheme theme) {
    final selected = v.template == theme.id;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () {
          if (!theme.available) {
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                  content: Text('${theme.name} theme is coming soon.')));
            return;
          }
          _set(theme.appearance, 'theme');
        },
        child: Column(children: [
          AnimatedScale(
            scale: selected ? 1 : 0.95,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 70,
              height: 100,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: theme.colors),
                border: Border.all(
                  color: selected
                      ? PhlioColors.brandOrange
                      : PhlioColors.borderSubtle,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Stack(fit: StackFit.expand, children: [
                if (theme.available)
                  ThemeBackdrop(
                      theme: theme, animate: selected, decorate: false),
                Center(
                  child: Icon(theme.icon,
                      color: theme.available
                          ? theme.accent
                          : Colors.white.withValues(alpha: 0.85)),
                ),
                if (!theme.available)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Soon',
                          style: TextStyle(fontSize: 9, color: Colors.white)),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 74,
            child: Text(theme.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: PhlioTypography.caption.copyWith(
                    fontSize: 10,
                    color: selected
                        ? PhlioColors.textPrimary
                        : PhlioColors.textMuted)),
          ),
        ]),
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: PhlioTypography.bodyStrong),
      );

  Widget _swatch(Color? color,
      {required bool selected, required VoidCallback onTap, double size = 36}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: color == null ? 'Default' : 'Colour',
        child: GestureDetector(
          onTap: onTap,
          // No overshooting curve here: margin and shadow must never go
          // negative mid-animation.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            margin: EdgeInsets.all(selected ? 0 : 3),
            decoration: BoxDecoration(
              color: color ?? PhlioColors.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? PhlioColors.textPrimary : PhlioColors.border,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected && color != null
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: 12)
                    ]
                  : null,
            ),
            child: color == null
                ? const Icon(Icons.format_color_reset_rounded,
                    size: 16, color: PhlioColors.textMuted)
                : null,
          ),
        ),
      ),
    );
  }

  Widget _wallTile({
    required bool selected,
    required String label,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedScale(
              scale: selected ? 1 : 0.94,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 58,
                height: 84,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: PhlioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? PhlioColors.brandOrange
                        : PhlioColors.borderSubtle,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: child,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: PhlioTypography.caption.copyWith(
                    fontSize: 10,
                    color: selected
                        ? PhlioColors.textPrimary
                        : PhlioColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _paletteChip(int index, List<Color> palette) {
    final selected = v.palette == index;
    return GestureDetector(
      onTap: () => _set(v.copyWith(palette: index), 'wallpaper'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        width: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: palette.take(3).toList()),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? PhlioColors.textPrimary : Colors.transparent,
              width: 2),
        ),
      ),
    );
  }

  Widget _effectTile(AppearanceEffect effect) {
    final selected = v.effect == effect;
    return GestureDetector(
      onTap: () => _set(v.copyWith(effect: effect), 'effect'),
      child: Column(
        children: [
          Expanded(
            child: AnimatedScale(
              scale: selected ? 1 : 0.93,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? PhlioColors.brandOrange
                        : PhlioColors.borderSubtle,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (effect != AppearanceEffect.none)
                      EffectLayer(
                        effect: effect,
                        color: selected ? v.effectColor : const Color(0xFFFFD27A),
                        intensity: 0.9,
                        // Only the chosen tile moves (keeps the GPU calm).
                        animate: selected,
                      ),
                    Center(
                      child: Icon(effect.icon,
                          size: 18,
                          color: Colors.white.withValues(
                              alpha: effect == AppearanceEffect.none ? .6 : .35)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(effect.label,
              style: PhlioTypography.caption.copyWith(
                  fontSize: 11,
                  color: selected
                      ? PhlioColors.textPrimary
                      : PhlioColors.textMuted)),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 70, child: Text(label, style: PhlioTypography.caption)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: PhlioColors.brandOrange,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// A rainbow strip for picking any (darkened) background hue.
class _HueSlider extends StatefulWidget {
  const _HueSlider({required this.onChanged});
  final ValueChanged<Color> onChanged;

  @override
  State<_HueSlider> createState() => _HueSliderState();
}

class _HueSliderState extends State<_HueSlider> {
  double? _hue;

  void _at(Offset local, double width) {
    final hue = (local.dx / width).clamp(0.0, 1.0) * 360;
    setState(() => _hue = hue);
    widget.onChanged(HSLColor.fromAHSL(1, hue, 0.45, 0.16).toColor());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onPanDown: (d) => _at(d.localPosition, box.maxWidth),
          onPanUpdate: (d) => _at(d.localPosition, box.maxWidth),
          child: SizedBox(
            height: 26,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(colors: [
                      for (var h = 0; h <= 360; h += 60)
                        HSLColor.fromAHSL(1, h.toDouble(), 0.6, 0.45).toColor(),
                    ]),
                  ),
                ),
                if (_hue != null)
                  Positioned(
                    left: (_hue! / 360) * (box.maxWidth - 22),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HSLColor.fromAHSL(1, _hue!, 0.6, 0.45).toColor(),
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
