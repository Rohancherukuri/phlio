// Phlio Stream · Music — Now playing, with Retro's switchable player themes
// (Normal, Fit, Flat, Color, Material, Classic, Adaptive, Blur, Tiny, Peek,
// plus Card, Gradient and Circle), the album-cover carousel, synced lyrics
// (over or replacing the cover), the reorderable queue, sleep timer, volume,
// playback speed and driving mode. Shader backdrop: retro_glow.frag.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import 'music_library.dart';
import 'music_lyrics.dart';
import 'music_models.dart';
import 'music_player.dart';
import 'music_ui.dart';
import 'open_music_api.dart' show openAudiusArtist;
import 'phlio_code_sheet.dart';

/// Slides the now-playing screen up from the bottom.
Future<void> openNowPlaying(BuildContext context) => Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const NowPlayingScreen(),
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ));

/// Full-screen player in the theme chosen in settings (13 layouts).
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

/// Builds the chosen layout from shared pieces (top bar, cover, title,
/// seek bar, controls, extras) and keeps the cover carousel on the playing
/// song.
class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with SingleTickerProviderStateMixin {
  bool lyrics = false;
  PageController? _pages;
  double _height = 800; // screen height; short screens get a compact layout
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _pages?.dispose();
    _spin.dispose();
    super.dispose();
  }

  PageController _pager(double fraction, int index) {
    final p = _pages;
    if (p == null || p.viewportFraction != fraction) {
      p?.dispose();
      _pages = PageController(viewportFraction: fraction, initialPage: index);
    }
    return _pages!;
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(musicPlayerProvider);
    final store = ref.watch(musicStoreProvider);
    final pal = ref.watch(retroPaletteProvider);
    final t = player.current;
    if (t == null) {
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(backgroundColor: pal.bg),
        body: Center(child: Text('Nothing playing', style: TextStyle(color: pal.muted))),
      );
    }
    final colors = ref.watch(artColorsProvider(artKey(t))).valueOrNull ?? ArtColors.phlio;
    if (player.playing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
    final style = store.settings.style;
    // Keep the carousel on the playing song.
    final pages = _pages;
    if (pages != null && pages.hasClients && (pages.page?.round() ?? player.index) != player.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pages.hasClients) {
          pages.animateToPage(player.index, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
        }
      });
    }
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: _lightText(style, pal, colors) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: pal.bg,
            body: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: LayoutBuilder(builder: (_, box) {
                _height = box.maxHeight;
                return _layout(style, t, player, store, pal, colors);
              }),
            ),
          ),
        ),
      ),
    );
  }

  bool _lightText(NowPlayingStyle s, RetroPalette pal, ArtColors c) => switch (s) {
        NowPlayingStyle.color => c.onPrimary == Colors.white,
        NowPlayingStyle.blur || NowPlayingStyle.classic || NowPlayingStyle.gradient => true,
        _ => pal.dark,
      };

  // -- building blocks ------------------------------------------------------------------

  Widget _topBar(Color fg, {String? title}) => SafeArea(
        bottom: false,
        child: Row(children: [
          IconButton(
            tooltip: 'Close',
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(children: [
              Text('NOW PLAYING',
                  style: TextStyle(color: fg.withValues(alpha: .65), fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w800)),
              if (title != null)
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(
            tooltip: 'More',
            icon: Icon(Icons.more_vert_rounded, color: fg),
            onPressed: () => _more(context),
          ),
        ]),
      );

  /// Album cover: carousel of the queue (swipe to skip) or a single cover.
  Widget _cover(Track t, MusicPlayer player, MusicStore store,
      {double radius = 20, bool circle = false, double fraction = .86, bool lyricsAllowed = true}) {
    final pal = ref.read(retroPaletteProvider);
    Widget art(Track x) {
      Widget a = Artwork(track: x, radius: circle ? 0 : radius);
      if (circle) {
        a = RotationTransition(
          turns: _spin,
          child: ClipOval(
            child: Stack(fit: StackFit.expand, children: [
              a,
              CustomPaint(painter: _VinylPainter()),
            ]),
          ),
        );
      }
      return AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(radius),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 30, offset: const Offset(0, 14))],
          ),
          child: a,
        ),
      );
    }

    Widget cover;
    if (store.settings.carousel && player.queue.length > 1) {
      final ctrl = _pager(fraction, player.index);
      cover = PageView.builder(
        controller: ctrl,
        itemCount: player.queue.length,
        onPageChanged: (i) {
          if (i != player.index) {
            HapticFeedback.selectionClick();
            player.jumpTo(i);
          }
        },
        itemBuilder: (_, i) => AnimatedBuilder(
          animation: ctrl,
          builder: (_, child) {
            // Carousel effect: neighbours shrink and fade.
            var d = 0.0;
            if (ctrl.position.haveDimensions) d = (ctrl.page! - i).abs();
            final s = (1 - d * .14).clamp(.8, 1.0);
            return Opacity(
              opacity: (1 - d * .45).clamp(.3, 1.0),
              child: Transform.scale(scale: s, child: child),
            );
          },
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Center(child: art(player.queue[i]))),
        ),
      );
    } else {
      cover = Center(child: art(t));
    }
    if (!lyrics || !lyricsAllowed) return cover;
    if (!store.settings.lyricsOverCover) {
      return SyncedLyricsView(track: t, color: pal.text);
    }
    return Stack(fit: StackFit.expand, children: [
      ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: cover),
      DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), borderRadius: BorderRadius.circular(radius)),
      ),
      SyncedLyricsView(track: t, color: Colors.white, compact: true),
    ]);
  }

  Widget _title(Track t, Color fg, MusicStore store, {TextAlign align = TextAlign.left, double size = 22}) {
    final fav = store.isFavorite(t.id);
    final text = Column(
      crossAxisAlignment: align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('${t.artist} · ${t.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 14)),
      ],
    );
    return Row(children: [
      if (align == TextAlign.center) const SizedBox(width: 48),
      Expanded(child: text),
      IconButton(
        tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
        onPressed: () {
          HapticFeedback.lightImpact();
          store.toggleFavorite(t.id);
        },
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(fav), color: fav ? const Color(0xFFF5636B) : fg.withValues(alpha: .8)),
        ),
      ),
    ]);
  }

  Widget _seek(MusicPlayer player, Color fg, Color accent) => StreamBuilder<Duration>(
        stream: player.positionStream,
        builder: (_, snap) {
          final pos = snap.data ?? Duration.zero;
          final dur = player.duration;
          final max = math.max(1, dur.inMilliseconds).toDouble();
          return Column(children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: accent,
                inactiveTrackColor: fg.withValues(alpha: .2),
                thumbColor: accent,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: pos.inMilliseconds.clamp(0, max).toDouble(),
                max: max,
                onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text(formatDuration(pos), style: TextStyle(color: fg.withValues(alpha: .65), fontSize: 12)),
              const Spacer(),
              Text(formatDuration(dur), style: TextStyle(color: fg.withValues(alpha: .65), fontSize: 12)),
            ]),
          ]);
        },
      );

  Widget _controls(MusicPlayer player, Color fg, Color accent, {double play = 72, bool filled = true}) {
    final repeatIcon = switch (player.repeat) {
      RepeatMode.one => Icons.repeat_one_rounded,
      _ => Icons.repeat_rounded,
    };
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      IconButton(
        tooltip: 'Shuffle',
        onPressed: player.toggleShuffle,
        icon: Icon(Icons.shuffle_rounded, color: player.shuffle ? accent : fg.withValues(alpha: .6)),
      ),
      IconButton(
        tooltip: 'Previous',
        onPressed: player.previous,
        iconSize: 38,
        icon: Icon(Icons.skip_previous_rounded, color: fg),
      ),
      GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          player.toggle();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: play,
          height: play,
          decoration: BoxDecoration(
            color: filled ? accent : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: fg, width: 2),
            boxShadow: filled ? [BoxShadow(color: accent.withValues(alpha: .45), blurRadius: 22, offset: const Offset(0, 8))] : null,
          ),
          child: player.loading
              ? Padding(
                  padding: EdgeInsets.all(play * .3),
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: filled ? Colors.white : fg))
              : Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: play * .55, color: filled ? Colors.white : fg),
        ),
      ),
      IconButton(
        tooltip: 'Next',
        onPressed: player.next,
        iconSize: 38,
        icon: Icon(Icons.skip_next_rounded, color: fg),
      ),
      IconButton(
        tooltip: 'Repeat',
        onPressed: player.cycleRepeat,
        icon: Icon(repeatIcon, color: player.repeat == RepeatMode.off ? fg.withValues(alpha: .6) : accent),
      ),
    ]);
  }

  Widget _extras(MusicPlayer player, Color fg, Color accent) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        IconButton(
          tooltip: 'Lyrics',
          onPressed: () => setState(() => lyrics = !lyrics),
          icon: Icon(Icons.lyrics_outlined, color: lyrics ? accent : fg.withValues(alpha: .75)),
        ),
        IconButton(
          tooltip: 'Volume',
          onPressed: () => _volumeSheet(context),
          icon: Icon(
              player.player.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: fg.withValues(alpha: .75)),
        ),
        IconButton(
          tooltip: 'Sleep timer',
          onPressed: () => showSleepTimer(context, ref),
          icon: Icon(Icons.bedtime_outlined, color: player.sleepAt != null ? accent : fg.withValues(alpha: .75)),
        ),
        IconButton(
          tooltip: 'Playing queue',
          onPressed: () => showQueue(context, ref),
          icon: Icon(Icons.queue_music_rounded, color: fg.withValues(alpha: .75)),
        ),
      ]);

  Widget _volumeRow(MusicPlayer player, Color fg, Color accent) => Row(children: [
        Icon(Icons.volume_mute_rounded, color: fg.withValues(alpha: .6), size: 20),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: fg.withValues(alpha: .8),
              inactiveTrackColor: fg.withValues(alpha: .2),
              thumbColor: fg,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(value: player.player.volume, onChanged: player.setVolume),
          ),
        ),
        Icon(Icons.volume_up_rounded, color: fg.withValues(alpha: .6), size: 20),
      ]);

  Widget _upNext(MusicPlayer player, Color fg) {
    final next = player.index + 1 < player.queue.length ? player.queue[player.index + 1] : null;
    if (next == null) return const SizedBox(height: 8);
    return InkWell(
      onTap: () => showQueue(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Text('UP NEXT  ', style: TextStyle(color: fg.withValues(alpha: .55), fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
          Expanded(
            child: Text('${next.title} · ${next.artist}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 13)),
          ),
          Icon(Icons.keyboard_arrow_up_rounded, color: fg.withValues(alpha: .55)),
        ]),
      ),
    );
  }

  // -- the themes ------------------------------------------------------------------------

  Widget _layout(NowPlayingStyle s, Track t, MusicPlayer player, MusicStore store, RetroPalette pal, ArtColors c) {
    final energy = player.playing ? 1.0 : .25;
    // Short screens drop the extras that don't fit (no overflow stripes).
    final tight = _height < 640, compact = _height < 740;
    Widget column(Color fg, Color accent, {Widget? cover, double play = 72, bool filled = true, bool volume = false, TextAlign align = TextAlign.left}) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _title(t, fg, store, align: align, size: tight ? 19 : 22),
              SizedBox(height: tight ? 4 : 10),
              _seek(player, fg, accent),
              SizedBox(height: tight ? 2 : 6),
              _controls(player, fg, accent, play: tight ? math.min(play, 58) : play, filled: filled),
              if (volume && !compact) _volumeRow(player, fg, accent),
              if (!tight) const SizedBox(height: 4),
              _extras(player, fg, accent),
              if (!tight) _upNext(player, fg),
            ]),
          ),
        );

    switch (s) {
      case NowPlayingStyle.normal:
        return Stack(fit: StackFit.expand, children: [
          RetroGlow(colors: c, energy: energy, light: !pal.dark),
          Column(children: [
            _topBar(pal.text, title: t.album),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: _cover(t, player, store, fraction: .82))),
            column(pal.text, pal.accent),
          ]),
        ]);
      case NowPlayingStyle.fit:
        return Column(children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              _cover(t, player, store, radius: 0, fraction: 1),
              Align(alignment: Alignment.topCenter, child: _topBar(Colors.white)),
            ]),
          ),
          Container(color: pal.surface, padding: const EdgeInsets.only(top: 14), child: column(pal.text, pal.accent)),
        ]);
      case NowPlayingStyle.flat:
        return ColoredBox(
          color: pal.surface,
          child: Column(children: [
            _topBar(pal.text),
            Expanded(child: Padding(padding: const EdgeInsets.all(20), child: _cover(t, player, store, radius: 0, fraction: .9))),
            column(pal.text, pal.text, filled: false, play: 64),
          ]),
        );
      case NowPlayingStyle.color:
        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          color: c.primary,
          child: Column(children: [
            _topBar(c.onPrimary),
            Expanded(child: Padding(padding: const EdgeInsets.all(20), child: _cover(t, player, store))),
            column(c.onPrimary, c.onPrimary == Colors.white ? Colors.white : Colors.black, filled: false),
          ]),
        );
      case NowPlayingStyle.material:
        return Column(children: [
          _topBar(pal.text),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Card(
                elevation: 10,
                color: pal.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: _cover(t, player, store, radius: 0, fraction: 1),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(28)),
            padding: const EdgeInsets.only(top: 16),
            child: column(pal.text, c.primary, volume: true),
          ),
        ]);
      case NowPlayingStyle.classic:
        return Stack(fit: StackFit.expand, children: [
          _cover(t, player, store, radius: 0, fraction: 1, lyricsAllowed: false),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .35, .62, 1],
                colors: [Colors.black54, Colors.transparent, Colors.black.withValues(alpha: .8), Colors.black],
              ),
            ),
          ),
          Column(children: [
            _topBar(Colors.white),
            Expanded(child: lyrics ? SyncedLyricsView(track: t, color: Colors.white) : const SizedBox()),
            column(Colors.white, pal.accent2, volume: true),
          ]),
        ]);
      case NowPlayingStyle.adaptive:
        final light = c.primary.computeLuminance() > .45;
        final fg = light ? const Color(0xFF14121F) : Colors.white;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.primary, Color.lerp(c.secondary, pal.bg, .55)!],
            ),
          ),
          child: Column(children: [
            _topBar(fg),
            Expanded(child: Padding(padding: const EdgeInsets.all(18), child: _cover(t, player, store, radius: 14))),
            column(fg, light ? Colors.black : Colors.white, filled: true),
          ]),
        );
      case NowPlayingStyle.blur:
        return Stack(fit: StackFit.expand, children: [
          if (t.artUrl != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.mirror),
              child: CachedNetworkImage(imageUrl: AppConfig.mediaUrl(t.artUrl!), fit: BoxFit.cover),
            )
          else
            RetroGlow(colors: c, energy: energy),
          const ColoredBox(color: Color(0x88000000)),
          Column(children: [
            _topBar(Colors.white, title: t.album),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _cover(t, player, store, radius: 16))),
            column(Colors.white, Colors.white, filled: false, align: TextAlign.center),
          ]),
        ]);
      case NowPlayingStyle.tiny:
        return Column(children: [
          _topBar(pal.text),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              SizedBox(width: tight ? 92 : 120, height: tight ? 92 : 120, child: Artwork(track: t, radius: 16)),
              const SizedBox(width: 16),
              Expanded(child: _title(t, pal.text, store, size: 19)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            child: Column(children: [
              _seek(player, pal.text, pal.accent),
              _controls(player, pal.text, pal.accent, play: 60),
              _extras(player, pal.text, pal.accent),
            ]),
          ),
          SectionLabel(lyrics ? 'Lyrics' : 'Up next'),
          Expanded(
            child: lyrics
                ? SyncedLyricsView(track: t, color: pal.text, compact: true)
                : ListView.builder(
                    itemCount: math.max(0, player.queue.length - player.index - 1),
                    itemBuilder: (_, i) {
                      final q = player.index + 1 + i;
                      return SongTile(track: player.queue[q], onTap: () => player.jumpTo(q));
                    },
                  ),
          ),
        ]);
      case NowPlayingStyle.peek:
        return Stack(fit: StackFit.expand, children: [
          RetroGlow(colors: c, energy: energy, light: !pal.dark),
          Column(children: [
            _topBar(pal.text),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: _cover(t, player, store, fraction: .7, radius: 26))),
            column(pal.text, pal.accent),
          ]),
        ]);
      case NowPlayingStyle.card:
        return Stack(fit: StackFit.expand, children: [
          RetroGlow(colors: c, energy: energy, light: !pal.dark),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Card(
                color: pal.surface.withValues(alpha: .92),
                elevation: 18,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                child: Column(children: [
                  _topBar(pal.text),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _cover(t, player, store, fraction: .92))),
                  const SizedBox(height: 12),
                  column(pal.text, c.primary),
                ]),
              ),
            ),
          ),
        ]);
      case NowPlayingStyle.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.primary, c.secondary, c.tertiary]),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0x55000000)),
            child: Column(children: [
              _topBar(Colors.white),
              Expanded(child: Padding(padding: const EdgeInsets.all(18), child: _cover(t, player, store, radius: 28))),
              column(Colors.white, Colors.white, filled: false, play: 80, align: TextAlign.center),
            ]),
          ),
        );
      case NowPlayingStyle.circle:
        return Stack(fit: StackFit.expand, children: [
          RetroGlow(colors: c, energy: energy, light: !pal.dark),
          Column(children: [
            _topBar(pal.text),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (_, snap) {
                      final d = player.duration.inMilliseconds;
                      final f = d <= 0 ? 0.0 : ((snap.data?.inMilliseconds ?? 0) / d).clamp(0.0, 1.0);
                      return CustomPaint(
                        foregroundPainter: _ArcPainter(f, pal.accent, pal.muted.withValues(alpha: .25)),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: _cover(t, player, store, circle: true, fraction: 1),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            column(pal.text, pal.accent, align: TextAlign.center),
          ]),
        ]);
    }
    // ignore: dead_code
    return const SizedBox.shrink();
  }

  // -- sheets ----------------------------------------------------------------------------

  Future<void> _volumeSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => Consumer(builder: (_, ref, __) {
          final p = ref.watch(musicPlayerProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Volume', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Row(children: [
                  const Icon(Icons.volume_mute_rounded),
                  Expanded(child: Slider(value: p.player.volume, onChanged: p.setVolume)),
                  Text('${(p.player.volume * 100).round()}%'),
                ]),
                const Text('Phlio volume (your phone\'s volume buttons still control the overall level).',
                    style: TextStyle(fontSize: 12)),
              ]),
            ),
          );
        }),
      );

  Future<void> _more(BuildContext context) {
    final t = ref.read(musicPlayerProvider).current;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => Consumer(builder: (_, ref, __) {
        final p = ref.watch(musicPlayerProvider);
        final store = ref.watch(musicStoreProvider);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Now playing theme', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final e in nowPlayingStyleNames.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: store.settings.style == e.key,
                          onSelected: (_) {
                            store.settings.style = e.key;
                            store.save();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Album cover carousel'),
                value: store.settings.carousel,
                onChanged: (v) {
                  store.settings.carousel = v;
                  store.save();
                },
              ),
              SwitchListTile(
                title: const Text('Lyrics over the cover'),
                subtitle: const Text('Off: lyrics replace the cover'),
                value: store.settings.lyricsOverCover,
                onChanged: (v) {
                  store.settings.lyricsOverCover = v;
                  store.save();
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed_rounded),
                title: const Text('Playback speed'),
                subtitle: Slider(
                  value: p.player.speed.clamp(.5, 2.0),
                  min: .5,
                  max: 2,
                  divisions: 6,
                  label: '${p.player.speed.toStringAsFixed(2)}x',
                  onChanged: p.setSpeed,
                ),
                trailing: Text('${p.player.speed.toStringAsFixed(2)}x'),
              ),
              ListTile(
                leading: const Icon(Icons.directions_car_rounded),
                title: const Text('Driving mode'),
                onTap: () {
                  Navigator.pop(sheet);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrivingModeScreen()));
                },
              ),
              if (t != null) ...[
                ListTile(
                  leading: const Icon(Icons.library_add_rounded),
                  title: const Text('Add to playlist…'),
                  onTap: () {
                    Navigator.pop(sheet);
                    addToPlaylistSheet(context, ref, [t]);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_2_rounded),
                  title: const Text('Phlio Code'),
                  subtitle: const Text('Share a scannable code for this song'),
                  onTap: () {
                    Navigator.pop(sheet);
                    showPhlioCodeSheet(context, t);
                  },
                ),
                if (t.isAudius && (t.artistId ?? '').isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.person_search_rounded),
                    title: Text('About ${t.artist}'),
                    subtitle: const Text('Bio, popular tracks and similar artists'),
                    onTap: () {
                      Navigator.pop(sheet);
                      openAudiusArtist(context, t.artistId!);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Edit lyrics'),
                  onTap: () {
                    Navigator.pop(sheet);
                    editLyrics(context, ref, t);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Tag editor'),
                  onTap: () {
                    Navigator.pop(sheet);
                    openTagEditor(context, ref, t);
                  },
                ),
              ],
            ]),
          ),
        );
      }),
    );
  }
}

