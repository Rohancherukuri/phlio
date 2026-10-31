// Phlio Stream · Music — shared retro UI: base themes (Clearly White /
// Kinda Dark / Just Black) in Phlio colours, artwork with generated
// covers, colour extraction from album art, the shader backdrop, song tiles
// and the song / add-to-playlist menus.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/config/app_config.dart';
import '../../../design_system/colors.dart';
import 'music_library.dart';
import 'music_models.dart';
import 'music_player.dart';
import 'open_music_api.dart' show openAudiusArtist;
import 'phlio_code_sheet.dart';

// -- theme -------------------------------------------------------------------------

/// Colours for one base theme (Clearly White, Kinda Dark, Just Black), all
/// taken from Phlio's brand palette.
class RetroPalette {
  const RetroPalette({
    required this.bg,
    required this.surface,
    required this.card,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accent2,
    required this.dark,
  });
  final Color bg, surface, card, text, muted, accent, accent2;
  final bool dark;

  static RetroPalette of(MusicTheme t) => switch (t) {
        MusicTheme.white => const RetroPalette(
            bg: Color(0xFFF6F5FB),
            surface: Colors.white,
            card: Color(0xFFECEAF6),
            text: Color(0xFF14121F),
            muted: Color(0xFF6E6B80),
            accent: Color(0xFF6B55E8),
            accent2: Color(0xFFE77F5B),
            dark: false),
        MusicTheme.dark => const RetroPalette(
            bg: PhlioColors.background,
            surface: PhlioColors.surface,
            card: PhlioColors.surfaceElevated,
            text: PhlioColors.textPrimary,
            muted: PhlioColors.textMuted,
            accent: PhlioColors.brandViolet,
            accent2: PhlioColors.brandPeach,
            dark: true),
        MusicTheme.black => const RetroPalette(
            bg: Colors.black,
            surface: Color(0xFF0B0B0F),
            card: Color(0xFF16161D),
            text: Colors.white,
            muted: Color(0xFF8A8A98),
            accent: PhlioColors.brandViolet,
            accent2: PhlioColors.brandPeach,
            dark: true),
      };

  ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: accent,
        secondary: accent2,
        surface: surface,
        onSurface: text,
        onPrimary: Colors.white,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      iconTheme: IconThemeData(color: text),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, modalBackgroundColor: surface),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: muted.withValues(alpha: .25),
      ),
      listTileTheme: ListTileThemeData(textColor: text, iconColor: muted),
      dividerColor: muted.withValues(alpha: .15),
    );
  }
}

/// The palette for the theme chosen in music settings.
final retroPaletteProvider =
    Provider<RetroPalette>((ref) => RetroPalette.of(ref.watch(musicStoreProvider.select((s) => s.settings.theme))));

// -- artwork --------------------------------------------------------------------------

Color _seedColor(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), .55, .55).toColor();
}

/// Album art for a track: the network image when there is one, otherwise a
/// generated cover (gradient from the album name, vinyl grooves, initials).
/// Without [size] it fills its parent.
class Artwork extends StatelessWidget {
  const Artwork({required this.track, this.size, this.radius = 12, this.label, super.key});
  final Track track;
  final double? size, radius;
  final String? label; // generated cover text (album / artist)

  @override
  Widget build(BuildContext context) {
    final fallback = _Generated(seed: label ?? track.album, text: label ?? track.album);
    Widget child = track.artUrl == null
        ? fallback
        : CachedNetworkImage(
            imageUrl: AppConfig.mediaUrl(track.artUrl!),
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            errorWidget: (_, __, ___) => fallback,
            placeholder: (_, __) => fallback,
          );
    child = ClipRRect(borderRadius: BorderRadius.circular(radius ?? 0), child: child);
    return size == null ? child : SizedBox(width: size, height: size, child: child);
  }
}

/// The generated cover used when a track has no artwork.
class _Generated extends StatelessWidget {
  const _Generated({required this.seed, required this.text});
  final String seed, text;
  @override
  Widget build(BuildContext context) {
    final a = _seedColor(seed), b = _seedColor('$seed~');
    final initials = text.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
      ),
      child: LayoutBuilder(
        builder: (_, box) => Stack(fit: StackFit.expand, children: [
          // Retro grooves.
          CustomPaint(painter: _Grooves()),
          Center(
            child: Text(initials.isEmpty ? '♪' : initials,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontWeight: FontWeight.w900,
                    fontSize: math.max(12, box.maxWidth * .28),
                    letterSpacing: 1)),
          ),
        ]),
      ),
    );
  }
}

