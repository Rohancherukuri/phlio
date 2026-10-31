// Moment templates — the data model.
//
// A template is a 360 × 640 design (9:16, the moment canvas) made of
// elements, drawn over a backdrop:
//
//   * slots   photo frames (rectangle, rounded, circle, arch, polaroid) the
//             user fills from the gallery; each can carry a Phlio Look.
//   * text    editable text with font, size, weight, colour, case, spacing
//             and a background style. Roles: plain text, @mention, #tag,
//             location and link, so tags and mentions also go into the
//             moment's caption.
//   * decos   fixed shapes that give a template its layout (bars, lines,
//             circles, washi tape, film sprockets, rating bars, REC dot).
//
// Everything is mutable so the editor can change it in place; a template's
// [MomentTemplate.build] returns fresh copies every time it's opened.

import 'package:flutter/painting.dart';

/// Design size every template is laid out in. The canvas scales it to fit
/// the screen and exports at 3× (1080 × 1920).
const templateSize = Size(360, 640);

enum SlotShape { rect, rounded, circle, arch, polaroid }

/// How a text element is backed: Instagram-style highlight, pill, outline…
enum TextBg { none, pill, highlight, outline, neon, block, gradient, sticker }

/// What a text element means, beyond how it looks.
enum TextRole { text, mention, tag, location, link }

enum DecoKind { rect, line, circle, tape, sprockets, rating, recDot }

enum ElementKind { slot, text, deco }

/// One element of a template. Fields not used by an element's [kind] are
/// ignored (a slot has no text, a deco no photo…).
class TElement {
  TElement._(this.kind, this.center, this.size, this.rotation);

  /// A photo frame centred at [center], [size] in design units.
  factory TElement.slot(Offset center, Size size,
      {SlotShape shape = SlotShape.rect,
      double radius = 0,
      double rotation = 0,
      Color border = const Color(0x00000000),
      double borderWidth = 0,
      String look = 'normal',
      String hint = 'Add photo',
      bool shadow = false}) {
    return TElement._(ElementKind.slot, center, size, rotation)
      ..shape = shape
      ..radius = radius
      ..border = border
      ..borderWidth = borderWidth
      ..look = look
      ..hint = hint
      ..shadow = shadow;
  }

  /// Editable text centred at [center], wrapping within [width].
  factory TElement.text(String text, Offset center,
      {double width = 300,
      String font = 'Manrope',
      double fontSize = 24,
      Color color = const Color(0xFFFFFFFF),
      FontWeight weight = FontWeight.w700,
      bool italic = false,
      bool upper = false,
      double spacing = 0,
      double lineHeight = 1.15,
      TextAlign align = TextAlign.center,
      TextBg bg = TextBg.none,
      Color bgColor = const Color(0xFF000000),
      TextRole role = TextRole.text,
      double rotation = 0}) {
    return TElement._(ElementKind.text, center, Size(width, 0), rotation)
      ..text = text
      ..font = font
      ..fontSize = fontSize
      ..color = color
      ..weight = weight
      ..italic = italic
      ..upper = upper
      ..spacing = spacing
      ..lineHeight = lineHeight
      ..align = align
      ..bg = bg
      ..bgColor = bgColor
      ..role = role;
  }

  /// A fixed decoration.
  factory TElement.deco(DecoKind deco, Offset center, Size size,
      {Color color = const Color(0xFFFFFFFF),
      Color color2 = const Color(0x00000000),
      double radius = 0,
      double rotation = 0,
      double value = 0}) {
    return TElement._(ElementKind.deco, center, size, rotation)
      ..deco = deco
      ..color = color
      ..color2 = color2
      ..radius = radius
      ..value = value;
  }

  final ElementKind kind;

  /// Centre in design units (360 × 640 space).
  Offset center;

  /// Size in design units; for text, `width` is the wrap width.
  Size size;

  /// Clockwise rotation in radians.
  double rotation;

  // -- slot -----------------------------------------------------------------------
  SlotShape shape = SlotShape.rect;
  double radius = 0;
  Color border = const Color(0x00000000);
  double borderWidth = 0;

  /// Phlio Look applied to the photo (shared/media/phlio_look_data.dart).
  String look = 'normal';
  String hint = 'Add photo';
  bool shadow = false;

  /// Picked photo (file path), and how it's panned / zoomed inside the frame.
  String? photo;
  Offset photoOffset = Offset.zero;
  double photoScale = 1;

  // -- text -----------------------------------------------------------------------
  String text = '';
  String font = 'Manrope';
  double fontSize = 24;
  FontWeight weight = FontWeight.w700;
  bool italic = false;
  bool upper = false;
  double spacing = 0;
  double lineHeight = 1.15;
  TextAlign align = TextAlign.center;
  TextBg bg = TextBg.none;
  Color bgColor = const Color(0xFF000000);
  TextRole role = TextRole.text;