/// Record grooves and label drawn over the cover in the Circle theme.
class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: .18);
    for (var x = r * .38; x < r; x += r * .05) {
      canvas.drawCircle(c, x, groove);
    }
    canvas.drawCircle(c, r * .14, Paint()..color = const Color(0xFF0B0B12));
    canvas.drawCircle(c, r * .045, Paint()..color = const Color(0xFFFFB58F));
  }

  @override
  bool shouldRepaint(_VinylPainter old) => false;
}

/// Progress ring around the Circle theme's spinning record.
class _ArcPainter extends CustomPainter {
  _ArcPainter(this.f, this.color, this.track);
  final double f;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(2), 0, math.pi * 2, false, p..color = track);
    canvas.drawArc(rect.deflate(2), -math.pi / 2, math.pi * 2 * f, false, p..color = color);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.f != f || old.color != color;
}

// -- queue -------------------------------------------------------------------------------------

/// The playing queue: drag to sort, swipe to remove, save as a playlist.
Future<void> showQueue(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .85,
        child: Consumer(builder: (_, ref, __) {
          final p = ref.watch(musicPlayerProvider);
          final store = ref.read(musicStoreProvider);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 8, 4),
              child: Row(children: [
                Expanded(
                  child: Text('Playing queue · ${p.queue.length}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                ),
                TextButton(
                  onPressed: () async {
                    final name = await askText(context, 'Save queue as playlist', 'Name');
                    if (name != null && name.trim().isNotEmpty) {
                      store.createPlaylist(name, [for (final t in p.queue) t.id]);
                    }
                  },
                  child: const Text('Save'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(sheet);
                    p.clearQueue();
                  },
                  child: const Text('Clear'),
                ),
              ]),
            ),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: p.queue.length,
                buildDefaultDragHandles: false,
                onReorder: (from, to) => p.moveInQueue(from, to > from ? to - 1 : to),
                itemBuilder: (_, i) {
                  final t = p.queue[i];
                  final now = i == p.index;
                  return Dismissible(
                    key: ValueKey('${t.id}-$i'),
                    direction: now ? DismissDirection.none : DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: const Color(0xFFF5636B),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) => p.removeFromQueue(i),
                    child: ListTile(
                      leading: Artwork(track: t, size: 44, radius: 8),
                      title: Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: now ? FontWeight.w900 : FontWeight.w600)),
                      subtitle: Text(now ? 'Now playing' : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => p.jumpTo(i),
                      trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                    ),
                  );
                },
              ),
            ),
          ]);
        }),
      ),
    );

