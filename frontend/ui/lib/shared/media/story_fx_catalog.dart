// Story effects catalogue: every filter and effect from the Phlio Story
// Effects Guide, grouped the way the picker shows them.
//
//   * shader effects are drawn live on the GPU by one of five fragment
//     shaders (assets/shaders/story_*.frag) — colour grades and film
//     textures (grade), lens and motion (lens), lighting and particles
//     (light), animated scenes (scene) and artistic looks (art);
//   * video effects change time itself (boomerang, slow motion…), so the
//     server renders them into the clip with FFmpeg (backend
//     app/api/v1/media_edits.py); two also have a photo version;
//   * AR and AI effects need face tracking or segmentation models and are
//     shown as "Coming soon".
//
// Grades are data: the same fields drive the editors' Adjust sliders.
// Generated from the effect list; keep ids stable (they're saved with
// moments and snaps in `filter_spec.fx`).

import 'dart:math' as math;

enum FxKind { shader, video, ar, ai }

enum FxShader { grade, lens, light, scene, art }

/// Colour grade + texture op for story_grade.frag.
class FxGrade {
  const FxGrade({
    this.exposure = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.tint = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.fade = 0,
    this.vignette = 0,
    this.grain = 0,
    this.sharpen = 0,
    this.soft = 0,
    this.mono = 0,
    this.clarity = 0,
    this.vibrance = 0,
    this.shadowTone = const [0, 0, 0, 0],
    this.highTone = const [0, 0, 0, 0],
    this.op = 0,
    this.opAmount = 1,
  });

  final double exposure, brightness, contrast, saturation, warmth, tint, highlights, shadows;
  final double fade, vignette, grain, sharpen, soft, mono, clarity, vibrance;

  /// Split toning: rgb + strength.
  final List<double> shadowTone, highTone;

  /// Texture op (VHS, film dust, Polaroid border…) and its strength.
  final int op;
  final double opAmount;

  /// The editors' Adjust sliders (each -1..1, `filter_spec.adjust`).
  static FxGrade fromAdjust(Map<String, double> a) => FxGrade(
        exposure: a['exposure'] ?? 0,
        brightness: a['brightness'] ?? 0,
        contrast: a['contrast'] ?? 0,
        saturation: a['saturation'] ?? 0,
        warmth: a['warmth'] ?? 0,
        tint: a['tint'] ?? 0,
        highlights: a['highlights'] ?? 0,
        shadows: a['shadows'] ?? 0,
        fade: math.max(0.0, a['fade'] ?? 0.0),
        vignette: a['vignette'] ?? 0,
        grain: math.max(0.0, a['grain'] ?? 0.0),
        sharpen: a['sharpen'] ?? 0,
        clarity: a['clarity'] ?? 0,
        vibrance: a['vibrance'] ?? 0,
      );

  /// Uniform values 4..33 of story_grade.frag (after size, time, amount).
  List<double> uniforms(DateTime stamp) => [
        exposure, brightness, contrast, saturation,
        warmth, tint, highlights, shadows,
        fade, vignette, grain, sharpen,
        soft, mono, clarity, vibrance,
        ...shadowTone, ...highTone,
        op.toDouble(), opAmount,
        (stamp.year % 100).toDouble(), stamp.month.toDouble(), stamp.day.toDouble(),
        (stamp.hour * 60 + stamp.minute).toDouble(),
      ];
}

class StoryFxDef {
  const StoryFxDef(this.id, this.name, this.category,
      {this.kind = FxKind.shader, this.shader, this.index = 0, this.grade, this.motion, this.animated = false});

  final String id, name, category;
  final FxKind kind;

  /// Which shader draws it (null for AR / AI and video-only effects).
  final FxShader? shader;

  /// Effect number inside that shader.
  final int index;
  final FxGrade? grade;

  /// Video time effect rendered by the server (`edits.motion`).
  final String? motion;

  /// Moves over time, so the view keeps ticking.
  final bool animated;

  bool get comingSoon => kind == FxKind.ar || kind == FxKind.ai;
  bool get videoOnly => kind == FxKind.video && shader == null;
}

/// Picker tabs, in order: (category id, label).
const storyFxCategories = <(String, String)>[
  ('classic', 'Classic'),
  ('modern', 'Modern'),
  ('vintage', 'Vintage'),
  ('beauty', 'Beauty'),
  ('lens', 'Lens'),
  ('light', 'Light'),
  ('art', 'Art'),
  ('ar', 'AR'),
  ('animated', 'Animated'),
  ('motion', 'Motion'),
  ('ai', 'AI'),
];

