// Discord-style building blocks for Phlio Rooms, in Phlio colours.
//
//   ┌────┬──────────────────────────┐
//   │ 💬 │ Gaming Lab           ⌄   │  server rail (rooms you're in) and
//   │ ── │ [ Search ] [ Invite ]    │  the channel panel of the selected
//   │ ▌🎮│ TEXT CHANNELS            │  room: its text channel and the two
//   │  🎨│  # demo-gaming           │  voice/video lounges.
//   │  ＋│ VOICE CHANNELS           │
//   │  🧭│  🔊 Lounge   📹 Watch party│
//   └────┴──────────────────────────┘
//
// Icons are hand-drawn SVGs in assets/images/rooms_icons/ (24 grid, 1.8
// stroke), so every glyph shares one weight. Room pictures are the
// community's own icon/banner (openly licensed art from the seed), falling
// back to initials like Discord — no emoji or stock placeholder glyphs.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../domain/entities/room_entity.dart';

/// One of the Rooms SVG glyphs, tinted.
class RoomGlyph extends StatelessWidget {
  const RoomGlyph(this.name,
      {super.key, this.size = 22, this.color = PhlioColors.textSecondary});

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/images/rooms_icons/$name.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// A square, fixed-size tap target holding a glyph (header and composer
/// icons line up on the same 40 px grid).
class RoomIconButton extends StatelessWidget {
  const RoomIconButton(
    this.glyph, {
    super.key,
    required this.tooltip,
    required this.onTap,
    this.size = 22,
    this.color = PhlioColors.textSecondary,
    this.extent = 40,
  });

  final String glyph;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final Color color;
  final double extent;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: extent / 2 + 2,
          child: SizedBox.square(
            dimension: extent,
            child: Center(child: RoomGlyph(glyph, size: size, color: color)),
          ),
        ),
      );
}

String categoryGlyph(RoomCategory category) => switch (category) {
      RoomCategory.techAndAi => 'cat_tech',
      RoomCategory.gaming => 'cat_gaming',
      RoomCategory.artAndCreators => 'cat_art',
      RoomCategory.travelAndExplore => 'cat_travel',
      RoomCategory.foodAndLifestyle => 'cat_food',
      RoomCategory.sportsAndFitness => 'cat_sports',
      RoomCategory.moviesAndMusic => 'cat_movies',
      RoomCategory.studyAndLearn => 'cat_study',
      RoomCategory.localNearby => 'cat_local',
    };

List<Color> categoryColors(RoomCategory category) => switch (category) {
      RoomCategory.techAndAi => const [Color(0xFF72A7FF), Color(0xFF8D78FF)],
      RoomCategory.gaming => const [Color(0xFF8D78FF), Color(0xFFE795D7)],
      RoomCategory.artAndCreators => const [
          Color(0xFFE795D7),
          Color(0xFFFFB58F)
        ],
      RoomCategory.travelAndExplore => const [
          Color(0xFF68D7CD),
          Color(0xFF72A7FF)
        ],
      RoomCategory.foodAndLifestyle => const [
          Color(0xFFFFB58F),
          Color(0xFFF6B93B)
        ],
      RoomCategory.sportsAndFitness => const [
          Color(0xFF68D7CD),
          Color(0xFF8D78FF)
        ],
      RoomCategory.moviesAndMusic => const [
          Color(0xFFE795D7),
          Color(0xFF8D78FF)
        ],
      RoomCategory.studyAndLearn => const [
          Color(0xFF72A7FF),
          Color(0xFF68D7CD)
        ],
      RoomCategory.localNearby => const [Color(0xFFFFB58F), Color(0xFFE795D7)],
    };

/// A room's picture: its community icon, or its initials on a dark tile
/// when it has none (as Discord does). Circle when idle, rounded square when
/// selected.
class RoomAvatar extends StatelessWidget {
  const RoomAvatar(
      {super.key, required this.room, this.size = 48, this.selected = true});

  final RoomEntity room;
  final double size;
  final bool selected;

