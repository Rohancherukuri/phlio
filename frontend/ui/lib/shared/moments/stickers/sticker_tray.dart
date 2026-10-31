// Moment stickers — the sticker tray (Stickers in the moment composer).
//
// Laid out like Instagram's tray, dressed in Phlio colours: a search field,
// a playful cloud of sticker chips (Location, Mention, Music, Photo, GIF,
// Add yours, Frames, Questions, Cutouts, Avatar, Templates, Emoji slider,
// Poll, Link, #hashtag, Countdown), then live stickers (clock, weather,
// likes), Phlio type stickers and the Foxy pack.
//
// Each chip asks for what it needs (a place, a poll's options, a song…)
// and returns a ready [MomentSticker]; Templates returns [TrayPick.templates].
//
// Below them, GIPHY: trending stickers and GIFs, and the search bar at the
// top searches GIPHY too (debounced), alongside the chips and Phlio stickers.

import 'dart:async';

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/config/app_config.dart';
import '../../../design_system/colors.dart';
import '../../../design_system/widgets/foxy_stickers.dart';
import '../../../features/stream/music/music_library.dart' show musicLibraryProvider;
import '../../../features/stream/music/music_models.dart' show Track;
import '../../../features/stream/music/open_music_api.dart' show audiusSearchProvider, audiusTrendingProvider, forYouChart;
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../giphy/giphy_picker.dart';
import 'sticker_model.dart';
import 'sticker_views.dart';

const _violet = PhlioColors.brandViolet;
const _pink = PhlioColors.brandPink;
const _peach = PhlioColors.brandPeach;
const _brand = LinearGradient(colors: [_violet, _pink, _peach]);

/// What the tray returns: a sticker, or a request to open Templates.
class TrayPick {
  const TrayPick.sticker(MomentSticker this.sticker) : templates = false;
  const TrayPick.templates()
      : sticker = null,
        templates = true;
  final MomentSticker? sticker;
  final bool templates;
}

/// Opens the tray. [userName] labels the Avatar sticker.
Future<TrayPick?> showStickerTray(BuildContext context, {required String userName}) =>
    showModalBottomSheet<TrayPick>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: PhlioColors.surface,
      barrierColor: Colors.black38,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _Tray(userName: userName),
    );

/// One chip in the tray.
class _ChipDef {
  const _ChipDef(this.label, this.icon, this.color, this.make);
  final String label;
  final IconData icon;
  final Color color;

  /// Builds the sticker (asking for input as needed); null = cancelled.
  final Future<TrayPick?> Function(BuildContext context, WidgetRef ref) make;
}

class _Tray extends ConsumerStatefulWidget {
  const _Tray({required this.userName});
  final String userName;
  @override
  ConsumerState<_Tray> createState() => _TrayState();
}

