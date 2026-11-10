// Phlio Studio templates: one-tap looks for a whole video, in the spirit of
// CapCut / OpenCut presets. A template sets the grade (filter + adjust),
// a clip effect, camera motion, in/out animations, transitions, the canvas
// (aspect ratio + background) and styled title text — all as ordinary
// editor settings, so everything stays editable afterwards and the export
// matches the preview exactly.
//
// The panel shows each template as a live preview card: the current clip's
// frame graded with that template's colour matrix, framed at its aspect
// ratio, with its vignette / effect hint and title text. Tapping a card
// applies it to the project and replays the video from the start.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'studio/studio_model.dart';

/// A title placed by a template.
class TemplateText {
  const TemplateText(
    this.text, {
    this.y = .5,
    this.x = .5,
    this.size = .085,
    this.style = 'shadow',
    this.font = 'Manrope',
    this.color = 0xFFFFFFFF,
    this.accent = 0xFF8D78FF,
    this.animIn = 'fade',
    this.animOut = 'fade',
    this.loop = 'none',
    this.when = 'start',
    this.seconds = 2.6,
    this.bold = true,
  });

  final String text;
  final double x, y, size;
  final String style, font, animIn, animOut, loop;
  final int color, accent;

  /// start (first [seconds]) | end (last [seconds]) | full (whole video).
  final String when;
  final double seconds;
  final bool bold;
}

class StudioTemplate {
  const StudioTemplate({
    required this.id,
    required this.name,
    required this.tagline,
    this.filter = 'none',
    this.amount = 1,
    this.adjust = const {},
    this.effect = 'none',
    this.motion = 'none',
    this.animIn = 'none',
    this.animOut = 'none',
    this.transition = 'none',
    this.ratio,
    this.background,
    this.fit,
    this.texts = const [],
  });

  final String id, name, tagline;
  final String filter;
  final double amount;
  final Map<String, double> adjust;
  final String effect, motion, animIn, animOut, transition;

  /// null keeps the project's current ratio / background / fit.
  final String? ratio, background, fit;
  final List<TemplateText> texts;
}

/// Overlays a template adds carry this id prefix, so switching templates
/// replaces them instead of piling up.
const templateOverlayPrefix = 'tpl_';