// -- sleep timer ---------------------------------------------------------------------------------

/// Sleep timer sheet: presets or a slider, optionally finishing the song.
Future<void> showSleepTimer(BuildContext context, WidgetRef ref) {
  var minutes = 30.0;
  var finish = false;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
      final p = ref.read(musicPlayerProvider);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Sleep timer', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            if (p.sleepAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Stops at ${TimeOfDay.fromDateTime(p.sleepAt!).format(sheet)}'),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [5, 10, 15, 30, 45, 60, 90])
                ChoiceChip(label: Text('$m min'), selected: minutes == m, onSelected: (_) => set(() => minutes = m.toDouble())),
            ]),
            Slider(value: minutes, min: 1, max: 180, divisions: 179, label: '${minutes.round()} min', onChanged: (v) => set(() => minutes = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Finish the last song'),
              value: finish,
              onChanged: (v) => set(() => finish = v),
            ),
            Row(children: [
              if (p.sleepAt != null)
                TextButton(
                    onPressed: () {
                      p.cancelSleep();
                      Navigator.pop(sheet);
                    },
                    child: const Text('Cancel timer')),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  p.setSleepTimer(Duration(minutes: minutes.round()), finishSong: finish);
                  Navigator.pop(sheet);
                },
                child: Text('Start · ${minutes.round()} min'),
              ),
            ]),
          ]),
        ),
      );
    }),
  );
}

