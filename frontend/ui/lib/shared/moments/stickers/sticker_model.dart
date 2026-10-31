// Moment stickers — the data model shared by the composer and the viewer.
//
// A sticker is a typed overlay on a moment: where it sits (centre as a
// fraction of the canvas), how big (scale, 1 = designed size on a 360-wide
// canvas), its rotation, and a `data` map whose keys depend on the type.
//
// Interactive stickers (poll, slider, question, countdown, like, add yours,
// link, music) stay live: they're sent as `overlays` and the viewer draws
// them on top so people can tap them. Everything else is decoration and is
// flattened into the photo (videos send every sticker as data).

import 'dart:math' as math;

/// Every sticker type the tray offers.
enum StickerType {
  location,
  mention,
  hashtag,
  link,
  music,
  photo,
  frame,
  cutout,
  gif,
  avatar,
  poll,
  question,
  slider,
  countdown,
  addyours,
  like,
  clock,
  weather,
  word, // Phlio type stickers ("SOUND ON", "MONDAY", "W"…)
  foxy, // Foxy sticker pack (design_system/widgets/foxy_stickers.dart)
}

/// Types that stay live in the viewer and are never flattened into the
/// photo: ones viewers can tap or answer, plus GIPHY GIFs / stickers so
/// they keep animating.
const interactiveStickers = {
  StickerType.gif,
  StickerType.poll,
  StickerType.question,
  StickerType.slider,
  StickerType.countdown,
  StickerType.addyours,
  StickerType.like,
  StickerType.link,
  StickerType.music,
};

/// Types whose responses the server stores (POST /social/moments/{id}/respond).
const respondingStickers = {
  StickerType.poll,
  StickerType.question,
  StickerType.slider,
  StickerType.countdown,
  StickerType.addyours,
  StickerType.like,
};

class MomentSticker {
  MomentSticker(this.type, this.data, {String? id, this.x = .5, this.y = .45, this.scale = 1, this.rotation = 0})
      : id = id ?? _newId();

  /// Stable id so responses can point at this sticker.
  final String id;
  final StickerType type;

  /// Type-specific fields, e.g. poll: {question, options}; slider: {prompt,
  /// emoji}; countdown: {title, ends}; link: {url, label}; music: {title,
  /// artist, url, cover_url}; photo/frame/cutout: {path, shape};
  /// gif: {url, title}; word: {word, style}; foxy: {sticker}.
  Map<String, dynamic> data;

  /// Centre as a fraction of the canvas (0–1).
  double x, y;
  double scale, rotation;

  bool get interactive => interactiveStickers.contains(type);

  /// Overlay JSON as stored with the moment. `foxy` keeps the legacy
  /// `{type: sticker, sticker: id}` shape older viewers understand.
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type == StickerType.foxy ? 'sticker' : type.name,
        if (type == StickerType.foxy) 'sticker': data['sticker'],
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'size': 26 * scale, // legacy viewers size Foxy stickers from this
        'data': data,
      };

  /// Parses an overlay; null for overlays that aren't stickers (old text layers).
  static MomentSticker? fromJson(Map j) {
    final name = j['type'] as String?;
    final type = name == 'sticker'
        ? StickerType.foxy
        : StickerType.values.where((t) => t.name == name).firstOrNull;
    if (type == null || (type == StickerType.foxy && j['sticker'] is! String)) return null;
    final data = Map<String, dynamic>.from((j['data'] as Map?) ?? const {});
    if (type == StickerType.foxy) data['sticker'] = j['sticker'];
    return MomentSticker(type, data,
        id: j['id'] as String?,
        x: (j['x'] as num? ?? .5).toDouble(),
        y: (j['y'] as num? ?? .5).toDouble(),
        scale: (j['scale'] as num? ?? ((j['size'] as num? ?? 26) / 26)).toDouble(),
        rotation: (j['rotation'] as num? ?? 0).toDouble());
  }

  static final _rng = math.Random();
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 20).toRadixString(36)}';
}

/// Phlio type stickers: the word and the style it's drawn in.
const wordStickers = <(String, String)>[
  ('SOUND ON', 'bubble'),
  ('TODAY', 'chrome'), // replaced by the weekday when drawn
  ('W', 'burst'),
  ('4K', 'tv'),
  ('GM', 'holo'),
  ('GN', 'neon'),
  ('VIBES', 'bubble'),
  ('OOTD', 'chrome'),
  ('IYKYK', 'neon'),
  ('SLAY', 'burst'),
  ('NEW', 'tag'),
  ('MOOD', 'holo'),
  ('ON REPEAT', 'tag'),
  ('MAIN CHARACTER', 'chrome'),
  ('BRB', 'tv'),
  ('YAY', 'bubble'),
];
