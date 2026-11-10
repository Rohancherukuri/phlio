// Foxy stickers everywhere: one id scheme, one renderer, one picker.
//
// Ids a sticker can carry (in comments, moments, DMs, Rooms, creator chat):
//   foxy2:<act>            the rigged Foxy (FoxyPuppet) — e.g. foxy2:wave
//   foxy:<outfit>:<mood>   animated Foxy (Rive) — e.g. foxy:wizard:think
//   emoji_foxy_* / sticker_foxy_* / costume_* / text_*   Foxy pack PNGs
//   happy, wave, …         the original sticker set (PhlioStickers)
//   giphy:<kind>:<id>      a GIPHY GIF or sticker
// [FoxyStickerView] draws any of them; [showFoxyStickerSheet] picks one.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/giphy/giphy_picker.dart';
import '../colors.dart';
import '../typography.dart';
import 'foxy_pack.dart';
import 'foxy_puppet.dart';
import 'foxy_rive.dart';
import 'phlio_fox.dart';

typedef FoxyPuppetSticker = ({FoxyAct act, String label});

/// The Foxy sticker pack: the rigged mascot, fully animated (each sticker
/// loops its act, and hops when tapped in a chat bubble). Ids are
/// `foxy2:<act>`; keep in sync with `FOXY_PUPPET_CATALOG` in
/// backend/app/domains/stickers/__init__.py.
abstract final class FoxyPuppetStickers {
  static const prefix = 'foxy2:';

  static const List<FoxyPuppetSticker> catalog = [
    (act: FoxyAct.wave, label: 'Hey!'),
    (act: FoxyAct.love, label: 'Love you'),
    (act: FoxyAct.hooray, label: 'Hooray!'),
    (act: FoxyAct.clap, label: 'Bravo'),
    (act: FoxyAct.happy, label: 'So happy'),
    (act: FoxyAct.cheer, label: "Let's go"),
    (act: FoxyAct.think, label: 'Hmm…'),
    (act: FoxyAct.peek, label: 'Not looking'),
    (act: FoxyAct.oops, label: 'Oops'),
    (act: FoxyAct.sad, label: 'Aww'),
    (act: FoxyAct.phone, label: 'Call me'),
    (act: FoxyAct.chill, label: 'Chillin'),
    (act: FoxyAct.ready, label: 'Ready!'),
    (act: FoxyAct.run, label: 'On my way'),
    (act: FoxyAct.talk, label: 'Chatty'),
    (act: FoxyAct.sleep, label: 'Good night'),
  ];

  static String idOf(FoxyAct act) => '$prefix${act.name}';

  static List<String> get ids => [for (final s in catalog) idOf(s.act)];

  /// Parses `foxy2:<act>`; null for anything else.
  static FoxyAct? parse(String id) {
    if (!id.startsWith(prefix)) return null;
    final name = id.substring(prefix.length);
    for (final act in FoxyAct.values) {
      if (act.name == name) return act;
    }
    return null;
  }

  /// A pack item (label + a still) for code that only knows [FoxyPack].
  static FoxyPackItem? item(String id) {
    final act = parse(id);
    if (act == null) return null;
    return (
      id: id,
      label: labelOf(id),
      assetPath: switch (act) {
        FoxyAct.sleep => 'assets/images/foxy/foxy_sleepy.png',
        FoxyAct.think => 'assets/images/foxy/foxy_curious.png',
        FoxyAct.love || FoxyAct.happy => 'assets/images/foxy/foxy_happy.png',
        _ => 'assets/images/foxy/foxy_hello.png',
      },
      kind: FoxyReactionKind.sticker,
    );
  }

  static String labelOf(String id) {
    final act = parse(id);
    for (final s in catalog) {
      if (s.act == act) return s.label;
    }
    return 'Foxy';
  }
}

typedef FoxyAnimatedSticker = ({FoxyOutfit outfit, FoxyMood mood, String label});

abstract final class FoxyAnimatedStickers {
  static const prefix = 'foxy:';