/// Faint vinyl grooves drawn over generated covers.
class _Grooves extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .08);
    final c = size.center(Offset.zero);
    for (var r = size.width * .12; r < size.width * .75; r += size.width * .06) {
      canvas.drawCircle(c, r, p);
    }
  }

  @override
  bool shouldRepaint(_Grooves old) => false;
}

// -- colours from artwork (Adaptive / Color themes) ---------------------------------------

/// Colours picked from album art: [primary] (dominant), [secondary],
/// [tertiary], and [onPrimary] for text on [primary].
class ArtColors {
  const ArtColors(this.primary, this.secondary, this.tertiary, this.onPrimary);
  final Color primary, secondary, tertiary, onPrimary;
  static const phlio = ArtColors(PhlioColors.brandViolet, PhlioColors.brandPink, PhlioColors.brandPeach, Colors.white);
}

final _artCache = <String, ArtColors>{};

/// Colours extracted from the artwork at [key] (see [artKey]), cached.
/// Keys that aren't URLs get colours seeded from the text instead.
final artColorsProvider = FutureProvider.family<ArtColors, String>((ref, key) async {
  if (_artCache[key] != null) return _artCache[key]!;
  if (!key.startsWith('/') && !key.startsWith('http')) {
    final a = _seedColor(key), b = _seedColor('$key~');
    return _artCache[key] = ArtColors(a, b, Color.lerp(a, b, .5)!, Colors.white);
  }
  try {
    final provider = ResizeImage(CachedNetworkImageProvider(AppConfig.mediaUrl(key)), width: 32, height: 32);
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      completer.complete(info.image);
      stream.removeListener(l);
    }, onError: (e, _) {
      completer.completeError(e);
      stream.removeListener(l);
    });
    stream.addListener(l);
    final image = await completer.future.timeout(const Duration(seconds: 8));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return ArtColors.phlio;
    // Score pixels by saturation × mid-brightness; pick 3 distinct hues.
    final buckets = <int, (double, double, double, double)>{};
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
      final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
      final score = hsl.saturation * (1 - (hsl.lightness - .5).abs() * 1.6) + .05;
      final bucket = (hsl.hue / 30).floor();
      final prev = buckets[bucket] ?? (0, 0, 0, 0);
      buckets[bucket] = (prev.$1 + r * score, prev.$2 + g * score, prev.$3 + b * score, prev.$4 + score);
    }
    final ranked = buckets.values.toList()..sort((a, b) => b.$4.compareTo(a.$4));
    Color pick(int i) {
      if (ranked.isEmpty) return PhlioColors.brandViolet;
      final v = ranked[math.min(i, ranked.length - 1)];
      return Color.fromARGB(255, (v.$1 / v.$4).round(), (v.$2 / v.$4).round(), (v.$3 / v.$4).round());
    }

    final p = pick(0);
    final colors = ArtColors(p, pick(1), pick(2), p.computeLuminance() > .55 ? Colors.black : Colors.white);
    return _artCache[key] = colors;
  } catch (_) {
    return ArtColors.phlio;
  }
});

/// Cache key for a track's art colours: its artwork URL, else its album.
String artKey(Track t) => t.artUrl ?? t.album;

// -- shader backdrop ------------------------------------------------------------------------

/// Animated shader backdrop (assets/shaders/retro_glow.frag): three drifting
/// fields of [colors] with grain and scanlines; [energy] 0–1 sets the pace.
/// Falls back to a gradient where shaders aren't supported.
class RetroGlow extends StatefulWidget {
  const RetroGlow({required this.colors, this.energy = 1, this.light = false, super.key});
  final ArtColors colors;
  final double energy;
  final bool light;
  @override
  State<RetroGlow> createState() => _RetroGlowState();
}

/// Loads the shader once and drives its time uniform with a ticker.
class _RetroGlowState extends State<RetroGlow> with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      _t = e.inMicroseconds / 1e6;
      if (mounted) setState(() {});
    })
      ..start();
    if (_program != null) {
      _shader = _program!.fragmentShader();
    } else {
      _loading ??= () async {
        try {
          _program = await ui.FragmentProgram.fromAsset('assets/shaders/retro_glow.frag');
        } catch (_) {}
      }();
      _loading!.then((_) {
        if (mounted && _program != null) setState(() => _shader = _program!.fragmentShader());
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _shader;
    final c = widget.colors;
    if (s == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(c.primary, widget.light ? Colors.white : Colors.black, .35)!,
              Color.lerp(c.secondary, widget.light ? Colors.white : Colors.black, .6)!,
            ],
          ),
        ),
      );
    }
    return CustomPaint(painter: _GlowPainter(s, _t, c, widget.energy, widget.light));
  }
}