  static String initials(String name) {
    final words = name
        .split(RegExp(r'[\s&]+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w[0]))
        .toList();
    if (words.isEmpty) return name.isEmpty ? '?' : name[0].toUpperCase();
    return words.take(words.length >= 3 ? 3 : 2).map((w) => w[0]).join();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(selected ? size * .3 : size / 2);
    final fallback = Container(
      color: PhlioColors.surfaceElevated,
      alignment: Alignment.center,
      child: Text(initials(room.name),
          maxLines: 1,
          style: PhlioTypography.label.copyWith(
              fontSize: size * .3,
              fontWeight: FontWeight.w800,
              color: PhlioColors.textPrimary)),
    );
    final url = room.iconUrl;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: radius),
      child: url == null || url.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: AppConfig.mediaUrl(url),
              fit: BoxFit.cover,
              memCacheWidth: px,
              memCacheHeight: px,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
    );
  }
}

/// A room's banner image, or a soft wash of the brand gradient.
class RoomBanner extends StatelessWidget {
  const RoomBanner({super.key, required this.room, required this.height});
  final RoomEntity room;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = categoryColors(room.category);
    final wash = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors[0].withValues(alpha: .55),
            colors[1].withValues(alpha: .25),
          ],
        ),
      ),
    );
    final url = room.bannerUrl;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url == null || url.isEmpty
          ? wash
          : CachedNetworkImage(
              imageUrl: AppConfig.mediaUrl(url),
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, __) => wash,
              errorWidget: (_, __, ___) => wash,
            ),
    );
  }
}

/// Which part of Rooms the rail is showing.
enum RailSection { messages, room, explore }

/// The far-left rail shared by the Rooms home, Explore and the channel
/// drawer: Messages, your rooms, then Explore.
class ServerRail extends StatelessWidget {
  const ServerRail({
    super.key,
    required this.rooms,
    required this.onSelect,
    required this.onMessages,
    this.onExplore,
    this.selectedId,
    this.section = RailSection.room,
    this.loading = false,
  });

  final List<RoomEntity> rooms;
  final String? selectedId;
  final RailSection section;
  final bool loading;
  final ValueChanged<RoomEntity> onSelect;
  final VoidCallback onMessages;

  /// Explore lives in the bottom navigation, so the rail only shows this
  /// button on the Explore page itself (as the selected item).
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context) {
    final onMessagesTab = section == RailSection.messages;
    final onExploreTab = section == RailSection.explore;
    return Container(
      width: 72,
      color: PhlioColors.roomsRail,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _RailItem(
            tooltip: 'Messages',
            selected: onMessagesTab,
            onTap: onMessages,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(onMessagesTab ? 15 : 24),
                gradient: onMessagesTab ? PhlioColors.sunsetGradient : null,
                color: onMessagesTab ? null : PhlioColors.surfaceElevated,
              ),
              child: Center(
                  child: RoomGlyph('chat',
                      size: 23,
                      color: onMessagesTab
                          ? PhlioColors.textOnBrand
                          : PhlioColors.textPrimary)),
            ),
          ),
          Center(
            child: Container(
              width: 32,
              height: 2,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                  color: PhlioColors.borderSubtle,
                  borderRadius: BorderRadius.circular(1)),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          for (final room in rooms)
            _RailItem(
              tooltip: room.name,
              selected: section == RailSection.room && room.id == selectedId,
              onTap: () => onSelect(room),
              child: RoomAvatar(
                  room: room,
                  selected:
                      section == RailSection.room && room.id == selectedId),
            ),
          if (onExplore != null)
          _RailItem(
            tooltip: 'Explore communities',
            selected: onExploreTab,
            onTap: onExplore!,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(onExploreTab ? 15 : 24),
                color: onExploreTab
                    ? PhlioColors.brandViolet
                    : PhlioColors.surfaceElevated,
              ),
              child: Center(
                  child: RoomGlyph('compass',
                      size: 24,
                      color: onExploreTab
                          ? Colors.white
                          : PhlioColors.success)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rounded panel to the right of the rail (Discord's "Servers" sheet).
class RailPanel extends StatelessWidget {
  const RailPanel(
      {super.key, required this.title, required this.child, this.actions = const []});
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(26)),
        child: ColoredBox(
          color: PhlioColors.roomsSidebar,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 10, 6),
              child: Row(children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.headline.copyWith(
                          fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                ...actions,
              ]),
            ),
            Expanded(child: child),
          ]),
        ),
      );
}