class _TrayState extends ConsumerState<_Tray> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  TrayPick _s(StickerType t, Map<String, dynamic> d) => TrayPick.sticker(MomentSticker(t, d));

  late final List<_ChipDef> _chips = [
    _ChipDef('Location', Icons.place_outlined, _violet, (c, r) async {
      final t = await askText(c, 'Location', 'Where are you?');
      return t == null ? null : _s(StickerType.location, {'text': t});
    }),
    _ChipDef('mention', Icons.alternate_email_rounded, _peach, (c, r) async {
      final t = await askText(c, 'Mention', '@username');
      return t == null ? null : _s(StickerType.mention, {'text': t.replaceAll(' ', '').replaceFirst('@', '')});
    }),
    _ChipDef('Music', Icons.music_note_rounded, _pink, (c, r) async {
      final song = await pickMomentSong(c);
      return song == null ? null : _s(StickerType.music, song);
    }),
    _ChipDef('Photo', Icons.image_outlined, const Color(0xFF68D7CD), (c, r) async {
      final path = await _pickImage();
      return path == null ? null : _s(StickerType.photo, {'path': path});
    }),
    _ChipDef('GIF', Icons.gif_box_outlined, const Color(0xFF68D7CD), (c, r) async {
      final gif = await showGiphyPicker(c, kind: 'sticker');
      return gif == null ? null : _s(StickerType.gif, {'url': gif.url, 'title': gif.title});
    }),
    _ChipDef('Add Yours', Icons.add_a_photo_outlined, _pink, (c, r) async {
      final t = await askText(c, 'Add yours', 'Show your view right now',
          suggestions: const ['Show your view right now', 'Your pet 🐾', 'Last photo you took', 'Coffee order ☕', 'Fit of the day']);
      return t == null ? null : _s(StickerType.addyours, {'prompt': t});
    }),
    _ChipDef('Frames', Icons.photo_size_select_actual_outlined, _peach, (c, r) async {
      final path = await _pickImage();
      if (path == null || !c.mounted) return null;
      final caption = await askText(c, 'Caption', 'Write on the frame', allowEmpty: true);
      return _s(StickerType.frame, {'path': path, 'caption': caption ?? ''});
    }),
    _ChipDef('Questions', Icons.help_outline_rounded, _violet, (c, r) async {
      final t = await askText(c, 'Questions', 'Ask me a question', initial: 'Ask me a question');
      return t == null ? null : _s(StickerType.question, {'prompt': t});
    }),
    _ChipDef('Cutouts', Icons.content_cut_rounded, const Color(0xFF2BC25B), (c, r) async {
      final path = await _pickImage();
      if (path == null || !c.mounted) return null;
      final shape = await _pickCutoutShape(c, path);
      return shape == null ? null : _s(StickerType.cutout, {'path': path, 'shape': shape});
    }),
    _ChipDef('Avatar', Icons.face_retouching_natural_outlined, _peach,
        (c, r) async => _s(StickerType.avatar, {'name': widget.userName})),
    _ChipDef('Templates', Icons.dashboard_customize_outlined, _peach, (c, r) async => const TrayPick.templates()),
    _ChipDef('Emoji slider', Icons.linear_scale_rounded, _pink, (c, r) async {
      final v = await _askSlider(c);
      return v == null ? null : _s(StickerType.slider, v);
    }),
    _ChipDef('Poll', Icons.poll_outlined, _violet, (c, r) async {
      final v = await _askPoll(c);
      return v == null ? null : _s(StickerType.poll, v);
    }),
    _ChipDef('Link', Icons.link_rounded, const Color(0xFF72A7FF), (c, r) async {
      final v = await _askLink(c);
      return v == null ? null : _s(StickerType.link, v);
    }),
    _ChipDef('#hashtag', Icons.tag_rounded, _violet, (c, r) async {
      final t = await askText(c, 'Hashtag', '#hashtag');
      return t == null ? null : _s(StickerType.hashtag, {'text': t.replaceAll(' ', '').replaceFirst('#', '')});
    }),
    _ChipDef('Countdown', Icons.timelapse_rounded, _pink, (c, r) async {
      final v = await _askCountdown(c);
      return v == null ? null : _s(StickerType.countdown, v);
    }),
  ];

  Future<void> _use(_ChipDef chip) async {
    HapticFeedback.selectionClick();
    final pick = await chip.make(context, ref);
    if (pick != null && mounted) Navigator.pop(context, pick);
  }

  void _pick(MomentSticker s) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, TrayPick.sticker(s));
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final chips = _chips.where((c) => q.isEmpty || c.label.toLowerCase().contains(q)).toList();
    final words = wordStickers.where((w) => q.isEmpty || w.$1.toLowerCase().contains(q)).toList();
    final now = TimeOfDay.now();
    final rng = math.Random(7); // the same playful tilt every time
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .82,
      maxChildSize: .95,
      minChildSize: .5,
      builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 10, 16, 32), children: [
        Center(
          child: Container(
              width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _q = v.trim()),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
            hintText: 'Search stickers, GIFs and more',
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: PhlioColors.surfaceElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 12, children: [
          for (final c in chips)
            Transform.rotate(
              angle: (rng.nextDouble() - .5) * .06,
              child: _TrayChip(chip: c, onTap: () => _use(c)),
            ),
        ]),
        const SizedBox(height: 24),
        if (q.isEmpty) ...[
          _section('Live'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _tile(MomentSticker(StickerType.clock, {
                'time': '${now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod}:${now.minute.toString().padLeft(2, '0')}',
                'period': now.period == DayPeriod.am ? 'AM' : 'PM',
              })),
              _WeatherTile(onPick: _pick),
              _tile(MomentSticker(StickerType.like, {})),
            ],
          ),
          const SizedBox(height: 20),
        ],
        _GiphyShelf(query: _q, onPick: _pick),
        const SizedBox(height: 20),
        if (words.isNotEmpty) ...[
          _section('Phlio stickers'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [for (final (w, style) in words) _tile(MomentSticker(StickerType.word, {'word': w, 'style': style}))],
          ),
          const SizedBox(height: 20),
        ],
        if (q.isEmpty || 'foxy'.contains(q))
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.all(14)),
            onPressed: () async {
              final id = await showFoxyStickerSheet(context, includeGiphy: false, includeFaces: false);
              if (id != null && mounted) _pick(MomentSticker(StickerType.foxy, {'sticker': id}));
            },
            icon: const Icon(Icons.pets_rounded),
            label: const Text('Foxy stickers'),
          ),
      ]),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
      );

  /// A sticker preview that inserts itself when tapped.
  Widget _tile(MomentSticker s) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _pick(s),
        child: Ink(
          decoration: BoxDecoration(color: PhlioColors.surfaceElevated.withValues(alpha: .5), borderRadius: BorderRadius.circular(16)),
          child: Padding(padding: const EdgeInsets.all(8), child: FittedBox(child: MomentStickerView(s))),
        ),
      );

  Future<String?> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 92);
    return picked?.path;
  }
}