// -- driving mode ------------------------------------------------------------------------------------

/// Driving mode: big title and huge buttons that are easy to hit at a glance.
class DrivingModeScreen extends ConsumerWidget {
  const DrivingModeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(musicPlayerProvider);
    final store = ref.watch(musicStoreProvider);
    final pal = ref.watch(retroPaletteProvider);
    final t = p.current;
    Widget big(IconData icon, String label, VoidCallback onTap, {Color? color}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Material(
              color: color ?? pal.card,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () {
                  HapticFeedback.heavyImpact();
                  onTap();
                },
                child: Semantics(
                  label: label,
                  button: true,
                  child: Center(child: Icon(icon, size: 72, color: color != null ? Colors.white : pal.text)),
                ),
              ),
            ),
          ),
        );
    return Theme(
      data: pal.theme(context),
      child: Scaffold(
        backgroundColor: pal.bg,
        body: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(
                  iconSize: 34, tooltip: 'Exit driving mode', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              const Spacer(),
              Text('DRIVING MODE', style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const Spacer(),
              IconButton(
                iconSize: 34,
                tooltip: 'Favourite',
                onPressed: t == null ? null : () => store.toggleFavorite(t.id),
                icon: Icon(t != null && store.isFavorite(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(children: [
                Text(t?.title ?? 'Nothing playing',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(t?.artist ?? '', style: TextStyle(fontSize: 20, color: pal.muted)),
              ]),
            ),
            StreamBuilder<Duration>(
              stream: p.positionStream,
              builder: (_, s) {
                final d = p.duration.inMilliseconds;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: LinearProgressIndicator(
                    value: d <= 0 ? 0 : ((s.data?.inMilliseconds ?? 0) / d).clamp(0.0, 1.0),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Column(children: [
                Expanded(
                  child: Row(children: [
                    big(Icons.skip_previous_rounded, 'Previous', p.previous),
                    big(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, 'Play or pause', p.toggle, color: pal.accent),
                    big(Icons.skip_next_rounded, 'Next', p.next),
                  ]),
                ),
                Expanded(
                  child: Row(children: [
                    big(Icons.shuffle_rounded, 'Shuffle', p.toggleShuffle, color: p.shuffle ? pal.accent2 : null),
                    big(p.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, 'Repeat', p.cycleRepeat,
                        color: p.repeat == RepeatMode.off ? null : pal.accent2),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// -- mini player ---------------------------------------------------------------------------------

/// The docked player at the bottom of music screens. Tap or swipe up to open
/// Now playing; swipe sideways to skip.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(musicPlayerProvider);
    final pal = RetroPaletteScope.of(context);
    final t = p.current;
    if (t == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => openNowPlaying(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) openNowPlaying(context);
      },
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) p.next();
        if (v > 300) p.previous();
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
            child: Row(children: [
              Hero(tag: 'np-art', child: Artwork(track: t, size: 46, radius: 10)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w800)),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12.5)),
                ]),
              ),
              IconButton(
                tooltip: p.playing ? 'Pause' : 'Play',
                onPressed: p.toggle,
                icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: pal.text, size: 30),
              ),
              IconButton(tooltip: 'Next', onPressed: p.next, icon: Icon(Icons.skip_next_rounded, color: pal.text)),
            ]),
          ),
          StreamBuilder<Duration>(
            stream: p.positionStream,
            builder: (_, s) {
              final d = p.duration.inMilliseconds;
              return LinearProgressIndicator(
                value: d <= 0 ? 0 : ((s.data?.inMilliseconds ?? 0) / d).clamp(0.0, 1.0),
                minHeight: 2.5,
                color: pal.accent,
                backgroundColor: pal.muted.withValues(alpha: .15),
              );
            },
          ),
        ]),
      ),
    );
  }
}