const studioTemplates = <StudioTemplate>[
  StudioTemplate(
    id: 'cinematic',
    name: 'Cinematic',
    tagline: 'Widescreen grade',
    filter: 'cinematic',
    adjust: {'contrast': .15, 'vignette': .45, 'fade': .1},
    motion: 'zoom_in',
    animIn: 'fade',
    animOut: 'fade',
    transition: 'fadeblack',
    ratio: '2.35:1',
    background: '#000000',
    fit: 'fill',
    texts: [
      TemplateText('CHAPTER ONE',
          y: .5, size: .05, style: 'plain', font: 'serif', bold: false, seconds: 2.4),
    ],
  ),
  StudioTemplate(
    id: 'vlog',
    name: 'Daily vlog',
    tagline: 'Warm + title card',
    filter: 'golden',
    amount: .8,
    adjust: {'saturation': .1, 'brightness': .05},
    motion: 'zoom_in',
    animIn: 'fade',
    transition: 'fade',
    ratio: '9:16',
    background: 'blur',
    texts: [
      TemplateText('today\'s vlog ✨',
          y: .16, size: .075, style: 'box', accent: 0xFF8D78FF, animIn: 'pop'),
      TemplateText('a little day out',
          y: .86, size: .045, style: 'shadow', font: 'Quicksand', bold: false, when: 'full'),
    ],
  ),
  StudioTemplate(
    id: 'vhs',
    name: 'Retro VHS',
    tagline: 'Tape look, timestamp',
    filter: 'vintage',
    amount: .7,
    adjust: {'grain': .5, 'saturation': -.1, 'contrast': .1},
    effect: 'vhs',
    animIn: 'fade',
    ratio: '4:3',
    background: '#000000',
    fit: 'fill',
    texts: [
      TemplateText('▶ PLAY',
          x: .2, y: .1, size: .055, style: 'plain', font: 'monospace', when: 'full', animIn: 'none'),
      TemplateText('OCT 18 1998',
          x: .74, y: .9, size: .045, style: 'plain', font: 'monospace', when: 'full',
          color: 0xFFF6B93B, animIn: 'none'),
    ],
  ),
  StudioTemplate(
    id: 'memories',
    name: 'Film memories',
    tagline: 'Old film, soft fade',
    filter: 'fade',
    adjust: {'grain': .6, 'vignette': .5, 'temperature': .25},
    effect: 'film',
    motion: 'pan_right',
    animIn: 'fade',
    animOut: 'fade',
    transition: 'dissolve',
    ratio: '4:5',
    background: '#0B0F17',
    texts: [
      TemplateText('memories', y: .82, size: .09, style: 'shadow', font: 'serif', bold: false),
    ],
  ),
  StudioTemplate(
    id: 'glitch',
    name: 'Glitch drop',
    tagline: 'Punchy, beat-ready',
    filter: 'teal',
    adjust: {'contrast': .3, 'saturation': .2},
    effect: 'glitch',
    animIn: 'fade_white',
    transition: 'pixelize',
    ratio: '9:16',
    background: 'blur',
    texts: [
      TemplateText('DROP',
          y: .5, size: .16, style: 'neon', accent: 0xFFE795D7, animIn: 'pop', loop: 'pulse'),
    ],
  ),
  StudioTemplate(
    id: 'dream',
    name: 'Soft dream',
    tagline: 'Pastel glow',
    filter: 'dream',
    adjust: {'fade': .2, 'brightness': .08},
    effect: 'soft',
    motion: 'zoom_out',
    animIn: 'fade',
    animOut: 'fade',
    transition: 'fade',
    ratio: '4:5',
    background: 'blur',
    texts: [
      TemplateText('dreamy days',
          y: .8, size: .07, style: 'outline', font: 'Quicksand', accent: 0xFFE795D7, loop: 'float'),
    ],
  ),
  StudioTemplate(
    id: 'noir',
    name: 'Noir',
    tagline: 'Black & white drama',
    filter: 'noir',
    adjust: {'vignette': .6, 'sharpen': .3},
    motion: 'zoom_in',
    animIn: 'fade',
    animOut: 'fade',
    transition: 'fadeblack',
    ratio: '16:9',
    background: '#000000',
    texts: [
      TemplateText('NOIR', y: .5, size: .12, style: 'outline', font: 'serif', accent: 0xFFFFFFFF),
    ],
  ),
  StudioTemplate(
    id: 'phlio',
    name: 'Phlio pop',
    tagline: 'Vivid + gradient title',
    filter: 'vivid',
    adjust: {'saturation': .15},
    motion: 'zoom_out',
    animIn: 'fade',
    transition: 'zoomin',
    ratio: '9:16',
    background: 'blur',
    texts: [
      TemplateText('made on Phlio',
          y: .14, size: .07, style: 'gradient', animIn: 'drop', loop: 'bounce'),
    ],
  ),
  StudioTemplate(
    id: 'travel',
    name: 'Travel diary',
    tagline: 'Golden hour pan',
    filter: 'sunset',
    adjust: {'temperature': .2, 'contrast': .08},
    motion: 'pan_left',
    animIn: 'fade',
    animOut: 'fade',
    transition: 'slideleft',
    ratio: '9:16',
    background: 'blur',
    texts: [
      TemplateText('📍 somewhere new', y: .12, size: .06, style: 'box', accent: 0xFF0B0F17),
      TemplateText('to be continued…', y: .5, size: .07, style: 'shadow', font: 'serif', when: 'end'),
    ],
  ),
  StudioTemplate(
    id: 'night',
    name: 'Moody night',
    tagline: 'Deep blues, RGB split',
    filter: 'moody',
    adjust: {'temperature': -.25, 'contrast': .15, 'vignette': .35},
    effect: 'rgb_split',
    animIn: 'fade',
    transition: 'hblur',
    ratio: '9:16',
    background: 'blur',
    texts: [
      TemplateText('after dark', y: .85, size: .07, style: 'neon', accent: 0xFF72A7FF, loop: 'blink'),
    ],
  ),
];