/// A tray chip: dark Phlio surface, gradient hairline, coloured icon.
class _TrayChip extends StatelessWidget {
  const _TrayChip({required this.chip, required this.onTap});
  final _ChipDef chip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(14)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF161E2C), borderRadius: BorderRadius.circular(12.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (chip.label == 'Emoji slider')
                const _MiniSlider()
              else ...[
                Icon(chip.icon, color: chip.color, size: 22),
                const SizedBox(width: 7),
                Text(chip.label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
        ),
      );
}

class _MiniSlider extends StatelessWidget {
  const _MiniSlider();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 120,
        height: 24,
        child: Stack(alignment: Alignment.centerLeft, children: [
          Container(height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
          FractionallySizedBox(
              widthFactor: .5,
              child: Container(height: 6, decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(3)))),
          const Positioned(left: 46, child: Text('😍', style: TextStyle(fontSize: 20))),
        ]),
      );
}

// -- weather (Open-Meteo: free, no key) ------------------------------------------------------

class _WeatherTile extends StatefulWidget {
  const _WeatherTile({required this.onPick});
  final void Function(MomentSticker) onPick;
  @override
  State<_WeatherTile> createState() => _WeatherTileState();
}

class _WeatherTileState extends State<_WeatherTile> {
  bool _busy = false;

  Future<void> _go() async {
    final city = await askText(context, 'Weather', 'Your city');
    if (city == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final w = await fetchWeather(city);
      if (mounted) widget.onPick(MomentSticker(StickerType.weather, w));
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Couldn\'t find the weather for $city')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : _go,
        child: Ink(
          decoration: BoxDecoration(color: PhlioColors.surfaceElevated.withValues(alpha: .5), borderRadius: BorderRadius.circular(16)),
          child: Center(
            child: _busy
                ? const CircularProgressIndicator()
                : const FittedBox(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('28°C', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w300)),
                    ),
                  ),
          ),
        ),
      );
}

/// Current temperature for a place name (Open-Meteo geocoding + forecast).
Future<Map<String, dynamic>> fetchWeather(String city) async {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
  final geo = await dio.get('https://geocoding-api.open-meteo.com/v1/search',
      queryParameters: {'name': city, 'count': 1, 'language': 'en'});
  final place = ((geo.data as Map)['results'] as List).first as Map;
  final now = await dio.get('https://api.open-meteo.com/v1/forecast', queryParameters: {
    'latitude': place['latitude'],
    'longitude': place['longitude'],
    'current': 'temperature_2m,weather_code',
  });
  final current = (now.data as Map)['current'] as Map;
  final code = (current['weather_code'] as num).toInt();
  return {
    'temp': (current['temperature_2m'] as num).round(),
    'unit': 'C',
    'city': place['name'],
    'icon': code == 0
        ? '☀️'
        : code <= 3
            ? '⛅'
            : code <= 48
                ? '🌫️'
                : code <= 67 || (code >= 80 && code <= 82)
                    ? '🌧️'
                    : code <= 77 || code == 85 || code == 86
                        ? '❄️'
                        : '⛈️',
  };
}

// -- input sheets -------------------------------------------------------------------------

InputDecoration _field(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: PhlioColors.surfaceElevated,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );

