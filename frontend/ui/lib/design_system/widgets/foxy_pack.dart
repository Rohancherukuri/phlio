// The Foxy reaction pack: emoji badges, costume/text stickers and looping
// GIFs sliced from the brand asset sheet (scripts/media/build_foxy_asset_pack.py).
//
// [FoxyPack] is the single source of truth mapping backend reaction/attachment
// `value` ids ("emoji_foxy_happy", "costume_wizard", "anim_celebration", …)
// to bundled asset paths. [showFoxyPicker] is the tabbed Emoji / Stickers /
// GIFs sheet the composer and the document reactions share, and
// [FoxyReactionChip] renders one reaction at chip size.

import 'package:flutter/material.dart';

import '../colors.dart';
import '../radii.dart';
import '../spacing.dart';
import '../typography.dart';

enum FoxyReactionKind { emoji, sticker, gif }

typedef FoxyPackItem = ({String id, String label, String assetPath, FoxyReactionKind kind});

abstract final class FoxyPack {
  static const String _emojiBase = 'assets/emoji/emoji_foxy_';
  static const String _stickerBase = 'assets/stickers/sticker_';
  static const String _gifBase = 'assets/animations/anim_';

  /// Foxy emoji badges (transparent PNGs from the expressions sheet).
  static const List<FoxyPackItem> emoji = [
    (id: 'emoji_foxy_happy', label: 'Happy', assetPath: '${_emojiBase}happy.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_excited', label: 'Excited', assetPath: '${_emojiBase}excited.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_laughing', label: 'Laughing', assetPath: '${_emojiBase}laughing.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_winking', label: 'Winking', assetPath: '${_emojiBase}winking.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_love', label: 'Love', assetPath: '${_emojiBase}love.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_surprised', label: 'Surprised', assetPath: '${_emojiBase}surprised.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_curious', label: 'Curious', assetPath: '${_emojiBase}curious.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_thinking', label: 'Thinking', assetPath: '${_emojiBase}thinking.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_confused', label: 'Confused', assetPath: '${_emojiBase}confused.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_sad', label: 'Sad', assetPath: '${_emojiBase}sad.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_determined', label: 'Determined', assetPath: '${_emojiBase}determined.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_angry', label: 'Angry', assetPath: '${_emojiBase}angry.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_sleepy', label: 'Sleepy', assetPath: '${_emojiBase}sleepy.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_blushing', label: 'Blushing', assetPath: '${_emojiBase}blushing.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_thumbs_up', label: 'Thumbs up', assetPath: '${_emojiBase}thumbs_up.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_hello', label: 'Hello', assetPath: '${_emojiBase}hello.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_good_job', label: 'Good job', assetPath: '${_emojiBase}good_job.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_clap', label: 'Clap', assetPath: '${_emojiBase}clap.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_cheers', label: 'Cheers', assetPath: '${_emojiBase}cheers.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_sorry', label: 'Sorry', assetPath: '${_emojiBase}sorry.png', kind: FoxyReactionKind.emoji),
    (id: 'emoji_foxy_thanks', label: 'Thanks', assetPath: '${_emojiBase}thanks.png', kind: FoxyReactionKind.emoji),
  ];