/// Applies [tpl] (or removes the current template when null) to [p].
void applyStudioTemplate(StudioProject p, StudioTemplate? tpl) {
  p.overlays.removeWhere((o) => o.id.startsWith(templateOverlayPrefix));
  for (var i = 0; i < p.clips.length; i++) {
    final c = p.clips[i];
    c
      ..filter = tpl?.filter ?? 'none'
      ..filterAmount = tpl?.amount ?? 1
      ..adjust = Map<String, double>.of(tpl?.adjust ?? const {})
      ..effect = tpl?.effect ?? 'none'
      ..motion = tpl?.motion ?? 'none'
      ..animIn = i == 0 ? (tpl?.animIn ?? 'none') : 'none'
      ..animOut = i == p.clips.length - 1 ? (tpl?.animOut ?? 'none') : 'none'
      ..transition = i < p.clips.length - 1 ? (tpl?.transition ?? 'none') : 'none';
    if (tpl?.fit != null) c.fit = tpl!.fit!;
  }
  if (tpl == null) return;
  if (tpl.ratio != null) p.ratio = tpl.ratio!;
  if (tpl.background != null) {
    p.background = tpl.background!;
    // A coloured canvas only shows around clips that are fitted, not filled.
    if (tpl.background != 'blur' && tpl.fit == null) {
      for (final c in p.clips) {
        c.fit = 'fit';
      }
    }
  }
  final total = math.max(1.0, p.total);
  for (final (i, text) in tpl.texts.indexed) {
    final length = math.min(text.seconds, total);
    final (start, end) = switch (text.when) {
      'full' => (0.0, total),
      'end' => (math.max(0.0, total - length), total),
      _ => (0.0, length),
    };
    p.overlays.add(StudioOverlay(
      kind: 'text',
      id: '$templateOverlayPrefix${tpl.id}_${i}_${studioId()}',
      text: text.text,
      x: text.x,
      y: text.y,
      size: text.size,
      start: start,
      end: end,
    )
      ..font = text.font
      ..color = text.color
      ..accent = text.accent
      ..style = text.style
      ..bold = text.bold
      ..animIn = text.animIn
      ..animOut = text.animOut
      ..loop = text.loop);
  }
}

double _ratioValue(String? r) => switch (r) {
      '9:16' => 9 / 16,
      '16:9' => 16 / 9,
      '1:1' => 1,
      '4:5' => 4 / 5,
      '3:4' => 3 / 4,
      '4:3' => 4 / 3,
      '2:1' => 2,
      '2.35:1' => 2.35,
      _ => 9 / 16,
    };

/// The Templates panel body: None + a card per template.
class StudioTemplatesPanel extends StatelessWidget {
  const StudioTemplatesPanel({
    super.key,
    required this.thumb,
    required this.selected,
    required this.onPick,
  });

  /// The current clip's frame (filmstrip / photo).
  final Widget thumb;
  final String? selected;
  final ValueChanged<StudioTemplate?> onPick;

  @override
  Widget build(BuildContext context) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        itemCount: studioTemplates.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _Card(
              label: 'None',
              tagline: 'Remove template',
              on: selected == null,
              onTap: () => onPick(null),
              preview: const ColoredBox(
                color: Color(0xFF1C2433),
                child: Center(
                    child: Icon(Icons.block_rounded, color: Colors.white54, size: 28)),
              ),
            );
          }
          final tpl = studioTemplates[i - 1];
          return _Card(
            label: tpl.name,
            tagline: tpl.tagline,
            on: selected == tpl.id,
            onTap: () => onPick(tpl),
            preview: TemplatePreview(template: tpl, thumb: thumb),
          );
        },
      );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.label,
    required this.tagline,
    required this.on,
    required this.onTap,
    required this.preview,
  });
  final String label, tagline;
  final bool on;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 96,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 128,
              width: 96,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: on
                    ? const LinearGradient(
                        colors: [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F)])
                    : null,
                color: on ? null : const Color(0xFF1C2433),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: preview),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: on ? const Color(0xFFB7A9FF) : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            Text(tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
          ]),
        ),
      );
}

/// A live miniature of the template over the current frame.
class TemplatePreview extends StatelessWidget {
  const TemplatePreview({super.key, required this.template, required this.thumb});
  final StudioTemplate template;
  final Widget thumb;