/// Bottom sheet scaffold with a title and a Done button.
Future<T?> _sheet<T>(BuildContext context, String title, Widget Function(BuildContext, StateSetter, void Function(T?)) body) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: StatefulBuilder(
              builder: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                body(c, set, (v) => Navigator.pop(sheet, v)),
              ]),
            ),
          ),
        ),
      ),
    );

Widget _doneButton(VoidCallback? onTap, {String label = 'Add'}) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(14)),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.all(14)),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ),
    );

/// One line of text (with optional quick suggestions). Null when cancelled.
Future<String?> askText(BuildContext context, String title, String hint,
    {String initial = '', List<String> suggestions = const [], bool allowEmpty = false}) {
  final c = TextEditingController(text: initial);
  return _sheet<String>(context, title, (ctx, set, done) {
    void submit() {
      final t = c.text.trim();
      if (t.isNotEmpty || allowEmpty) done(t);
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: c,
        autofocus: true,
        maxLength: 80,
        style: const TextStyle(color: Colors.white, fontSize: 17),
        decoration: _field(hint).copyWith(counterText: ''),
        onSubmitted: (_) => submit(),
      ),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in suggestions)
            ActionChip(
              label: Text(s),
              onPressed: () => set(() => c.text = s),
            ),
        ]),
      ],
      _doneButton(submit),
    ]);
  });
}

Future<Map<String, dynamic>?> _askPoll(BuildContext context) {
  final q = TextEditingController();
  final opts = [TextEditingController(text: 'Yes'), TextEditingController(text: 'No')];
  return _sheet<Map<String, dynamic>>(context, 'Poll', (ctx, set, done) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          controller: q,
          autofocus: true,
          maxLength: 90,
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          decoration: _field('Ask a question…').copyWith(counterText: '')),
      const SizedBox(height: 8),
      for (final (i, o) in opts.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: o,
            maxLength: 40,
            style: const TextStyle(color: Colors.white),
            decoration: _field('Option ${i + 1}').copyWith(
              counterText: '',
              suffixIcon: opts.length > 2
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => set(() => opts.removeAt(i)),
                    )
                  : null,
            ),
          ),
        ),
      if (opts.length < 4)
        TextButton.icon(
          onPressed: () => set(() => opts.add(TextEditingController())),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add option'),
        ),
      _doneButton(() {
        final options = [for (final o in opts) if (o.text.trim().isNotEmpty) o.text.trim()];
        if (q.text.trim().isEmpty || options.length < 2) return;
        done({'question': q.text.trim(), 'options': options});
      }),
    ]);
  });
}

Future<Map<String, dynamic>?> _askSlider(BuildContext context) {
  final q = TextEditingController(text: 'How much do you love this?');
  var emoji = '😍';
  const emojis = ['😍', '🔥', '😂', '😮', '🥹', '💜', '🎉', '👏', '🤤', '💯'];
  return _sheet<Map<String, dynamic>>(context, 'Emoji slider', (ctx, set, done) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: q, autofocus: true, maxLength: 80, style: const TextStyle(color: Colors.white), decoration: _field('Ask something…')),
      Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
        for (final e in emojis)
          GestureDetector(
            onTap: () => set(() => emoji = e),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: e == emoji ? _violet.withValues(alpha: .35) : Colors.transparent),
              child: Text(e, style: const TextStyle(fontSize: 28)),
            ),
          ),
      ]),
      _doneButton(() => done({'prompt': q.text.trim(), 'emoji': emoji})),
    ]);
  });
}

Future<Map<String, dynamic>?> _askLink(BuildContext context) {
  final url = TextEditingController(text: 'https://');
  final label = TextEditingController();
  String? error;
  return _sheet<Map<String, dynamic>>(context, 'Link', (ctx, set, done) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          controller: url,
          autofocus: true,
          keyboardType: TextInputType.url,
          style: const TextStyle(color: Colors.white),
          decoration: _field('https://…').copyWith(errorText: error)),
      const SizedBox(height: 8),
      TextField(controller: label, maxLength: 30, style: const TextStyle(color: Colors.white), decoration: _field('Sticker text (optional)')),
      _doneButton(() {
        final u = Uri.tryParse(url.text.trim());
        if (u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty) {
          set(() => error = 'Enter a full web address');
          return;
        }
        done({'url': u.toString(), if (label.text.trim().isNotEmpty) 'label': label.text.trim()});
      }),
    ]);
  });
}