  // -- deco (and text colour) ----------------------------------------------------
  DecoKind deco = DecoKind.rect;
  Color color = const Color(0xFFFFFFFF);
  Color color2 = const Color(0x00000000);

  /// Deco-specific value (rating bar fill 0–1).
  double value = 0;

  /// The text as drawn (upper-cased when [upper]).
  String get display => upper ? text.toUpperCase() : text;

  bool get isSlot => kind == ElementKind.slot;
  bool get isText => kind == ElementKind.text;
  bool get isDeco => kind == ElementKind.deco;

  /// A deep copy (duplicate in the editor).
  TElement copy() {
    final e = TElement._(kind, center, size, rotation)
      ..shape = shape
      ..radius = radius
      ..border = border
      ..borderWidth = borderWidth
      ..look = look
      ..hint = hint
      ..shadow = shadow
      ..photo = photo
      ..photoOffset = photoOffset
      ..photoScale = photoScale
      ..text = text
      ..font = font
      ..fontSize = fontSize
      ..weight = weight
      ..italic = italic
      ..upper = upper
      ..spacing = spacing
      ..lineHeight = lineHeight
      ..align = align
      ..bg = bg
      ..bgColor = bgColor
      ..role = role
      ..deco = deco
      ..color = color
      ..color2 = color2
      ..value = value;
    return e;
  }
}

/// Shader backdrop styles (assets/shaders/moment_backdrop.frag).
enum BackdropStyle { mesh, aurora, paper, halftone, grid, sunburst, holo, film, linear, checker }

const backdropNames = {
  BackdropStyle.mesh: 'Mesh',
  BackdropStyle.aurora: 'Aurora',
  BackdropStyle.paper: 'Paper',
  BackdropStyle.halftone: 'Halftone',
  BackdropStyle.grid: 'Y2K grid',
  BackdropStyle.sunburst: 'Sunburst',
  BackdropStyle.holo: 'Holo',
  BackdropStyle.film: 'Light leak',
  BackdropStyle.linear: 'Gradient',
  BackdropStyle.checker: 'Checker',
};

/// The template's background: a shader style and four colours.
class TBackdrop {
  TBackdrop(this.style, this.colors, {this.grain = .25, this.animate = true});

  BackdropStyle style;

  /// Exactly four colours (A, B, C, D in the shader).
  List<Color> colors;
  double grain;

  /// Moves in the editor (exports are a still frame).
  bool animate;

  TBackdrop copy() => TBackdrop(style, [...colors], grain: grain, animate: animate);
}

/// Colour sets offered by the Background sheet (Phlio palette first).
const backdropPalettes = <List<Color>>[
  [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F), Color(0xFF111925)],
  [Color(0xFF72A7FF), Color(0xFF8D78FF), Color(0xFF68D7CD), Color(0xFF080E16)],
  [Color(0xFFF6EFE6), Color(0xFFE9DCCB), Color(0xFF2B2A28), Color(0xFF1A1918)],
  [Color(0xFFFFD86E), Color(0xFFFF7A59), Color(0xFFFFF4D6), Color(0xFF2B1B3F)],
  [Color(0xFF0E0E10), Color(0xFF26262B), Color(0xFFE8E8EA), Color(0xFF000000)],
  [Color(0xFFB8F2E6), Color(0xFFAED9E0), Color(0xFF5E6472), Color(0xFF14213D)],
  [Color(0xFFFF5DA2), Color(0xFF7B2FF7), Color(0xFF00E5FF), Color(0xFF0B0425)],
  [Color(0xFF9BC53D), Color(0xFFFDE74C), Color(0xFFFFFFFF), Color(0xFF1B3A2F)],
];

enum TemplateCategory { portrait, collage, creator, trending, quotes }

const templateCategoryNames = {
  TemplateCategory.portrait: 'Portraits',
  TemplateCategory.collage: 'Collages',
  TemplateCategory.creator: 'Creator',
  TemplateCategory.trending: 'Trending',
  TemplateCategory.quotes: 'Quotes & advice',
};

/// A ready-made design. [build] returns fresh, editable elements.
class MomentTemplate {
  const MomentTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.backdrop,
    required this.build,
    this.trend,
  });

  final String id, name;
  final TemplateCategory category;
  final TBackdrop Function() backdrop;
  final List<TElement> Function() build;

  /// Short note on the trend it follows (shown in the gallery).
  final String? trend;

  /// How many photos it takes.
  int get slots => build().where((e) => e.isSlot).length;
}