  /// The curated animated set, in picker order.
  static const List<FoxyAnimatedSticker> catalog = [
    (outfit: FoxyOutfit.classic, mood: FoxyMood.wave, label: 'Hi!'),
    (outfit: FoxyOutfit.classic, mood: FoxyMood.celebrate, label: 'Yay'),
    (outfit: FoxyOutfit.classic, mood: FoxyMood.love, label: 'Love it'),
    (outfit: FoxyOutfit.classic, mood: FoxyMood.think, label: 'Hmm'),
    (outfit: FoxyOutfit.classic, mood: FoxyMood.sleep, label: 'Night night'),
    (outfit: FoxyOutfit.classic, mood: FoxyMood.noPeeking, label: 'Not looking'),
    (outfit: FoxyOutfit.classic, mood: FoxyMood.curious, label: 'Oh?'),
    (outfit: FoxyOutfit.classic, mood: FoxyMood.cozy, label: 'Cozy'),
    (outfit: FoxyOutfit.wizard, mood: FoxyMood.think, label: 'Magic'),
    (outfit: FoxyOutfit.wizard, mood: FoxyMood.celebrate, label: 'Ta-da'),
    (outfit: FoxyOutfit.chef, mood: FoxyMood.hello, label: 'Dinner?'),
    (outfit: FoxyOutfit.chef, mood: FoxyMood.love, label: "Chef's kiss"),
    (outfit: FoxyOutfit.traveler, mood: FoxyMood.explore, label: 'Trip time'),
    (outfit: FoxyOutfit.explorer, mood: FoxyMood.wave, label: 'Adventure'),
    (outfit: FoxyOutfit.space, mood: FoxyMood.curious, label: 'Out of this world'),
    (outfit: FoxyOutfit.samurai, mood: FoxyMood.focused, label: 'On guard'),
    (outfit: FoxyOutfit.samurai, mood: FoxyMood.celebrate, label: 'Victory'),
    (outfit: FoxyOutfit.business, mood: FoxyMood.focused, label: 'In a meeting'),
    (outfit: FoxyOutfit.business, mood: FoxyMood.celebrate, label: 'Deal!'),
    (outfit: FoxyOutfit.student, mood: FoxyMood.think, label: 'Studying'),
    (outfit: FoxyOutfit.hoodie, mood: FoxyMood.cozy, label: 'Chill'),
    (outfit: FoxyOutfit.hoodie, mood: FoxyMood.sleep, label: 'Five more minutes'),
    (outfit: FoxyOutfit.rainy, mood: FoxyMood.hello, label: 'Rainy day'),
    (outfit: FoxyOutfit.winter, mood: FoxyMood.cozy, label: 'Brr'),
    (outfit: FoxyOutfit.winter, mood: FoxyMood.love, label: 'Warm hugs'),
  ];

  static String idOf(FoxyOutfit outfit, FoxyMood mood) =>
      '$prefix${outfit.name}:${mood.name}';

  static String idFor(FoxyAnimatedSticker sticker) =>
      idOf(sticker.outfit, sticker.mood);

  /// Parses `foxy:<outfit>:<mood>`; null for anything else.
  static (FoxyOutfit, FoxyMood)? parse(String id) {
    if (!id.startsWith(prefix)) return null;
    final parts = id.substring(prefix.length).split(':');
    if (parts.length != 2) return null;
    final outfit = FoxyOutfit.byName(parts[0]);
    final mood = FoxyMood.byName(parts[1]);
    return outfit == null || mood == null ? null : (outfit, mood);
  }

  static String labelOf(String id) {
    final parsed = parse(id);
    if (parsed == null) return 'Foxy';
    for (final sticker in catalog) {
      if (sticker.outfit == parsed.$1 && sticker.mood == parsed.$2) {
        return sticker.label;
      }
    }
    return parsed.$1 == FoxyOutfit.classic
        ? parsed.$2.label
        : '${parsed.$1.label} · ${parsed.$2.label}';
  }

  /// A pack item for an animated id, so code that only knows [FoxyPack]
  /// (reaction chips, overlays) still gets a label and a still image.
  static FoxyPackItem? item(String id) {
    final parsed = parse(id);
    if (parsed == null) return null;
    final (outfit, mood) = parsed;
    return (
      id: id,
      label: labelOf(id),
      assetPath: outfit.stickerAsset ??
          (mood.loop ? 'assets/images/foxy/foxy_hello.png' : mood.fallbackAsset),
      kind: FoxyReactionKind.sticker,
    );
  }

  static List<FoxyPackItem> get items =>
      [for (final sticker in catalog) item(idFor(sticker))!];
}

/// Draws any sticker id (see the file header) at [size].
class FoxyStickerView extends StatelessWidget {
  const FoxyStickerView({
    super.key,
    required this.id,
    this.size = 96,
    this.interactive = false,
  });

  final String id;
  final double size;

  /// Animated stickers hop when tapped (chat bubbles); off inside pickers so
  /// the tap selects the sticker instead.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    if (id.startsWith('giphy:')) {
      return SizedBox(
          width: size, height: size, child: GiphyReferenceView(reference: id));
    }
    final puppet = FoxyPuppetStickers.parse(id);
    if (puppet != null) {
      return Semantics(
        label: FoxyPuppetStickers.labelOf(id),
        image: true,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: FoxyPuppet(
            act: puppet,
            size: size,
            entrance: false,
            tapToHop: interactive,
          ),
        ),
      );
    }
    final animated = FoxyAnimatedStickers.parse(id);
    if (animated != null) {
      // The artboard keeps air around Foxy for hops and props; zoom in a
      // little so he fills a sticker-sized box like the still stickers do.
      return Semantics(
        label: FoxyAnimatedStickers.labelOf(id),
        image: true,
        child: SizedBox(
          width: size,
          height: size,
          child: Transform.scale(
            scale: 1.22,
            alignment: const Alignment(0, 0.2),
            child: FoxyRive(
              outfit: animated.$1,
              mood: animated.$2,
              size: size,
              entrance: false,
              tapToHop: interactive,
              poofOnOutfitChange: false,
            ),
          ),
        ),
      );
    }
    final path = FoxyPack.resolve(id)?.assetPath ??
        (PhlioStickers.catalog.any((s) => s.id == id)
            ? PhlioStickers.assetFor(id)
            : null);
    return SizedBox(
      width: size,
      height: size,
      child: path == null
          ? const Icon(Icons.pets_rounded, color: PhlioColors.brandOrange)
          : Image.asset(
              path,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const Icon(Icons.pets_rounded,
                  color: PhlioColors.brandOrange),
            ),
    );
  }
}