Future<Map<String, dynamic>?> _askCountdown(BuildContext context) {
  final title = TextEditingController();
  var ends = DateTime.now().add(const Duration(days: 1));
  return _sheet<Map<String, dynamic>>(context, 'Countdown', (ctx, set, done) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: title, autofocus: true, maxLength: 40, style: const TextStyle(color: Colors.white), decoration: _field('Countdown name')),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_rounded, color: _pink),
        title: Text(MaterialLocalizations.of(ctx).formatFullDate(ends), style: const TextStyle(color: Colors.white)),
        subtitle: Text(TimeOfDay.fromDateTime(ends).format(ctx), style: const TextStyle(color: Colors.white60)),
        onTap: () async {
          final d = await showDatePicker(
              context: ctx, initialDate: ends, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (d == null || !ctx.mounted) return;
          final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(ends));
          set(() => ends = DateTime(d.year, d.month, d.day, t?.hour ?? ends.hour, t?.minute ?? ends.minute));
        },
      ),
      _doneButton(() {
        if (title.text.trim().isEmpty) return;
        done({'title': title.text.trim(), 'ends': ends.toUtc().toIso8601String()});
      }),
    ]);
  });
}

Future<String?> _pickCutoutShape(BuildContext context, String path) =>
    _sheet<String>(context, 'Cutout shape', (ctx, set, done) {
      return Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
        for (final shape in cutoutShapes)
          GestureDetector(
            onTap: () => done(shape),
            child: SizedBox(
              width: 92,
              height: 92,
              child: FittedBox(child: MomentStickerView(MomentSticker(StickerType.cutout, {'path': path, 'shape': shape}))),
            ),
          ),
      ]);
    });

// -- music --------------------------------------------------------------------------------

/// Picks a song for the moment: Phlio Stream music or Audius (search or
/// this week's chart). Returns `{title, artist, url, cover_url}`, the shape
/// moments store in `music` and play from 0:20.
Future<Map<String, dynamic>?> pickMomentSong(BuildContext context) => showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _SongSheet(),
    );

class _SongSheet extends ConsumerStatefulWidget {
  const _SongSheet();
  @override
  ConsumerState<_SongSheet> createState() => _SongSheetState();
}

class _SongSheetState extends ConsumerState<_SongSheet> {
  String _q = '';

  Map<String, dynamic> _song(Track t) =>
      {'title': t.title, 'artist': t.artist, 'url': t.uri, if (t.artUrl != null) 'cover_url': t.artUrl};

  @override
  Widget build(BuildContext context) {
    final library = [
      for (final t in ref.watch(musicLibraryProvider).valueOrNull ?? const <Track>[])
        if (!t.isDevice && !t.podcast) t
    ];
    final online = _q.length >= 2
        ? ref.watch(audiusSearchProvider(_q)).valueOrNull?.$1
        : ref.watch(audiusTrendingProvider(forYouChart)).valueOrNull;
    final q = _q.toLowerCase();
    final local = library.where((t) => q.isEmpty || '${t.title} ${t.artist}'.toLowerCase().contains(q)).take(30).toList();
    Widget tile(Track t) => ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 46,
              height: 46,
              child: t.artUrl == null
                  ? const DecoratedBox(decoration: BoxDecoration(gradient: _brand), child: Icon(Icons.music_note_rounded, color: Colors.white))
                  : CachedNetworkImage(imageUrl: AppConfig.mediaUrl(t.artUrl!), fit: BoxFit.cover),
            ),
          ),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
          onTap: () => Navigator.pop(context, _song(t)),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(8, 14, 8, 24), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _q = v.trim()),
            style: const TextStyle(color: Colors.white),
            decoration: _field('Search music').copyWith(prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54)),
          ),
        ),
        if (local.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('PHLIO STREAM', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.4))),
          for (final t in local) tile(t),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(_q.length >= 2 ? 'ON AUDIUS' : 'TRENDING ON AUDIUS',
              style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.4)),
        ),
        if (online == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        for (final t in (online ?? const <Track>[]).take(30)) tile(t),
      ]),
    );
  }
}


// -- GIPHY stickers and GIFs ----------------------------------------------------------------

final _giphyApi = Dio(BaseOptions(
    baseUrl: 'https://api.giphy.com/v1',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15)));

/// One GIPHY result: a small preview for the grid and a sharper file for
/// the moment.
class _GiphyResult {
  _GiphyResult(this.id, this.title, this.preview, this.full);
  final String id, title, preview, full;