const storyFxEffects = <StoryFxDef>[
  StoryFxDef('paris', 'Paris', 'classic', shader: FxShader.grade, grade: FxGrade(brightness: 0.03, contrast: -0.08, saturation: -0.05, highlights: -0.1, soft: 0.3, op: 19, opAmount: 0.5)),
  StoryFxDef('los_angeles', 'Los Angeles', 'classic', shader: FxShader.grade, grade: FxGrade(brightness: 0.05, contrast: 0.12, saturation: 0.15, warmth: 0.25, vignette: 0.15, highTone: [1, 0.8, 0.5, 0.25])),
  StoryFxDef('oslo', 'Oslo', 'classic', shader: FxShader.grade, grade: FxGrade(brightness: 0.08, contrast: -0.05, saturation: -0.25, warmth: -0.05, highlights: 0.1)),
  StoryFxDef('lagos', 'Lagos', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: 0.1, saturation: 0.3, warmth: 0.35, shadowTone: [0.5, 0.2, 0.1, 0.2])),
  StoryFxDef('melbourne', 'Melbourne', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: -0.1, saturation: -0.3, warmth: -0.05, shadows: 0.1, fade: 0.3, shadowTone: [0.2, 0.3, 0.35, 0.3])),
  StoryFxDef('jakarta', 'Jakarta', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: 0.3, saturation: 0.1, warmth: 0.25, shadows: -0.1)),
  StoryFxDef('abu_dhabi', 'Abu Dhabi', 'classic', shader: FxShader.grade, grade: FxGrade(brightness: 0.04, warmth: 0.15, soft: 0.2, highTone: [1, 0.85, 0.4, 0.5])),
  StoryFxDef('buenos_aires', 'Buenos Aires', 'classic', shader: FxShader.grade, grade: FxGrade(brightness: 0.12, contrast: -0.2, saturation: -0.1, fade: 0.2, shadowTone: [0.6, 0.7, 0.9, 0.2], highTone: [1, 0.85, 0.9, 0.3])),
  StoryFxDef('new_york', 'New York', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: -0.05, saturation: -0.35, warmth: -0.05, fade: 0.35, grain: 0.15, shadowTone: [0.3, 0.35, 0.4, 0.3])),
  StoryFxDef('jaipur', 'Jaipur', 'classic', shader: FxShader.grade, grade: FxGrade(saturation: 0.1, warmth: 0.2, tint: 0.25, highTone: [1, 0.6, 0.7, 0.4])),
  StoryFxDef('cairo', 'Cairo', 'classic', shader: FxShader.grade, grade: FxGrade(saturation: -0.2, warmth: 0.3, fade: 0.2, vignette: 0.2, grain: 0.2, shadowTone: [0.45, 0.3, 0.15, 0.4])),
  StoryFxDef('tokyo', 'Tokyo', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: 0.25, mono: 1, clarity: 0.2)),
  StoryFxDef('rio_de_janeiro', 'Rio de Janeiro', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: 0.1, saturation: 0.25, shadowTone: [0.1, 0.4, 0.6, 0.45], highTone: [1, 0.7, 0.3, 0.45])),
  StoryFxDef('seoul', 'Seoul', 'classic', shader: FxShader.grade, grade: FxGrade(brightness: 0.06, contrast: -0.1, saturation: -0.05, soft: 0.35, shadowTone: [0.6, 0.5, 0.8, 0.25], highTone: [0.9, 0.8, 1, 0.35])),
  StoryFxDef('lisbon', 'Lisbon', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: -0.1, saturation: -0.1, warmth: 0.2, fade: 0.3)),
  StoryFxDef('mexico_city', 'Mexico City', 'classic', shader: FxShader.grade, grade: FxGrade(contrast: 0.15, saturation: 0.15, warmth: 0.35, vignette: 0.2, shadowTone: [0.4, 0.15, 0.1, 0.3])),
  StoryFxDef('fade', 'Fade', 'modern', shader: FxShader.grade, grade: FxGrade(contrast: -0.2, fade: 0.5)),
  StoryFxDef('grainy', 'Grainy', 'modern', shader: FxShader.grade, grade: FxGrade(contrast: 0.05, grain: 0.8)),
  StoryFxDef('graphite', 'Graphite', 'modern', shader: FxShader.grade, grade: FxGrade(brightness: -0.12, contrast: 0.15, shadows: -0.1, grain: 0.2, mono: 1, clarity: 0.2)),
  StoryFxDef('gritty', 'Gritty', 'modern', shader: FxShader.grade, grade: FxGrade(contrast: 0.2, saturation: -0.2, grain: 0.35, op: 18)),
  StoryFxDef('handheld', 'Handheld', 'modern', shader: FxShader.grade, grade: FxGrade(op: 15), animated: true),
  StoryFxDef('hyper', 'Hyper', 'modern', shader: FxShader.grade, grade: FxGrade(contrast: 0.2, saturation: 0.55, clarity: 0.3, vibrance: 0.3)),
  StoryFxDef('lo_res', 'Lo-res', 'modern', shader: FxShader.grade, grade: FxGrade(op: 14)),
  StoryFxDef('midnight', 'Midnight', 'modern', shader: FxShader.grade, grade: FxGrade(exposure: -0.35, contrast: 0.15, saturation: -0.15, warmth: -0.35, vignette: 0.4, shadowTone: [0.1, 0.15, 0.4, 0.5])),
  StoryFxDef('simple', 'Simple', 'modern', shader: FxShader.grade, grade: FxGrade(contrast: 0.08, saturation: 0.08, sharpen: 0.2, clarity: 0.15, vibrance: 0.1)),
  StoryFxDef('soft_light', 'Soft Light', 'modern', shader: FxShader.grade, grade: FxGrade(brightness: 0.05, contrast: -0.1, soft: 0.55)),
  StoryFxDef('zoom_blur', 'Zoom Blur', 'modern', shader: FxShader.lens, index: 23),
  StoryFxDef('wavy', 'Wavy', 'modern', shader: FxShader.lens, index: 24, animated: true),
  StoryFxDef('moire', 'Moiré', 'modern', shader: FxShader.lens, index: 25, animated: true),
  StoryFxDef('wide_angle', 'Wide Angle', 'modern', shader: FxShader.lens, index: 2),
  StoryFxDef('vhs', 'VHS', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.05, saturation: 0.1, warmth: 0.05, grain: 0.15, highTone: [0.9, 0.7, 1, 0.15], op: 1), animated: true),
  StoryFxDef('vcr', 'VCR', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.05, saturation: -0.1, grain: 0.2, op: 2), animated: true),
  StoryFxDef('film_8mm', '8mm Film', 'vintage', shader: FxShader.grade, grade: FxGrade(saturation: -0.2, warmth: 0.25, fade: 0.2, vignette: 0.35, grain: 0.55, op: 3), animated: true),
  StoryFxDef('film_16mm', '16mm Film', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.05, saturation: -0.08, warmth: 0.12, fade: 0.12, grain: 0.35, op: 4), animated: true),
  StoryFxDef('film_35mm', '35mm Film', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.06, warmth: 0.06, grain: 0.18, op: 5, opAmount: 0.6)),
  StoryFxDef('super_8', 'Super 8', 'vintage', shader: FxShader.grade, grade: FxGrade(saturation: 0.1, warmth: 0.35, fade: 0.2, vignette: 0.3, grain: 0.45, highTone: [1, 0.75, 0.45, 0.3], op: 6), animated: true),
  StoryFxDef('retro_camcorder', 'Retro Camcorder', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: -0.05, saturation: -0.05, grain: 0.1, sharpen: 0.3, op: 7), animated: true),
  StoryFxDef('polaroid', 'Polaroid', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: -0.05, saturation: -0.1, warmth: 0.12, fade: 0.25, shadowTone: [0.3, 0.4, 0.45, 0.3], highTone: [1, 0.95, 0.8, 0.2], op: 8)),
  StoryFxDef('disposable', 'Disposable Camera', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.25, saturation: 0.15, warmth: 0.1, grain: 0.45, op: 9)),
  StoryFxDef('film_burn', 'Film Burn', 'vintage', shader: FxShader.grade, grade: FxGrade(warmth: 0.15, fade: 0.1, grain: 0.2, op: 10), animated: true),
  StoryFxDef('light_leak', 'Light Leak', 'vintage', shader: FxShader.grade, grade: FxGrade(warmth: 0.1, op: 11), animated: true),
  StoryFxDef('dust_scratches', 'Dust and Scratches', 'vintage', shader: FxShader.grade, grade: FxGrade(fade: 0.1, grain: 0.2, op: 12)),
  StoryFxDef('sepia', 'Sepia', 'vintage', shader: FxShader.grade, grade: FxGrade(fade: 0.1, mono: 0.9, shadowTone: [0.4, 0.25, 0.1, 0.6], highTone: [1, 0.85, 0.6, 0.6])),
  StoryFxDef('vintage_70s', 'Vintage 70s', 'vintage', shader: FxShader.grade, grade: FxGrade(saturation: -0.15, warmth: 0.35, fade: 0.35, grain: 0.2, highTone: [1, 0.8, 0.45, 0.35])),
  StoryFxDef('vintage_80s', 'Vintage 80s', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.2, saturation: 0.35, tint: 0.1, shadowTone: [0.2, 0.2, 0.6, 0.35], highTone: [1, 0.6, 0.9, 0.2])),
  StoryFxDef('vintage_90s', 'Vintage 90s', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: -0.05, saturation: -0.1, warmth: 0.1, fade: 0.25, op: 1, opAmount: 0.4), animated: true),
  StoryFxDef('y2k', 'Y2K', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.1, warmth: -0.15, tint: -0.05, sharpen: 0.4, highTone: [0.8, 0.9, 1, 0.3], op: 16)),
  StoryFxDef('crt', 'CRT', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.1, saturation: 0.1, op: 13)),
  StoryFxDef('bw_film', 'B&W Film', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.2, grain: 0.45, mono: 1, op: 3, opAmount: 0.35), animated: true),
  StoryFxDef('retro_flash', 'Retro Flash', 'vintage', shader: FxShader.grade, grade: FxGrade(contrast: 0.25, warmth: 0.05, grain: 0.2, op: 17)),
  StoryFxDef('soft_skin', 'Soft Skin', 'beauty', shader: FxShader.grade, grade: FxGrade(soft: 0.15, op: 19)),
  StoryFxDef('beauty_glow', 'Beauty Glow', 'beauty', shader: FxShader.grade, grade: FxGrade(brightness: 0.04, warmth: 0.05, op: 21)),
  StoryFxDef('subtle', 'Subtle', 'beauty', shader: FxShader.grade, grade: FxGrade(brightness: 0.03, soft: 0.1, vibrance: 0.1, op: 19, opAmount: 0.4)),
  StoryFxDef('golden_hour', 'Golden Hour', 'beauty', shader: FxShader.grade, grade: FxGrade(contrast: 0.05, saturation: 0.15, warmth: 0.4, soft: 0.2, highTone: [1, 0.75, 0.35, 0.5])),
  StoryFxDef('glass_skin', 'Glass Skin', 'beauty', shader: FxShader.grade, grade: FxGrade(brightness: 0.04, soft: 0.15, op: 20)),
  StoryFxDef('sun_kissed', 'Sun Kissed', 'beauty', shader: FxShader.grade, grade: FxGrade(brightness: 0.03, saturation: 0.1, warmth: 0.3, tint: 0.08)),
  StoryFxDef('rosy_glow', 'Rosy Glow', 'beauty', shader: FxShader.grade, grade: FxGrade(tint: 0.2, soft: 0.15, highTone: [1, 0.65, 0.75, 0.35])),
  StoryFxDef('natural_makeup', 'Natural Makeup', 'beauty', kind: FxKind.ar),
  StoryFxDef('glam_makeup', 'Glam Makeup', 'beauty', kind: FxKind.ar),
  StoryFxDef('blush', 'Blush', 'beauty', kind: FxKind.ar),
  StoryFxDef('lip_tint', 'Lip Tint', 'beauty', kind: FxKind.ar),
  StoryFxDef('freckles', 'Freckles', 'beauty', kind: FxKind.ar),
  StoryFxDef('glitter_freckles', 'Glitter Freckles', 'beauty', kind: FxKind.ar),
  StoryFxDef('eye_color', 'Eye Color', 'beauty', kind: FxKind.ar),
  StoryFxDef('eyelashes', 'Eyelashes', 'beauty', kind: FxKind.ar),
  StoryFxDef('eyeliner', 'Eyeliner', 'beauty', kind: FxKind.ar),
  StoryFxDef('face_sculpt', 'Face Sculpt', 'beauty', kind: FxKind.ar),
  StoryFxDef('hair_color', 'Hair Color', 'beauty', kind: FxKind.ar),
  StoryFxDef('hair_glitter', 'Hair Glitter', 'beauty', kind: FxKind.ar),
  StoryFxDef('face_paint', 'Face Paint', 'beauty', kind: FxKind.ar),
  StoryFxDef('fisheye', 'Fisheye', 'lens', shader: FxShader.lens, index: 1),
  StoryFxDef('wide_angle', 'Wide Angle', 'lens', shader: FxShader.lens, index: 2),
  StoryFxDef('barrel', 'Barrel Distortion', 'lens', shader: FxShader.lens, index: 3),
  StoryFxDef('pincushion', 'Pincushion', 'lens', shader: FxShader.lens, index: 4),
  StoryFxDef('kaleidoscope', 'Kaleidoscope', 'lens', shader: FxShader.lens, index: 5, animated: true),
  StoryFxDef('mirror', 'Mirror', 'lens', shader: FxShader.lens, index: 6),
  StoryFxDef('infinity_mirror', 'Infinity Mirror', 'lens', shader: FxShader.lens, index: 7),
  StoryFxDef('infinite_zoom', 'Infinite Zoom', 'lens', shader: FxShader.lens, index: 8, animated: true),
  StoryFxDef('tunnel', 'Tunnel', 'lens', shader: FxShader.lens, index: 9, animated: true),
  StoryFxDef('wave', 'Wave', 'lens', shader: FxShader.lens, index: 10, animated: true),
  StoryFxDef('ripple', 'Ripple', 'lens', shader: FxShader.lens, index: 11, animated: true),
  StoryFxDef('swirl', 'Swirl', 'lens', shader: FxShader.lens, index: 12, animated: true),
  StoryFxDef('bulge', 'Bulge', 'lens', shader: FxShader.lens, index: 13),
  StoryFxDef('pinch', 'Pinch', 'lens', shader: FxShader.lens, index: 14),
  StoryFxDef('face_melt', 'Face Melt', 'lens', shader: FxShader.lens, index: 15, animated: true),
  StoryFxDef('glass_distortion', 'Glass Distortion', 'lens', shader: FxShader.lens, index: 16),
  StoryFxDef('rgb_split', 'RGB Split', 'lens', shader: FxShader.lens, index: 17),
  StoryFxDef('chromatic_pulse', 'Chromatic Pulse', 'lens', shader: FxShader.lens, index: 18, animated: true),
  StoryFxDef('pixel_sort', 'Pixel Sort', 'lens', shader: FxShader.lens, index: 19),
  StoryFxDef('glitch', 'Glitch', 'lens', shader: FxShader.lens, index: 20, animated: true),
  StoryFxDef('liquid', 'Liquid', 'lens', shader: FxShader.lens, index: 21, animated: true),
  StoryFxDef('prism', 'Prism', 'lens', shader: FxShader.lens, index: 22),
  StoryFxDef('bloom', 'Bloom', 'light', shader: FxShader.light, index: 1),
  StoryFxDef('sparkle', 'Sparkle', 'light', shader: FxShader.light, index: 2, animated: true),
  StoryFxDef('glitter', 'Glitter', 'light', shader: FxShader.light, index: 3, animated: true),
  StoryFxDef('golden_glitter', 'Golden Glitter', 'light', shader: FxShader.light, index: 4, animated: true),
  StoryFxDef('purple_glitter', 'Purple Glitter', 'light', shader: FxShader.light, index: 5, animated: true),
  StoryFxDef('iridescent_glitter', 'Iridescent Glitter', 'light', shader: FxShader.light, index: 6, animated: true),
  StoryFxDef('starburst', 'Starburst', 'light', shader: FxShader.light, index: 7),
  StoryFxDef('led_starburst', 'LED Starburst', 'light', shader: FxShader.light, index: 8, animated: true),
  StoryFxDef('rayburst', 'Rayburst', 'light', shader: FxShader.light, index: 9, animated: true),
  StoryFxDef('prism_light', 'Prism Light', 'light', shader: FxShader.light, index: 10, animated: true),
  StoryFxDef('light_streak', 'Light Streak', 'light', shader: FxShader.light, index: 11),
  StoryFxDef('lens_flare', 'Lens Flare', 'light', shader: FxShader.light, index: 12, animated: true),
  StoryFxDef('bokeh', 'Bokeh', 'light', shader: FxShader.light, index: 13, animated: true),
  StoryFxDef('neon_glow', 'Neon Glow', 'light', shader: FxShader.light, index: 14, animated: true),
  StoryFxDef('neon_frame', 'Neon Frame', 'light', shader: FxShader.light, index: 15, animated: true),
  StoryFxDef('rgb_lighting', 'RGB Lighting', 'light', shader: FxShader.light, index: 16, animated: true),
  StoryFxDef('spotlight', 'Spotlight', 'light', shader: FxShader.light, index: 17),
  StoryFxDef('god_rays', 'God Rays', 'light', shader: FxShader.light, index: 18, animated: true),
  StoryFxDef('palm_shade', 'Palm Shade', 'light', shader: FxShader.light, index: 19, animated: true),
  StoryFxDef('cyberpunk', 'Cyberpunk', 'light', shader: FxShader.light, index: 20),
  StoryFxDef('aura', 'Aura', 'light', shader: FxShader.light, index: 21, animated: true),
  StoryFxDef('holographic', 'Holographic', 'light', shader: FxShader.light, index: 22, animated: true),
  StoryFxDef('comic_book', 'Comic Book', 'art', shader: FxShader.art, index: 1),
  StoryFxDef('cartoon', 'Cartoon', 'art', shader: FxShader.art, index: 2),
  StoryFxDef('anime', 'Anime', 'art', shader: FxShader.art, index: 3),
  StoryFxDef('watercolor', 'Watercolor', 'art', shader: FxShader.art, index: 4),
  StoryFxDef('oil_painting', 'Oil Painting', 'art', shader: FxShader.art, index: 5),
  StoryFxDef('pencil_sketch', 'Pencil Sketch', 'art', shader: FxShader.art, index: 6),
  StoryFxDef('charcoal', 'Charcoal', 'art', shader: FxShader.art, index: 7),
  StoryFxDef('noir', 'Noir', 'art', shader: FxShader.art, index: 8),
  StoryFxDef('outline', 'Outline', 'art', shader: FxShader.art, index: 9),
  StoryFxDef('halftone', 'Halftone', 'art', shader: FxShader.art, index: 10),
  StoryFxDef('pop_art', 'Pop Art', 'art', shader: FxShader.art, index: 11),
  StoryFxDef('duotone', 'Duotone', 'art', shader: FxShader.art, index: 12),
  StoryFxDef('tritone', 'Tritone', 'art', shader: FxShader.art, index: 13),
  StoryFxDef('posterize', 'Posterize', 'art', shader: FxShader.art, index: 14),
  StoryFxDef('bit8', '8-bit', 'art', shader: FxShader.art, index: 15),
  StoryFxDef('bit16', '16-bit', 'art', shader: FxShader.art, index: 16),
  StoryFxDef('mosaic', 'Mosaic', 'art', shader: FxShader.art, index: 17),
  StoryFxDef('ascii', 'ASCII Art', 'art', shader: FxShader.art, index: 18),
  StoryFxDef('negative', 'Negative', 'art', shader: FxShader.art, index: 19),
  StoryFxDef('thermal', 'Thermal Vision', 'art', shader: FxShader.art, index: 20),
  StoryFxDef('emboss', 'Emboss', 'art', shader: FxShader.art, index: 21),
  StoryFxDef('blueprint', 'Blueprint', 'art', shader: FxShader.art, index: 22),
  StoryFxDef('dithering', 'Dithering', 'art', shader: FxShader.art, index: 23),
  StoryFxDef('low_poly', 'Low Poly', 'art', shader: FxShader.art, index: 24),
  StoryFxDef('crosshatch', 'Crosshatch', 'art', shader: FxShader.art, index: 25),
  StoryFxDef('puppy', 'Puppy', 'ar', kind: FxKind.ar),
  StoryFxDef('kitten', 'Kitten', 'ar', kind: FxKind.ar),
  StoryFxDef('bunny', 'Bunny', 'ar', kind: FxKind.ar),
  StoryFxDef('bulldog', 'Bulldog', 'ar', kind: FxKind.ar),
  StoryFxDef('fox', 'Fox', 'ar', kind: FxKind.ar),
  StoryFxDef('bear', 'Bear', 'ar', kind: FxKind.ar),
  StoryFxDef('sunglasses', 'Sunglasses', 'ar', kind: FxKind.ar),
  StoryFxDef('crown', 'Crown', 'ar', kind: FxKind.ar),
  StoryFxDef('flower_crown', 'Flower Crown', 'ar', kind: FxKind.ar),
  StoryFxDef('angel_halo', 'Angel Halo', 'ar', kind: FxKind.ar),
  StoryFxDef('devil_horns', 'Devil Horns', 'ar', kind: FxKind.ar),
  StoryFxDef('heart_eyes', 'Heart Eyes', 'ar', kind: FxKind.ar),
  StoryFxDef('mouth_face', 'Mouth Face', 'ar', kind: FxKind.ar),
  StoryFxDef('big_eyes', 'Big Eyes', 'ar', kind: FxKind.ar),
  StoryFxDef('big_mouth', 'Big Mouth', 'ar', kind: FxKind.ar),
  StoryFxDef('alien', 'Alien', 'ar', kind: FxKind.ar),
  StoryFxDef('robot', 'Robot', 'ar', kind: FxKind.ar),
  StoryFxDef('clown', 'Clown', 'ar', kind: FxKind.ar),
  StoryFxDef('skull', 'Skull', 'ar', kind: FxKind.ar),
  StoryFxDef('zombie', 'Zombie', 'ar', kind: FxKind.ar),
  StoryFxDef('vampire', 'Vampire', 'ar', kind: FxKind.ar),
  StoryFxDef('face_swap', 'Face Swap', 'ar', kind: FxKind.ar),
  StoryFxDef('face_clone', 'Face Clone', 'ar', kind: FxKind.ar),
  StoryFxDef('helmet_3d', '3D Helmet', 'ar', kind: FxKind.ar),
  StoryFxDef('heart_bloom', 'Heart Bloom', 'animated', shader: FxShader.scene, index: 1, animated: true),
  StoryFxDef('heart_cannon', 'Heart Cannon', 'animated', shader: FxShader.scene, index: 2, animated: true),
  StoryFxDef('heart_windows', 'Heart Windows', 'animated', shader: FxShader.scene, index: 3, animated: true),
  StoryFxDef('heart_frame', 'Heart Frame', 'animated', shader: FxShader.scene, index: 4, animated: true),
  StoryFxDef('neon_valentine', 'Neon Valentine', 'animated', shader: FxShader.scene, index: 5, animated: true),
  StoryFxDef('love_letter', 'Love Letter', 'animated', shader: FxShader.scene, index: 6, animated: true),
  StoryFxDef('spring_bloom', 'Spring Bloom', 'animated', shader: FxShader.scene, index: 7, animated: true),
  StoryFxDef('winter_sparkle', 'Winter Sparkle', 'animated', shader: FxShader.scene, index: 8, animated: true),
  StoryFxDef('starfield', 'Starfield', 'animated', shader: FxShader.scene, index: 9, animated: true),
  StoryFxDef('snow', 'Snow', 'animated', shader: FxShader.scene, index: 10, animated: true),
  StoryFxDef('rain', 'Rain', 'animated', shader: FxShader.scene, index: 11, animated: true),
  StoryFxDef('thunderstorm', 'Thunderstorm', 'animated', shader: FxShader.scene, index: 12, animated: true),
  StoryFxDef('fire', 'Fire', 'animated', shader: FxShader.scene, index: 13, animated: true),
  StoryFxDef('smoke', 'Smoke', 'animated', shader: FxShader.scene, index: 14, animated: true),
  StoryFxDef('fog', 'Fog', 'animated', shader: FxShader.scene, index: 15, animated: true),
  StoryFxDef('confetti', 'Confetti', 'animated', shader: FxShader.scene, index: 16, animated: true),
  StoryFxDef('bubbles', 'Bubbles', 'animated', shader: FxShader.scene, index: 17, animated: true),
  StoryFxDef('butterflies', 'Butterflies', 'animated', shader: FxShader.scene, index: 18, animated: true),
  StoryFxDef('fireflies', 'Fireflies', 'animated', shader: FxShader.scene, index: 19, animated: true),
  StoryFxDef('cherry_blossom', 'Cherry Blossom', 'animated', shader: FxShader.scene, index: 20, animated: true),
  StoryFxDef('galaxy', 'Galaxy', 'animated', shader: FxShader.scene, index: 21, animated: true),
  StoryFxDef('lightning', 'Lightning', 'animated', shader: FxShader.scene, index: 22, animated: true),
  StoryFxDef('magic_dust', 'Magic Dust', 'animated', shader: FxShader.scene, index: 23, animated: true),
  StoryFxDef('water_droplets', 'Water Droplets', 'animated', shader: FxShader.scene, index: 24, animated: true),
  StoryFxDef('boomerang', 'Boomerang', 'motion', kind: FxKind.video, motion: 'boomerang'),
  StoryFxDef('superzoom', 'Superzoom', 'motion', shader: FxShader.lens, index: 30, animated: true),
  StoryFxDef('slow_motion', 'Slow Motion', 'motion', kind: FxKind.video, motion: 'slow_motion'),
  StoryFxDef('hyperlapse', 'Hyperlapse', 'motion', kind: FxKind.video, motion: 'hyperlapse'),
  StoryFxDef('motion_blur', 'Motion Blur', 'motion', shader: FxShader.lens, index: 27),
  StoryFxDef('ghost_trail', 'Ghost Trail', 'motion', kind: FxKind.video, shader: FxShader.lens, index: 37, motion: 'ghost_trail', animated: true),
  StoryFxDef('motion_echo', 'Motion Echo', 'motion', kind: FxKind.video, shader: FxShader.lens, index: 36, motion: 'motion_echo'),
  StoryFxDef('freeze_frame', 'Freeze Frame', 'motion', kind: FxKind.video, motion: 'freeze_frame'),
  StoryFxDef('camera_shake', 'Camera Shake', 'motion', shader: FxShader.lens, index: 28, animated: true),
  StoryFxDef('strobe', 'Strobe', 'motion', shader: FxShader.lens, index: 29, animated: true),
  StoryFxDef('stop_motion', 'Stop Motion', 'motion', kind: FxKind.video, motion: 'stop_motion'),
  StoryFxDef('dolly_zoom', 'Dolly Zoom', 'motion', shader: FxShader.lens, index: 31, animated: true),
  StoryFxDef('split_screen', 'Split Screen', 'motion', shader: FxShader.lens, index: 32),
  StoryFxDef('contact_sheet', 'Contact Sheet', 'motion', shader: FxShader.lens, index: 33),
  StoryFxDef('five_frame', 'Five Frame Contact Sheet', 'motion', shader: FxShader.lens, index: 34),
  StoryFxDef('shuffle', 'Shuffle', 'motion', shader: FxShader.lens, index: 35, animated: true),
  StoryFxDef('clone_trail', 'Clone Trail', 'motion', shader: FxShader.lens, index: 36),
  StoryFxDef('cinematic_blur', 'Cinematic Blur', 'motion', shader: FxShader.lens, index: 38),
  StoryFxDef('tilt_shift', 'Tilt Shift', 'motion', shader: FxShader.lens, index: 39),
  StoryFxDef('green_screen', 'Green Screen', 'ai', kind: FxKind.ai),
  StoryFxDef('background_blur', 'Background Blur', 'ai', kind: FxKind.ai),
  StoryFxDef('background_removal', 'Background Removal', 'ai', kind: FxKind.ai),
  StoryFxDef('virtual_background', 'Virtual Background', 'ai', kind: FxKind.ai),
  StoryFxDef('color_splash', 'Color Splash', 'ai', kind: FxKind.ai),
  StoryFxDef('sky_replacement', 'Sky Replacement', 'ai', kind: FxKind.ai),
  StoryFxDef('background_desaturation', 'Background Desaturation', 'ai', kind: FxKind.ai),
  StoryFxDef('subject_glow', 'Subject Glow', 'ai', kind: FxKind.ai),
  StoryFxDef('subject_outline', 'Subject Outline', 'ai', kind: FxKind.ai),
  StoryFxDef('silhouette', 'Silhouette', 'ai', kind: FxKind.ai),
  StoryFxDef('ai_restyle', 'AI Restyle', 'ai', kind: FxKind.ai),
  StoryFxDef('ai_avatar', 'AI Avatar', 'ai', kind: FxKind.ai),
  StoryFxDef('ai_relighting', 'AI Relighting', 'ai', kind: FxKind.ai),
  StoryFxDef('ai_object_removal', 'AI Object Removal', 'ai', kind: FxKind.ai),
  StoryFxDef('ai_background', 'AI Background Generation', 'ai', kind: FxKind.ai),
];

final Map<String, StoryFxDef> storyFxById = () {
  final map = <String, StoryFxDef>{};
  for (final e in storyFxEffects) {
    map.putIfAbsent(e.id, () => e);
  }
  return map;
}();

/// Effects you can use today (everything but AR / AI).
int get storyFxLiveCount => {for (final e in storyFxEffects) if (!e.comingSoon) e.id}.length;