/// Recently sent stickers, newest first (kept for this app session).
final List<String> _recentStickers = [];

void rememberSticker(String id) {
  _recentStickers
    ..remove(id)
    ..insert(0, id);
  if (_recentStickers.length > 16) _recentStickers.removeLast();
}

/// The Foxy sticker sheet. Returns a sticker id (or a `giphy:` reference
/// when [includeGiphy] and the person searched GIPHY), or null.
Future<String?> showFoxyStickerSheet(
  BuildContext context, {
  bool includeGiphy = true,
  bool includeFaces = true,
}) async {
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PhlioColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheet) => _FoxyStickerSheet(
        includeGiphy: includeGiphy, includeFaces: includeFaces),
  );
  if (id != null) rememberSticker(id);
  return id;
}

class _FoxyStickerSheet extends StatefulWidget {
  const _FoxyStickerSheet(
      {required this.includeGiphy, required this.includeFaces});

  final bool includeGiphy;
  final bool includeFaces;

  @override
  State<_FoxyStickerSheet> createState() => _FoxyStickerSheetState();
}

class _FoxyStickerSheetState extends State<_FoxyStickerSheet> {
  late final List<(String, List<String>)> _sections = [
    if (_recentStickers.isNotEmpty) ('Recent', List.of(_recentStickers)),
    ('Foxy', FoxyPuppetStickers.ids),
    ('Moves', [for (final item in FoxyPack.moves) item.id]),
    (
      'Animated',
      [for (final s in FoxyAnimatedStickers.catalog) FoxyAnimatedStickers.idFor(s)]
    ),
    (
      'Classic',
      [
        for (final item in FoxyPack.stickers)
          if (!item.id.startsWith('text_')) item.id
      ]
    ),
    (
      'Words',
      [
        for (final item in FoxyPack.stickers)
          if (item.id.startsWith('text_')) item.id
      ]
    ),
    if (widget.includeFaces)
      ('Faces', [for (final item in FoxyPack.emoji) item.id]),
  ];
  late int _tab = _recentStickers.isNotEmpty ? 1 : 0;

  Future<void> _searchGiphy() async {
    final item = await showGiphyPicker(context, kind: 'sticker');
    if (item != null && mounted) Navigator.of(context).pop(item.reference);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
    final (_, ids) = _sections[_tab];
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: PhlioColors.border,
                  borderRadius: BorderRadius.circular(4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Text('Stickers', style: PhlioTypography.title),
                  const Spacer(),
                  if (widget.includeGiphy)
                    TextButton.icon(
                      onPressed: _searchGiphy,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('GIPHY'),
                      style: TextButton.styleFrom(
                          foregroundColor: PhlioColors.textSecondary),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _sections.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final selected = index == _tab;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? PhlioColors.textPrimary
                            : PhlioColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _sections[index].$1,
                        style: PhlioTypography.label.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? PhlioColors.backgroundDeep
                              : PhlioColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: GridView.builder(
                  key: ValueKey(_tab),
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _sections[_tab].$1 == 'Faces' ? 5 : 4,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: ids.length,
                  itemBuilder: (context, index) => _StickerTile(
                    id: ids[index],
                    onTap: () => Navigator.of(context).pop(ids[index]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sticker that dips slightly under the finger — no box, no label (the
/// label is the long-press tooltip and the accessibility name).
class _StickerTile extends StatefulWidget {
  const _StickerTile({required this.id, required this.onTap});

  final String id;
  final VoidCallback onTap;

  @override
  State<_StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<_StickerTile> {
  bool _down = false;

  String get _label =>
      FoxyPack.resolve(widget.id)?.label ??
      (widget.id.startsWith('giphy:')
          ? 'GIPHY'
          : FoxyPuppetStickers.labelOf(widget.id));

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.88 : 1,
          duration: const Duration(milliseconds: 120),
          child: LayoutBuilder(
            builder: (context, box) => Center(
              child: FoxyStickerView(
                  id: widget.id, size: box.biggest.shortestSide - 6),
            ),
          ),
        ),
      ),
    );
  }
}