  Color get _canvas {
    final bg = template.background;
    if (bg == null || bg == 'blur') return const Color(0xFF0B0F17);
    return Color(int.parse('FF${bg.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final matrix = flutterColorMatrix(
        studioColorMatrix(template.filter, template.amount, template.adjust));
    final vignette = math.max(template.adjust['vignette'] ?? 0,
        template.effect == 'film' ? .4 : 0.0);
    final frame = Stack(fit: StackFit.expand, children: [
      ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: thumb),
      if (vignette > 0)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: .9,
              colors: [Colors.transparent, Colors.black.withValues(alpha: .75 * vignette)],
              stops: const [.55, 1],
            ),
          ),
        ),
      if (const {'vhs', 'film', 'glitch', 'rgb_split'}.contains(template.effect) ||
          (template.adjust['grain'] ?? 0) > 0)
        CustomPaint(painter: _EffectHint(template.effect)),
      if (template.effect == 'soft')
        ColoredBox(color: Colors.white.withValues(alpha: .12)),
    ]);
    final ratio = _ratioValue(template.ratio);
    return ColoredBox(
      color: _canvas,
      child: Stack(fit: StackFit.expand, children: [
        if (template.background == 'blur' || template.background == null)
          Opacity(
            opacity: .35,
            child: ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: thumb),
          ),
        Center(child: AspectRatio(aspectRatio: ratio, child: frame)),
        for (final text in template.texts.take(2))
          Align(
            alignment: Alignment(text.x * 2 - 1, text.y * 2 - 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _MiniTitle(text: text),
            ),
          ),
      ]),
    );
  }
}

class _MiniTitle extends StatelessWidget {
  const _MiniTitle({required this.text});
  final TemplateText text;

  @override
  Widget build(BuildContext context) {
    final fontSize = (text.size * 96).clamp(6.0, 15.0);
    final family = switch (text.font) {
      'serif' => 'serif',
      'monospace' => 'monospace',
      _ => text.font,
    };
    final base = TextStyle(
      fontSize: fontSize,
      fontFamily: family,
      fontWeight: text.bold ? FontWeight.w800 : FontWeight.w500,
      color: Color(text.color),
      height: 1.1,
    );
    final label = Text(text.text,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: switch (text.style) {
          'shadow' => base.copyWith(shadows: const [Shadow(blurRadius: 4, color: Colors.black)]),
          'neon' => base.copyWith(shadows: [
              Shadow(blurRadius: 6, color: Color(text.accent)),
              Shadow(blurRadius: 12, color: Color(text.accent)),
            ]),
          'outline' => base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = .8
                ..color = Color(text.accent)),
          _ => base,
        });
    if (text.style == 'box') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
            color: Color(text.accent), borderRadius: BorderRadius.circular(3)),
        child: label,
      );
    }
    if (text.style == 'gradient') {
      return ShaderMask(
        shaderCallback: (r) => const LinearGradient(
                colors: [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F)])
            .createShader(r),
        child: Text(text.text,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: base.copyWith(color: Colors.white)),
      );
    }
    return label;
  }
}

/// Scanlines / film scratches / RGB fringes / grain, as a static hint.
class _EffectHint extends CustomPainter {
  _EffectHint(this.effect);
  final String effect;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(effect.hashCode);
    switch (effect) {
      case 'vhs':
        final line = Paint()..color = Colors.black.withValues(alpha: .22);
        for (var y = 0.0; y < size.height; y += 3) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
        }
        canvas.drawRect(Rect.fromLTWH(0, size.height * .7, size.width, 3),
            Paint()..color = Colors.white.withValues(alpha: .25));
      case 'glitch' || 'rgb_split':
        for (var i = 0; i < 4; i++) {
          final y = rng.nextDouble() * size.height;
          canvas.drawRect(
              Rect.fromLTWH(rng.nextDouble() * 10, y, size.width * .8, 3 + rng.nextDouble() * 4),
              Paint()
                ..color = (i.isEven ? const Color(0xFFFF2E8B) : const Color(0xFF00E5FF))
                    .withValues(alpha: .35)
                ..blendMode = BlendMode.screen);
        }
      case 'film':
        final scratch = Paint()
          ..color = Colors.white.withValues(alpha: .3)
          ..strokeWidth = .6;
        for (var i = 0; i < 3; i++) {
          final x = rng.nextDouble() * size.width;
          canvas.drawLine(Offset(x, 0), Offset(x + 2, size.height), scratch);
        }
    }
    final grain = Paint()..color = Colors.white.withValues(alpha: .08);
    for (var i = 0; i < 140; i++) {
      canvas.drawCircle(
          Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), .5, grain);
    }
  }

  @override
  bool shouldRepaint(covariant _EffectHint old) => old.effect != effect;
}