/// Paints the glow shader over the whole canvas.
class _GlowPainter extends CustomPainter {
  _GlowPainter(this.shader, this.t, this.c, this.energy, this.light);
  final ui.FragmentShader shader;
  final double t, energy;
  final ArtColors c;
  final bool light;
  @override
  void paint(Canvas canvas, Size size) {
    void rgb(int i, Color col) {
      shader
        ..setFloat(i, col.r)
        ..setFloat(i + 1, col.g)
        ..setFloat(i + 2, col.b);
    }

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, t);
    rgb(3, c.primary);
    rgb(6, c.secondary);
    rgb(9, c.tertiary);
    shader
      ..setFloat(12, energy)
      ..setFloat(13, light ? 1 : 0);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlowPainter old) => true;
}

// -- lists ------------------------------------------------------------------------------------

/// Upper-case section heading with an optional action button on the right.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.action, this.onAction, super.key});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final pal = RetroPaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 8, 8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.6)),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!, style: TextStyle(color: pal.muted))),
      ]),
    );
  }
}

/// Inherits the active palette down the music screens.
class RetroPaletteScope extends InheritedWidget {
  const RetroPaletteScope({required this.palette, required super.child, super.key});
  final RetroPalette palette;
  static RetroPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RetroPaletteScope>()?.palette ?? RetroPalette.of(MusicTheme.dark);
  @override
  bool updateShouldNotify(RetroPaletteScope old) => old.palette != palette;
}

/// A song row: artwork (or track number), title, artist and length, and a
/// menu button. Highlights the playing song. Long-press opens the song menu.
class SongTile extends ConsumerWidget {
  const SongTile({
    required this.track,
    required this.onTap,
    this.index,
    this.trailing,
    this.showArt = true,
    super.key,
  });
  final Track track;
  final VoidCallback onTap;
  final int? index;
  final Widget? trailing;
  final bool showArt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = RetroPaletteScope.of(context);
    final current = ref.watch(musicPlayerProvider.select((p) => p.current?.id)) == track.id;
    return InkWell(
      onTap: onTap,
      onLongPress: () => showSongMenu(context, ref, track),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          if (index != null && !showArt)
            SizedBox(
                width: 30,
                child: Text('$index',
                    style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontFeatures: const [ui.FontFeature.tabularFigures()])))
          else
            Stack(children: [
              Artwork(track: track, size: 50, radius: 10),
              if (current)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
                  ),
                ),
            ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: current ? pal.accent : pal.text, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                  '${track.artist}${track.durationMs > 0 ? ' · ${formatDuration(track.duration)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.muted, fontSize: 12.5)),
            ]),
          ),
          trailing ??
              IconButton(
                tooltip: 'More',
                icon: Icon(Icons.more_vert_rounded, color: pal.muted),
                onPressed: () => showSongMenu(context, ref, track),
              ),
        ]),
      ),
    );
  }
}

// -- menus -------------------------------------------------------------------------------------

/// The song menu: play next, add to queue / playlist, favourite, tag editor,
/// Phlio Code, artist page (Audius), details and share.
Future<void> showSongMenu(BuildContext context, WidgetRef ref, Track t, {VoidCallback? onTagEditor}) async {
  HapticFeedback.selectionClick();
  final store = ref.read(musicStoreProvider);
  final player = ref.read(musicPlayerProvider);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Artwork(track: t, size: 48, radius: 10),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${t.artist} · ${t.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          _menu(sheet, Icons.queue_play_next_rounded, 'Play next', () => player.playNext(t)),
          _menu(sheet, Icons.playlist_add_rounded, 'Add to playing queue', () => player.addToQueue([t])),
          _menu(sheet, Icons.library_add_rounded, 'Add to playlist…', () => addToPlaylistSheet(context, ref, [t])),
          _menu(sheet, store.isFavorite(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              store.isFavorite(t.id) ? 'Remove from favourites' : 'Add to favourites', () => store.toggleFavorite(t.id)),
          _menu(sheet, Icons.edit_rounded, 'Tag editor', () => openTagEditor(context, ref, t)),
          _menu(sheet, Icons.qr_code_2_rounded, 'Phlio Code', () => showPhlioCodeSheet(context, t)),
          if (t.isAudius && (t.artistId ?? '').isNotEmpty)
            _menu(sheet, Icons.person_search_rounded, 'Go to artist', () => openAudiusArtist(context, t.artistId!)),
          _menu(sheet, Icons.info_outline_rounded, 'Details', () => _details(context, t, store)),
          if (!t.isDevice && t.ref != null)
            _menu(sheet, Icons.ios_share_rounded, 'Share', () => SharePlus.instance.share(ShareParams(text: '${t.title} · ${t.artist} on Phlio Stream'))),
        ]),
      ),
    ),
  );
}