/// Fonts offered in the text editor. Manrope and Quicksand are bundled;
/// the rest come from Google Fonts (fetched once, then cached).
const templateFonts = [
  'Manrope',
  'Quicksand',
  'Playfair Display',
  'DM Serif Display',
  'Cormorant Garamond',
  'Bebas Neue',
  'Anton',
  'Archivo Black',
  'Space Grotesk',
  'Inter',
  'Courier Prime',
  'Caveat',
  'Pacifico',
  'Permanent Marker',
  'Righteous',
  'Monoton',
];

/// Text colours offered in the editor (Phlio palette + neutrals).
const templateTextColors = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFF111925),
  Color(0xFFF6EFE6),
  Color(0xFF8D78FF),
  Color(0xFFE795D7),
  Color(0xFFFFB58F),
  Color(0xFF72A7FF),
  Color(0xFF68D7CD),
  Color(0xFFF6D365),
  Color(0xFFF5636B),
  Color(0xFF2BC25B),
];

// -- saving -----------------------------------------------------------------------------

Map<String, dynamic> _offset(Offset o) => {'x': o.dx, 'y': o.dy};
Offset _toOffset(Object? j) => j is Map ? Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()) : Offset.zero;
T _named<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;

extension TElementJson on TElement {
  /// Everything needed to rebuild the element ([withPhoto]: keep the photo path).
  Map<String, dynamic> toJson({bool withPhoto = false}) => {
        'kind': kind.name,
        'center': _offset(center),
        'w': size.width,
        'h': size.height,
        'rotation': rotation,
        'shape': shape.name,
        'radius': radius,
        'border': border.toARGB32(),
        'borderWidth': borderWidth,
        'look': look,
        'hint': hint,
        'shadow': shadow,
        if (withPhoto && photo != null) 'photo': photo,
        'text': text,
        'font': font,
        'fontSize': fontSize,
        'weight': weight.index,
        'italic': italic,
        'upper': upper,
        'spacing': spacing,
        'lineHeight': lineHeight,
        'align': align.name,
        'bg': bg.name,
        'bgColor': bgColor.toARGB32(),
        'role': role.name,
        'deco': deco.name,
        'color': color.toARGB32(),
        'color2': color2.toARGB32(),
        'value': value,
      };
}

/// Rebuilds an element saved with [TElementJson.toJson].
TElement elementFromJson(Map j) {
  double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
  Color c(String k, int f) => Color((j[k] as num?)?.toInt() ?? f);
  final center = _toOffset(j['center']);
  final size = Size(d('w', 100), d('h', 0));
  final kind = _named(ElementKind.values, j['kind'], ElementKind.text);
  final e = switch (kind) {
    ElementKind.slot => TElement.slot(center, size),
    ElementKind.deco => TElement.deco(DecoKind.rect, center, size),
    ElementKind.text => TElement.text('${j['text'] ?? ''}', center, width: size.width),
  };
  return e
    ..rotation = d('rotation', 0)
    ..shape = _named(SlotShape.values, j['shape'], SlotShape.rect)
    ..radius = d('radius', 0)
    ..border = c('border', 0)
    ..borderWidth = d('borderWidth', 0)
    ..look = '${j['look'] ?? 'normal'}'
    ..hint = '${j['hint'] ?? 'Add photo'}'
    ..shadow = j['shadow'] == true
    ..photo = j['photo'] as String?
    ..text = '${j['text'] ?? ''}'
    ..font = '${j['font'] ?? 'Manrope'}'
    ..fontSize = d('fontSize', 24)
    ..weight = FontWeight.values[((j['weight'] as num?)?.toInt() ?? 6).clamp(0, 8)]
    ..italic = j['italic'] == true
    ..upper = j['upper'] == true
    ..spacing = d('spacing', 0)
    ..lineHeight = d('lineHeight', 1.15)
    ..align = _named(TextAlign.values, j['align'], TextAlign.center)
    ..bg = _named(TextBg.values, j['bg'], TextBg.none)
    ..bgColor = c('bgColor', 0xFF000000)
    ..role = _named(TextRole.values, j['role'], TextRole.text)
    ..deco = _named(DecoKind.values, j['deco'], DecoKind.rect)
    ..color = c('color', 0xFFFFFFFF)
    ..color2 = c('color2', 0)
    ..value = d('value', 0);
}

extension TBackdropJson on TBackdrop {
  Map<String, dynamic> toJson() =>
      {'style': style.name, 'colors': [for (final c in colors) c.toARGB32()], 'grain': grain, 'animate': animate};
}

TBackdrop backdropFromJson(Map j) => TBackdrop(
      _named(BackdropStyle.values, j['style'], BackdropStyle.mesh),
      [for (final c in (j['colors'] as List? ?? const [])) Color((c as num).toInt())]
        ..addAll(List.filled(4, const Color(0xFF111925)))
        ..length = 4,
      grain: (j['grain'] as num?)?.toDouble() ?? .25,
      animate: j['animate'] != false,
    );