String compactCount(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A community in Explore: banner, overlapping icon, name, about, activity
/// and a Preview / Open button (Discord's server discovery card).
class CommunityCard extends StatelessWidget {
  const CommunityCard({
    super.key,
    required this.room,
    required this.joined,
    required this.onPreview,
    this.onMore,
  });

  final RoomEntity room;
  final bool joined;
  final VoidCallback onPreview;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    const banner = 132.0, icon = 72.0;
    Widget stat(Color dot, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.caption.copyWith(
                      fontSize: 12.5, color: PhlioColors.textSecondary)),
            ),
          ],
        );
    return Material(
      color: PhlioColors.roomsInput,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPreview,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: banner + icon / 2,
            child: Stack(children: [
              RoomBanner(room: room, height: banner),
              if (onMore != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: .45),
                    shape: const CircleBorder(),
                    child: InkResponse(
                      onTap: onMore,
                      radius: 18,
                      child: const SizedBox.square(
                        dimension: 32,
                        child: Icon(Icons.more_horiz_rounded,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: PhlioColors.roomsInput,
                    borderRadius: BorderRadius.circular(icon * .3 + 4),
                  ),
                  child: RoomAvatar(room: room, size: icon),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.title
                        .copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(room.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.body.copyWith(
                        color: PhlioColors.textSecondary, height: 1.35)),
                const SizedBox(height: 12),
                Wrap(spacing: 18, runSpacing: 6, children: [
                  stat(PhlioColors.success,
                      '${compactCount(room.activeCount)} Active'),
                  stat(PhlioColors.textMuted,
                      '${compactCount(room.memberCount)} Members'),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: joined ? null : PhlioColors.sunsetGradient,
                      color: joined ? PhlioColors.surfaceElevated : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onPreview,
                        child: Center(
                          child: Text(joined ? 'Open' : 'Preview',
                              style: PhlioTypography.label.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: joined
                                      ? PhlioColors.textPrimary
                                      : PhlioColors.textOnBrand)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem(
      {required this.tooltip,
      required this.selected,
      required this.onTap,
      required this.child});

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // The white pill on the left edge: tall when selected, a dot on hover.
    final pill = widget.selected ? 36.0 : (_hover ? 18.0 : 0.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 48,
          child: Stack(alignment: Alignment.center, children: [
            Positioned(
              left: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 4,
                height: pill,
                decoration: const BoxDecoration(
                  color: PhlioColors.textPrimary,
                  borderRadius:
                      BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
            ),
            Tooltip(
              message: widget.tooltip,
              preferBelow: false,
              child: GestureDetector(onTap: widget.onTap, child: widget.child),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The channel list for one room.
class ChannelPanel extends StatelessWidget {
  const ChannelPanel({
    super.key,
    required this.room,
    required this.onOpenChat,
    required this.onVoice,
    required this.onVideo,
    required this.onSearch,
    required this.onInvite,
  });

  final RoomEntity room;
  final VoidCallback onOpenChat;
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onSearch;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PhlioColors.roomsSidebar,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Banner + name, like a Discord server header.
          Stack(children: [
            RoomBanner(room: room, height: 110),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      PhlioColors.roomsSidebar.withValues(alpha: .92),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 12,
              bottom: 10,
              child: Row(children: [
                Expanded(
                  child: Text(room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.title.copyWith(
                          fontWeight: FontWeight.w800, fontSize: 19)),
                ),
                const RoomGlyph('chevron_right',
                    size: 18, color: PhlioColors.textPrimary),
              ]),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Icon(Icons.circle, size: 8, color: PhlioColors.success),
              const SizedBox(width: 6),
              Text('${room.memberCount} members',
                  style: PhlioTypography.caption),
              if (room.isPrivate) ...[
                const SizedBox(width: 10),
                Text('· Private', style: PhlioTypography.caption),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Expanded(
                  child: _PanelButton(
                      glyph: 'search', label: 'Search', onTap: onSearch)),
              const SizedBox(width: 8),
              Expanded(
                  child: _PanelButton(
                      glyph: 'invite', label: 'Invite', onTap: onInvite)),
            ]),
          ),
          const _CategoryLabel('Text channels'),
          ChannelRow(
              glyph: 'hash', label: room.slug, selected: true, onTap: onOpenChat),
          const _CategoryLabel('Voice channels'),
          ChannelRow(glyph: 'speaker', label: 'Lounge', onTap: onVoice),
          ChannelRow(glyph: 'video', label: 'Watch party', onTap: onVideo),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton(
      {required this.glyph, required this.label, required this.onTap});
  final String glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PhlioColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              RoomGlyph(glyph, size: 17, color: PhlioColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: PhlioTypography.label
                      .copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 4),
        child: Row(children: [
          const RoomGlyph('chevron_down', size: 12, color: PhlioColors.textMuted),
          const SizedBox(width: 4),
          Text(text.toUpperCase(),
              style: PhlioTypography.caption.copyWith(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w800,
                  color: PhlioColors.textMuted)),
        ]),
      );
}

class ChannelRow extends StatelessWidget {
  const ChannelRow({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String glyph;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected
              ? PhlioColors.surfaceElevated
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              height: 38,
              child: Row(children: [
                const SizedBox(width: 10),
                RoomGlyph(glyph,
                    size: 19,
                    color: selected
                        ? PhlioColors.textPrimary
                        : PhlioColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.body.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? PhlioColors.textPrimary
                              : PhlioColors.textSecondary)),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// "Welcome to #channel!" at the very top of a channel's history.
class ChannelWelcome extends StatelessWidget {
  const ChannelWelcome({super.key, required this.room});
  final RoomEntity room;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: PhlioColors.surfaceElevated),
            child: const Center(
                child: RoomGlyph('hash',
                    size: 34, color: PhlioColors.textPrimary)),
          ),
          const SizedBox(height: 14),
          Text('Welcome to #${room.slug}!',
              style: PhlioTypography.headline
                  .copyWith(fontWeight: FontWeight.w800, fontSize: 24)),
          const SizedBox(height: 6),
          Text('This is the start of the #${room.slug} channel.',
              style: PhlioTypography.body
                  .copyWith(color: PhlioColors.textSecondary)),
          if (room.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child:
                    RoomGlyph('pin', size: 16, color: PhlioColors.brandLavender),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(room.description,
                    style: PhlioTypography.body
                        .copyWith(color: PhlioColors.textSecondary)),
              ),
            ]),
          ],
        ]),
      );
}

/// A centred date between days of messages: ───── November 2, 2026 ─────
class DayDivider extends StatelessWidget {
  const DayDivider(this.day, {super.key});
  final DateTime day;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          const Expanded(child: Divider(color: PhlioColors.borderSubtle)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('${_months[day.month - 1]} ${day.day}, ${day.year}',
                style: PhlioTypography.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: PhlioColors.textMuted)),
          ),
          const Expanded(child: Divider(color: PhlioColors.borderSubtle)),
        ]),
      );
}

/// Discord-style timestamps: "Today at 11:53", "Yesterday at 9:05",
/// otherwise "02/11/2026 11:53".
String discordTime(DateTime when) {
  final local = when.toLocal();
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final clock = '${local.hour}:${two(local.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today at $clock';
  if (diff == 1) return 'Yesterday at $clock';
  return '${two(local.day)}/${two(local.month)}/${local.year} $clock';
}

/// A stable name colour per author (like Discord role colours).
Color authorColor(String authorId) {
  const palette = [
    Color(0xFFB7A9FF),
    Color(0xFFFFC7A8),
    Color(0xFFF0B0E3),
    Color(0xFF8FE3DA),
    Color(0xFF9CC2FF),
  ];
  return palette[authorId.hashCode.abs() % palette.length];
}

bool sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}