Widget _menu(BuildContext sheet, IconData icon, String label, VoidCallback action) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.pop(sheet);
        action();
      },
    );

void _details(BuildContext context, Track t, MusicStore store) {
  showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(t.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (k, v) in [
          ('Artist', t.artist),
          ('Album', t.album),
          ('Genre', t.genre),
          ('Year', t.year?.toString() ?? '—'),
          ('Length', t.durationMs > 0 ? formatDuration(t.duration) : '—'),
          ('Source', t.isDevice ? 'This device' : t.isAudius ? 'Audius' : 'Phlio Stream'),
          if (t.plays != null) ('Audius plays', '${t.plays}'),
          ('Location', t.isDevice ? t.uri : t.folder),
          ('Plays', '${store.playCounts[t.id] ?? 0}'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$k  ', style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: v),
            ])),
          ),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
    ),
  );
}

/// Sheet to add [tracks] to an existing playlist or a new one.
Future<void> addToPlaylistSheet(BuildContext context, WidgetRef ref, List<Track> tracks) async {
  final store = ref.read(musicStoreProvider);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: const Text('New playlist'),
          onTap: () async {
            Navigator.pop(sheet);
            final name = await askText(context, 'New playlist', 'Name');
            if (name != null && name.trim().isNotEmpty) {
              store.createPlaylist(name, [for (final t in tracks) t.id]);
              _toast(context, 'Added to $name');
            }
          },
        ),
        for (final p in store.playlists)
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: Text(p.name),
            subtitle: Text('${p.trackIds.length} songs'),
            onTap: () {
              Navigator.pop(sheet);
              store.addToPlaylist(p, tracks.map((t) => t.id));
              _toast(context, 'Added to ${p.name}');
            },
          ),
      ]),
    ),
  );
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

/// Simple text dialog; returns the text, or null if cancelled.
Future<String?> askText(BuildContext context, String title, String hint, {String initial = ''}) async {
  final ctrl = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('Save')),
      ],
    ),
  );
  ctrl.dispose();
  return value;
}

/// Tag editor: edits are stored as Phlio overrides (the original file is
/// never modified), and apply everywhere in the library.
Future<void> openTagEditor(BuildContext context, WidgetRef ref, Track t) async {
  final store = ref.read(musicStoreProvider);
  final current = store.tags[t.id] ?? const {};
  final fields = {
    'title': TextEditingController(text: '${current['title'] ?? t.title}'),
    'artist': TextEditingController(text: '${current['artist'] ?? t.artist}'),
    'album': TextEditingController(text: '${current['album'] ?? t.album}'),
    'genre': TextEditingController(text: '${current['genre'] ?? t.genre}'),
    'year': TextEditingController(text: '${current['year'] ?? t.year ?? ''}'),
    'trackNo': TextEditingController(text: '${current['trackNo'] ?? t.trackNo ?? ''}'),
  };
  const labels = {
    'title': 'Title',
    'artist': 'Artist',
    'album': 'Album',
    'genre': 'Genre',
    'year': 'Year',
    'trackNo': 'Track number',
  };
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (page) => Scaffold(
      appBar: AppBar(
        title: const Text('Tag editor'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(page, true), child: const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Artwork(track: t, size: 160, radius: 18)),
        const SizedBox(height: 18),
        for (final e in fields.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: e.value,
              keyboardType: e.key == 'year' || e.key == 'trackNo' ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(labelText: labels[e.key], border: const OutlineInputBorder()),
            ),
          ),
        TextButton.icon(
          onPressed: () {
            store.setTags(t.id, {});
            Navigator.pop(page, false);
          },
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Reset to original tags'),
        ),
        const Text('Edits are saved in Phlio and shown everywhere in your library; the original file isn\'t changed.',
            style: TextStyle(fontSize: 12)),
      ]),
    ),
  ));
  if (saved == true) {
    store.setTags(t.id, {for (final e in fields.entries) e.key: e.value.text.trim()});
  }
  for (final c in fields.values) {
    c.dispose();
  }
}