  /// Classic expression stickers + costume skins + hand-lettered notes.
  static const List<FoxyPackItem> stickers = [
    // Classic chat stickers (existing pack).
    (id: 'sticker_foxy_happy', label: 'Foxy', assetPath: '${_stickerBase}foxy_happy.png', kind: FoxyReactionKind.sticker),
    (id: 'sticker_foxy_excited', label: 'Excited', assetPath: '${_stickerBase}foxy_excited.png', kind: FoxyReactionKind.sticker),
    (id: 'sticker_foxy_hello', label: 'Hello!', assetPath: '${_stickerBase}foxy_hello.png', kind: FoxyReactionKind.sticker),
    (id: 'sticker_foxy_thinking', label: 'Thinking', assetPath: '${_stickerBase}foxy_thinking.png', kind: FoxyReactionKind.sticker),
    (id: 'sticker_foxy_sad', label: 'Sad', assetPath: '${_stickerBase}foxy_sad.png', kind: FoxyReactionKind.sticker),
    (id: 'sticker_foxy_surprised', label: 'Surprised', assetPath: '${_stickerBase}foxy_surprised.png', kind: FoxyReactionKind.sticker),
    (id: 'sticker_foxy_sleepy', label: 'Sleepy', assetPath: '${_stickerBase}foxy_sleepy.png', kind: FoxyReactionKind.sticker),
    (id: 'sticker_foxy_coffee', label: 'Coffee', assetPath: '${_stickerBase}foxy_coffee.png', kind: FoxyReactionKind.sticker),
    // Costumes / themes.
    (id: 'costume_explorer', label: 'Explorer', assetPath: '${_stickerBase}costume_explorer.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_hoodie', label: 'Hoodie', assetPath: '${_stickerBase}costume_hoodie.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_space', label: 'Space', assetPath: '${_stickerBase}costume_space.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_samurai', label: 'Samurai', assetPath: '${_stickerBase}costume_samurai.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_wizard', label: 'Wizard', assetPath: '${_stickerBase}costume_wizard.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_chef', label: 'Chef', assetPath: '${_stickerBase}costume_chef.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_student', label: 'Student', assetPath: '${_stickerBase}costume_student.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_business', label: 'Business', assetPath: '${_stickerBase}costume_business.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_rainy', label: 'Rainy', assetPath: '${_stickerBase}costume_rainy.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_winter', label: 'Winter', assetPath: '${_stickerBase}costume_winter.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_sporty', label: 'Sporty', assetPath: '${_stickerBase}costume_sporty.png', kind: FoxyReactionKind.sticker),
    (id: 'costume_traveler', label: 'Traveler', assetPath: '${_stickerBase}costume_traveler.png', kind: FoxyReactionKind.sticker),
    // Hand-lettered notes.
    (id: 'text_hi', label: 'Hi!', assetPath: '${_stickerBase}text_hi.png', kind: FoxyReactionKind.sticker),
    (id: 'text_good_morning', label: 'Good morning', assetPath: '${_stickerBase}text_good_morning.png', kind: FoxyReactionKind.sticker),
    (id: 'text_good_night', label: 'Good night', assetPath: '${_stickerBase}text_good_night.png', kind: FoxyReactionKind.sticker),
    (id: 'text_on_my_way', label: 'On my way', assetPath: '${_stickerBase}text_on_my_way.png', kind: FoxyReactionKind.sticker),
    (id: 'text_lets_go', label: "Let's go", assetPath: '${_stickerBase}text_lets_go.png', kind: FoxyReactionKind.sticker),
    (id: 'text_nice', label: 'Nice!', assetPath: '${_stickerBase}text_nice.png', kind: FoxyReactionKind.sticker),
    (id: 'text_awesome', label: 'Awesome', assetPath: '${_stickerBase}text_awesome.png', kind: FoxyReactionKind.sticker),
    (id: 'text_oops', label: 'Oops!', assetPath: '${_stickerBase}text_oops.png', kind: FoxyReactionKind.sticker),
    (id: 'text_hmmm', label: 'Hmmm', assetPath: '${_stickerBase}text_hmmm.png', kind: FoxyReactionKind.sticker),
    (id: 'text_lol', label: 'LOL!', assetPath: '${_stickerBase}text_lol.png', kind: FoxyReactionKind.sticker),
    (id: 'text_thank_you', label: 'Thank you', assetPath: '${_stickerBase}text_thank_you.png', kind: FoxyReactionKind.sticker),
    (id: 'text_congrats', label: 'Congrats', assetPath: '${_stickerBase}text_congrats.png', kind: FoxyReactionKind.sticker),
    (id: 'text_stay_cozy', label: 'Stay cozy', assetPath: '${_stickerBase}text_stay_cozy.png', kind: FoxyReactionKind.sticker),
    (id: 'text_take_a_break', label: 'Take a break', assetPath: '${_stickerBase}text_take_a_break.png', kind: FoxyReactionKind.sticker),
    (id: 'text_done', label: 'Done!', assetPath: '${_stickerBase}text_done.png', kind: FoxyReactionKind.sticker),
  ];

  /// Looping Foxy GIF tiles.
  static const List<FoxyPackItem> gifs = [
    (id: 'anim_idle_blink', label: 'Foxy', assetPath: '${_gifBase}idle_blink.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_tail_wag', label: 'Tail wag', assetPath: '${_gifBase}tail_wag.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_happy_jump', label: 'Happy jump', assetPath: '${_gifBase}happy_jump.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_wave', label: 'Wave', assetPath: '${_gifBase}wave.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_typing', label: 'Typing', assetPath: '${_gifBase}typing.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_drink_coffee', label: 'Coffee', assetPath: '${_gifBase}drink_coffee.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_sleep', label: 'Sleep', assetPath: '${_gifBase}sleep.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_thinking', label: 'Thinking', assetPath: '${_gifBase}thinking.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_celebration', label: 'Celebration', assetPath: '${_gifBase}celebration.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_loading', label: 'Loading', assetPath: '${_gifBase}loading.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_heart', label: 'Heart', assetPath: '${_gifBase}heart.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_reading', label: 'Reading', assetPath: '${_gifBase}reading.gif', kind: FoxyReactionKind.gif),
    (id: 'anim_fly', label: 'Fly', assetPath: '${_gifBase}fly.gif', kind: FoxyReactionKind.gif),
  ];