  static _GiphyResult? from(Map m) {
    final images = m['images'] as Map? ?? const {};
    String? url(String k) => (images[k] as Map?)?['url'] as String?;
    final preview = url('fixed_width_small') ?? url('fixed_width');
    final full = url('downsized') ?? url('fixed_width') ?? preview;
    if (preview == null || full == null) return null;
    return _GiphyResult('${m['id']}', '${m['title'] ?? 'GIPHY'}', preview, full);
  }
}

/// Trending (or searched) GIPHY stickers and GIFs inside the tray.
class _GiphyShelf extends StatefulWidget {
  const _GiphyShelf({required this.query, required this.onPick});

  /// The tray's search text; GIPHY is searched 400 ms after it settles.
  final String query;
  final void Function(MomentSticker) onPick;

  @override
  State<_GiphyShelf> createState() => _GiphyShelfState();
}

class _GiphyShelfState extends State<_GiphyShelf> {
  static const _page = 24;
  String _kind = 'stickers'; // or 'gifs'
  final _items = <_GiphyResult>[];
  bool _loading = false, _more = true;
  String? _error;
  int _ticket = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_GiphyShelf old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _load);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ticket++;
    super.dispose();
  }

  /// Loads the first page, or the next one with [append].
  Future<void> _load({bool append = false}) async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) {
        _items.clear();
        _more = true;
      }
    });
    try {
      final key = await resolveGiphyKey();
      if (!mounted || ticket != _ticket) return;
      if (key.isEmpty) {
        setState(() => _error = 'GIPHY isn\'t set up on this server yet.');
        return;
      }
      final q = widget.query.trim();
      final res = await _giphyApi.get('/$_kind/${q.isEmpty ? 'trending' : 'search'}', queryParameters: {
        'api_key': key,
        'limit': _page,
        'offset': _items.length,
        'rating': 'pg-13',
        if (q.isNotEmpty) 'q': q,
      });
      final data = ((res.data as Map)['data'] as List? ?? const []);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _items.addAll([for (final m in data) if (_GiphyResult.from(m as Map) case final r?) r]);
        _more = data.length == _page;
      });
    } catch (_) {
      if (mounted && ticket == _ticket) setState(() => _error = 'Couldn\'t load GIPHY. Tap to retry.');
    } finally {
      if (mounted && ticket == _ticket) setState(() => _loading = false);
    }
  }

  void _choose(_GiphyResult r) {
    final kind = _kind == 'gifs' ? 'gif' : 'sticker';
    // Same recents list as the DM GIF picker (best effort).
    unawaited(getIt<ApiClient>()
        .dio
        .post('/messaging/giphy/recents', data: {'giphy_id': r.id, 'kind': kind})
        .then((_) {}, onError: (_) {}));
    widget.onPick(MomentSticker(StickerType.gif, {'url': r.full, 'title': r.title, 'giphy_id': r.id, 'kind': kind}));
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(q.isEmpty ? 'TRENDING ON GIPHY' : 'GIPHY · "$q"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        ),
        for (final (k, label) in const [('stickers', 'Stickers'), ('gifs', 'GIFs')])
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(label),
              selected: _kind == k,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                if (_kind == k) return;
                setState(() => _kind = k);
                _load();
              },
            ),
          ),
      ]),
      const SizedBox(height: 10),
      if (_error != null)
        GestureDetector(
          onTap: _load,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
          ),
        )
      else if (_items.isEmpty && !_loading)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No ${_kind == 'gifs' ? 'GIFs' : 'stickers'} for "$q"',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
        )
      else
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _kind == 'gifs' ? 3 : 4, mainAxisSpacing: 8, crossAxisSpacing: 8),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final r = _items[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _choose(r),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: _kind == 'gifs' ? PhlioColors.surfaceElevated : Colors.transparent,
                  child: Image.network(
                    r.preview,
                    fit: _kind == 'gifs' ? BoxFit.cover : BoxFit.contain,
                    gaplessPlayback: true,
                    semanticLabel: r.title,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const DecoratedBox(decoration: BoxDecoration(color: Color(0x14FFFFFF))),
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white24),
                  ),
                ),
              ),
            );
          },
        ),
      if (_loading)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (_more && _items.isNotEmpty)
        TextButton(onPressed: () => _load(append: true), child: const Text('Show more')),
      // GIPHY's attribution requirement.
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Powered by GIPHY', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
      ),
    ]);
  }
}