  static final Map<String, FoxyPackItem> _byId = {
    for (final item in [...emoji, ...stickers, ...gifs]) item.id: item,
  };

  /// Resolves a backend value id ("costume_wizard", "anim_heart", …) to its
  /// bundled asset, or null when unknown (renderer falls back gracefully).
  static FoxyPackItem? resolve(String id) => _byId[id];

  static FoxyPackItem? find(FoxyReactionKind kind, String id) {
    final item = _byId[id];
    return (item != null && item.kind == kind) ? item : null;
  }
}

/// Renders one reaction at chip size: a unicode glyph, or the Foxy asset
/// (animated for gifs) for pack reactions.
class FoxyReactionChipContent extends StatelessWidget {
  const FoxyReactionChipContent({super.key, required this.kind, required this.value, this.size = 18});

  final FoxyReactionKind kind;
  final String value;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (kind == FoxyReactionKind.emoji && FoxyPack.resolve(value) == null) {
      // Plain unicode emoji reaction.
      return Text(value, style: TextStyle(fontSize: size * 0.95, height: 1.0));
    }
    final item = FoxyPack.resolve(value);
    final path = item?.assetPath;
    if (path == null) {
      // Unknown pack id — degrade to a paw glyph, never a broken-image box.
      return Icon(Icons.pets_rounded, size: size, color: PhlioColors.brandOrange);
    }
    return SizedBox(
      width: kind == FoxyReactionKind.emoji ? size * 0.9 : size * 1.35,
      height: kind == FoxyReactionKind.gif ? size * 1.35 : size,
      child: Image.asset(
        path,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.pets_rounded, size: size, color: PhlioColors.brandOrange),
      ),
    );
  }
}

/// The tabbed Emoji / Stickers / GIFs sheet. Returns the picked [FoxyPackItem],
/// or null when dismissed. Used by the composer (send a sticker/GIF) and by
/// document reactions (overlay a reaction on a file).
Future<FoxyPackItem?> showFoxyPicker(
  BuildContext context, {
  FoxyReactionKind initialTab = FoxyReactionKind.emoji,
  String title = 'Foxy pack',
}) {
  return showModalBottomSheet<FoxyPackItem>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: DefaultTabController(
        length: 3,
        initialIndex: switch (initialTab) {
          FoxyReactionKind.emoji => 0,
          FoxyReactionKind.sticker => 1,
          FoxyReactionKind.gif => 2,
        },
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: PhlioTypography.headline)),
                    _FoxyBadge(size: 30),
                  ],
                ),
              ),
              TabBar(
                tabs: const [
                  Tab(text: 'Emoji'),
                  Tab(text: 'Stickers'),
                  Tab(text: 'GIFs'),
                ],
                labelColor: PhlioColors.textPrimary,
                unselectedLabelColor: PhlioColors.textMuted,
                indicatorColor: PhlioColors.brandOrange,
                dividerColor: PhlioColors.borderSubtle,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final items in [FoxyPack.emoji, FoxyPack.stickers, FoxyPack.gifs])
                      GridView.builder(
                        padding: const EdgeInsets.all(PhlioSpacing.md),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 92,
                          mainAxisSpacing: PhlioSpacing.sm,
                          crossAxisSpacing: PhlioSpacing.sm,
                          childAspectRatio: 0.9,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return InkWell(
                            borderRadius: PhlioRadii.mdRadius,
                            onTap: () => Navigator.of(sheetContext).pop(item),
                            child: Container(
                              padding: const EdgeInsets.all(PhlioSpacing.xs),
                              decoration: BoxDecoration(
                                color: PhlioColors.surfaceElevated,
                                borderRadius: PhlioRadii.mdRadius,
                                border: Border.all(color: PhlioColors.borderSubtle),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Image.asset(
                                      item.assetPath,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.pets_rounded,
                                        color: PhlioColors.brandOrange,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.label,
                                    style: PhlioTypography.caption.copyWith(fontSize: 9),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FoxyBadge extends StatelessWidget {
  const _FoxyBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/emoji/emoji_foxy_happy.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.pets_rounded, color: PhlioColors.brandOrange),
      ),
    );
  }
}
