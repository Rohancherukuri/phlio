// Experience — weekly photo dumps with your best friends (Phlio's take on
// Locket's Rollcall).
//
//   Intro    tilted photo cards fall into a collage and sway, then the
//            title, the three promises and "Let's do it!" rise in. Shown
//            the first time (a flag in the app documents folder).
//   Home     this week's range ("OCT 26 — NOV 1"), your friends' dumps
//            from the last 7 days, and your own past Experiences.
//   Share    pick up to 10 photos / videos → a stacked preview you can
//            swipe through, a caption and audience → "Share Experience".
//            Every item uploads as an `experience` memory with the same
//            `group`, so they show as one dump.
//   Viewer   a dump's cards one by one ("2 / 4"), who posted it and when,
//            quick reactions and a reply.
//
// Friends can see an Experience for 7 days (GET /social/memories).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../shared/content/memory_photo.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../rooms/data/datasources/messaging_api.dart';
import 'memories_screen.dart' show memoriesProvider;
import 'snap_audience.dart';

const _monthsShort = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The current Experience week, Sunday to Saturday.
(DateTime, DateTime) experienceWeek([DateTime? now]) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final start = today.subtract(Duration(days: today.weekday % 7));
  return (start, start.add(const Duration(days: 6)));
}

String _weekLabel((DateTime, DateTime) w) =>
    '${_monthsShort[w.$1.month - 1]} ${w.$1.day} — ${_monthsShort[w.$2.month - 1]} ${w.$2.day}';

/// Opens Experience: the intro the first time, then the home screen.
Future<void> openExperience(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final seen = await _IntroFlag.seen();
  await navigator.push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => seen ? const ExperienceHome() : const ExperienceIntroScreen(),
  ));
}

class _IntroFlag {
  static Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/phlio_experience_intro');
  static Future<bool> seen() async {
    try {
      return (await _file()).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> mark() async {
    try {
      await (await _file()).writeAsString('1');
    } catch (_) {}
  }
}

/// The Experience mark: a megaphone with sound lines, in the brand gradient.
class ExperienceMark extends StatelessWidget {
  const ExperienceMark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => PhlioColors.brandGradient.createShader(r),
        child: Transform.rotate(angle: -.35, child: Icon(Icons.campaign_rounded, size: size, color: Colors.white)),
      );
}

// -- intro -----------------------------------------------------------------------------

class ExperienceIntroScreen extends ConsumerStatefulWidget {
  const ExperienceIntroScreen({super.key});
  @override
  ConsumerState<ExperienceIntroScreen> createState() => _ExperienceIntroState();
}

class _ExperienceIntroState extends ConsumerState<ExperienceIntroScreen> with TickerProviderStateMixin {
  /// Cards falling in, then the text; [_sway] keeps the collage gently moving.
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))
    ..forward();
  late final AnimationController _sway = AnimationController(vsync: this, duration: const Duration(seconds: 5))
    ..repeat(reverse: true);

  // Card layout: horizontal centre (fraction of width), top (fraction of the
  // collage height), width (fraction of screen width), resting angle.
  static const _cards = [
    (x: .16, y: .08, w: .5, angle: -.12),
    (x: .5, y: .0, w: .44, angle: .05),
    (x: .86, y: .06, w: .46, angle: .1),
    (x: .3, y: .3, w: .52, angle: -.06),
    (x: .74, y: .32, w: .5, angle: .07),
  ];

  @override
  void dispose() {
    _enter.dispose();
    _sway.dispose();
    super.dispose();
  }

  /// Entrance sub-animations, made once (CurvedAnimation listens to its parent).
  final _intervals = <(double, double, Curve), Animation<double>>{};
  Animation<double> _interval(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      _intervals[(a, b, curve)] ??= CurvedAnimation(parent: _enter, curve: Interval(a, b, curve: curve));

  Future<void> _go() async {
    HapticFeedback.mediumImpact();
    await _IntroFlag.mark();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const ExperienceHome()));
  }

  @override
  Widget build(BuildContext context) {
    // Photos for the collage: your friends' and your own snaps if there are
    // any; Phlio gradient cards otherwise.
    final photos = (ref.watch(memoriesProvider).valueOrNull ?? const <Map>[])
        .where((m) => m['media_kind'] != 'video')
        .take(_cards.length)
        .toList();
    final size = MediaQuery.sizeOf(context);
    final collageH = size.height * .42;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: Stack(children: [
        // The collage.
        SizedBox(
          height: collageH + 60,
          width: size.width,
          child: AnimatedBuilder(
            animation: Listenable.merge([_enter, _sway]),
            builder: (_, __) => Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < _cards.length; i++) _card(i, size, collageH, i < photos.length ? photos[i] : null),
            ]),
          ),
        ),
        // Fade the collage into the page.
        Positioned(
          left: 0,
          right: 0,
          top: collageH - 40,
          height: 120,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00080E16), PhlioColors.background],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ),
        Positioned.fill(
          top: collageH + 10,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(children: [
                _rise(.42, .62, Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const ExperienceMark(size: 44),
                  const SizedBox(width: 10),
                  Text('Experience',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: size.width < 360 ? 34 : 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5)),
                ])),
                const SizedBox(height: 6),
                _rise(.48, .68, const Text('Weekly photo dumps\nwith all your best friends',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 17, height: 1.3))),
                const Spacer(),
                _rise(.55, .75, const _Promise(
                  leading: _SundayBadge(),
                  text: 'Share your favourite photos of the week, every Sunday',
                )),
                const SizedBox(height: 8),
                _rise(.6, .8, _Promise(leading: _StackThumb(photo: photos.isNotEmpty ? photos.first : null),
                    text: 'See what your friends did last week')),
                const SizedBox(height: 8),
                _rise(.65, .85, const _Promise(
                  leading: Icon(Icons.groups_rounded, color: PhlioColors.brandPeach, size: 38),
                  text: 'Friends can only see your Experience for the next 7 days',
                )),
                const Spacer(),
                ScaleTransition(
                  scale: _interval(.75, 1, Curves.easeOutBack),
                  child: SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      onPressed: _go,
                      child: const Text("Let's do it!"),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// A card drops in from above with a spin and settles on its angle.
  Widget _card(int i, Size screen, double collageH, Map? photo) {
    final c = _cards[i];
    // Plain curve maths here: this runs every frame.
    final t = Interval(i * .08, .32 + i * .08, curve: Curves.easeOutBack).transform(_enter.value);
    final w = screen.width * c.w;
    final h = w * 1.18;
    final sway = math.sin(_sway.value * math.pi * 2 + i * 1.3) * .012;
    final angle = c.angle + (1 - t) * (i.isEven ? -.6 : .6) + sway;
    final dy = (1 - t) * -(collageH + h);
    return Positioned(
      left: screen.width * c.x - w / 2,
      top: collageH * c.y - 30 + dy,
      width: w,
      height: h,
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F1EC),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: ClipRect(
              child: photo != null
                  ? MemoryPhoto('${photo['image_url']}', filter: photo['filter'] as String?)
                  : _placeholder(i),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(int i) {
    const palettes = [
      [PhlioColors.brandViolet, PhlioColors.brandPink],
      [PhlioColors.brandPeach, PhlioColors.brandPink],
      [PhlioColors.domainRooms, PhlioColors.brandBlue],
      [PhlioColors.brandPink, PhlioColors.brandPeach],
      [PhlioColors.brandBlue, PhlioColors.brandViolet],
    ];
    const icons = [Icons.celebration_rounded, Icons.local_cafe_rounded, Icons.landscape_rounded, Icons.pets_rounded, Icons.music_note_rounded];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: palettes[i % palettes.length]),
      ),
      child: Center(child: Icon(icons[i % icons.length], color: Colors.white70, size: 46)),
    );
  }

  /// Fades and slides a block up during [a]-[b] of the entrance.
  Widget _rise(double a, double b, Widget child) {
    final t = _interval(a, b);
    return FadeTransition(
      opacity: t,
      child: SlideTransition(position: Tween(begin: const Offset(0, .35), end: Offset.zero).animate(t), child: child),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.leading, required this.text});
  final Widget leading;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          SizedBox(width: 54, height: 44, child: Center(child: leading)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1.25)),
          ),
        ]),
      );
}

/// "SUN" calendar page with a gradient photos flower.
class _SundayBadge extends StatelessWidget {
  const _SundayBadge();
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Transform.rotate(
          angle: -.12,
          child: Container(
            width: 36,
            height: 34,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.topCenter,
            child: Container(
              height: 12,
              decoration: const BoxDecoration(
                  color: PhlioColors.danger, borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
              alignment: Alignment.center,
              child: const Text('SUN', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
        Positioned(
          right: -12,
          bottom: -6,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const SweepGradient(colors: [
                PhlioColors.brandPeach, PhlioColors.brandPink, PhlioColors.brandViolet, PhlioColors.brandBlue,
                PhlioColors.domainRooms, PhlioColors.brandPeach,
              ]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ]);
}

/// Three stacked photos.
class _StackThumb extends StatelessWidget {
  const _StackThumb({this.photo});
  final Map? photo;
  @override
  Widget build(BuildContext context) => Stack(children: [
        for (final (i, a) in [(0, .16), (1, -.1), (2, 0.0)])
          Transform.rotate(
            angle: a,
            child: Container(
              width: 40,
              height: 40,
              margin: EdgeInsets.only(left: i * 2.0),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
              child: i == 2 && photo != null
                  ? MemoryPhoto('${photo!['image_url']}')
                  : DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: i == 2
                              ? const LinearGradient(colors: [PhlioColors.domainRooms, PhlioColors.brandBlue])
                              : const LinearGradient(colors: [PhlioColors.brandViolet, PhlioColors.brandPink]))),
            ),
          ),
      ]);
}

// -- home --------------------------------------------------------------------------------

/// Experiences grouped into dumps: (group id, items oldest first).
List<(String, List<Map>)> experienceDumps(Iterable<Map> items) {
  final groups = <String, List<Map>>{};
  for (final m in items.where((m) => m['kind'] == 'experience')) {
    groups.putIfAbsent('${m['group'] ?? m['id']}', () => []).add(m);
  }
  for (final list in groups.values) {
    list.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
  }
  final out = [for (final e in groups.entries) (e.key, e.value)];
  out.sort((a, b) => '${b.$2.last['created_at']}'.compareTo('${a.$2.last['created_at']}'));
  return out;
}

class ExperienceHome extends ConsumerWidget {
  const ExperienceHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull?.id;
    final week = experienceWeek();
    final data = ref.watch(memoriesProvider);
    final dumps = experienceDumps(data.valueOrNull ?? const []);
    final friends = [for (final d in dumps) if (d.$2.first['author']?['id'] != me) d];
    final mine = [for (final d in dumps) if (d.$2.first['author']?['id'] == me) d];
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(children: [
          const Row(mainAxisSize: MainAxisSize.min, children: [
            ExperienceMark(size: 22),
            SizedBox(width: 6),
            Text('Experience', style: TextStyle(fontWeight: FontWeight.w900)),
          ]),
          Text(_weekLabel(week),
              style: const TextStyle(color: Colors.white54, fontSize: 11.5, letterSpacing: 1.6, fontFamily: 'monospace')),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(memoriesProvider.future),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          _ShareCard(onTap: () => shareExperience(context, ref)),
          const SizedBox(height: 22),
          const Text('From your friends', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (data.isLoading && dumps.isEmpty)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (friends.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(18)),
              child: const Column(children: [
                Icon(Icons.photo_library_outlined, color: Colors.white38, size: 48),
                SizedBox(height: 10),
                Text('No Experiences from friends yet',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 4),
                Text('When friends share their week, it shows up here for 7 days.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              ]),
            )
          else
            SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: friends.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _DumpCard(items: friends[i].$2, onTap: () => _view(context, friends[i].$2)),
              ),
            ),
          const SizedBox(height: 26),
          const Text('Your Experiences', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (mine.isEmpty)
            const Text('Look back on your weekly recaps by sharing your first Experience.',
                style: TextStyle(color: Colors.white60))
          else
            for (final d in mine) _MineRow(items: d.$2, onTap: () => _view(context, d.$2)),
        ]),
      ),
    );
  }

  void _view(BuildContext context, List<Map> items) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExperienceViewer(items: items)));
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final sunday = DateTime.now().weekday == DateTime.sunday;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: PhlioColors.brandGradient, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const Icon(Icons.add_photo_alternate_rounded, color: PhlioColors.textOnBrand, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sunday ? 'It\'s Sunday — share your week' : 'Share your Experience',
                    style: const TextStyle(color: PhlioColors.textOnBrand, fontSize: 17, fontWeight: FontWeight.w900)),
                const Text('Pick your favourite photos and videos of the week',
                    style: TextStyle(color: PhlioColors.textOnBrand, fontSize: 13)),
              ]),
            ),
            const Icon(Icons.arrow_forward_rounded, color: PhlioColors.textOnBrand),
          ]),
        ),
      ),
    );
  }
}

/// A friend's dump: the first three items fanned out, name and count.
class _DumpCard extends StatelessWidget {
  const _DumpCard({required this.items, required this.onTap});
  final List<Map> items;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final author = items.first['author'] as Map? ?? const {};
    final t = DateTime.tryParse('${items.last['created_at']}')?.toLocal();
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 170,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(clipBehavior: Clip.none, children: [
              for (final (i, m) in items.take(3).toList().reversed.indexed)
                Positioned.fill(
                  child: Transform.rotate(
                    angle: [.08, -.06, 0.0][(i + 3 - math.min(3, items.length)).clamp(0, 2).toInt()],
                    child: _Polaroid(item: m),
                  ),
                ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                  child: Text('${items.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text('${author['display_name'] ?? author['username'] ?? 'Friend'}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          if (t != null) Text(_weekdays[t.weekday - 1], style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
        ]),
      ),
    );
  }
}

class _Polaroid extends StatelessWidget {
  const _Polaroid({required this.item, this.autoplay = false});
  final Map item;
  final bool autoplay;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1EC),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 6))],
        ),
        child: ClipRect(
          child: MemoryPhoto('${item['image_url']}',
              isVideo: item['media_kind'] == 'video', filter: item['filter'] as String?, autoplay: autoplay),
        ),
      );
}

class _MineRow extends StatelessWidget {
  const _MineRow({required this.items, required this.onTap});
  final List<Map> items;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = DateTime.tryParse('${items.last['created_at']}')?.toLocal();
    final reactions = items.fold<int>(0, (n, m) => n + (m['reactions'] as List? ?? const []).length);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            for (final m in items.take(4))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MemoryPhoto('${m['image_url']}', isVideo: m['media_kind'] == 'video', filter: m['filter'] as String?),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t == null ? 'Experience' : _weekLabel(experienceWeek(t)),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                Text('${items.length} item${items.length == 1 ? '' : 's'} · $reactions reaction${reactions == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white54),
          ]),
        ),
      ),
    );
  }
}

// -- share --------------------------------------------------------------------------------

/// Picks up to 10 photos / videos and opens the Experience composer.
Future<void> shareExperience(BuildContext context, WidgetRef ref) async {
  final picked = await ImagePicker().pickMultipleMedia(limit: 10, imageQuality: 92, maxWidth: 2160);
  if (picked.isEmpty || !context.mounted) return;
  final shared = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ExperienceComposer(files: picked.take(10).toList())));
  if (shared == true) ref.invalidate(memoriesProvider);
}

bool _isVideoPath(String path) =>
    const ['.mp4', '.mov', '.m4v', '.webm', '.3gp'].any((e) => path.toLowerCase().endsWith(e));

class ExperienceComposer extends ConsumerStatefulWidget {
  const ExperienceComposer({required this.files, super.key});
  final List<XFile> files;
  @override
  ConsumerState<ExperienceComposer> createState() => _ExperienceComposerState();
}

class _ExperienceComposerState extends ConsumerState<ExperienceComposer> {
  late final List<XFile> _files = [...widget.files];
  final _caption = TextEditingController();
  final _pager = PageController(viewportFraction: .82);
  SnapAudience _audience = const SnapAudience();
  int _page = 0;
  int _sent = 0;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_busy || _files.isEmpty) return;
    setState(() {
      _busy = true;
      _sent = 0;
    });
    final group = 'exp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    try {
      for (final f in _files) {
        final video = _isVideoPath(f.path);
        await getIt<ApiClient>().dio.post(
              '/social/memories',
              data: FormData.fromMap({
                // The caption goes with the first item of the dump.
                'caption': f == _files.first ? _caption.text.trim() : '',
                'audience': _audience.mode,
                'recipients': jsonEncode(_audience.recipients),
                'kind': 'experience',
                'group': group,
                'file': await MultipartFile.fromFile(f.path,
                    filename: f.name,
                    contentType: video
                        ? DioMediaType('video', 'mp4')
                        : f.path.toLowerCase().endsWith('.png')
                            ? DioMediaType('image', 'png')
                            : DioMediaType('image', 'jpeg')),
              }),
              options: Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 3)),
            );
        if (mounted) setState(() => _sent++);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text('Experience shared with ${_audience.label} for 7 days')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Shared $_sent of ${_files.length}. Check your connection and try again.')));
        // Keep only what didn't go up, so a retry doesn't post twice.
        setState(() => _files.removeRange(0, _sent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final week = experienceWeek();
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(children: [
          const Text('Your Experience', style: TextStyle(fontWeight: FontWeight.w900)),
          Text(_weekLabel(week), style: const TextStyle(color: Colors.white54, fontSize: 11.5, letterSpacing: 1.6, fontFamily: 'monospace')),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 8),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: _files.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => AnimatedBuilder(
                animation: _pager,
                builder: (_, child) {
                  final page = _pager.hasClients && _pager.position.haveDimensions ? _pager.page ?? 0 : 0.0;
                  final d = (page - i).clamp(-1.0, 1.0);
                  return Transform.rotate(angle: d * -.08, child: Transform.scale(scale: 1 - d.abs() * .08, child: child));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: Stack(children: [
                    Positioned.fill(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F1EC),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))],
                        ),
                        child: ClipRect(child: _LocalMedia(file: _files[i], playing: i == _page)),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      top: 14,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() => _files.removeAt(i));
                                  if (_files.isEmpty) Navigator.pop(context);
                                },
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          Text('${math.min(_page + 1, _files.length)} / ${_files.length}', style: const TextStyle(color: Colors.white54)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: TextField(
              controller: _caption,
              enabled: !_busy,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Say something about your week…', counterText: ''),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Row(children: [
              ActionChip(
                avatar: const Icon(Icons.people_alt_outlined, size: 18),
                label: Text(_audience.label),
                onPressed: _busy
                    ? null
                    : () async {
                        final v = await pickSnapAudience(context, _audience);
                        if (mounted && v != null) setState(() => _audience = v);
                      },
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.black, shape: const StadiumBorder()),
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const ExperienceMark(size: 20),
                label: Text(_busy ? 'Sharing $_sent/${_files.length}…' : 'Share Experience',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A picked photo or (looping, muted) video.
class _LocalMedia extends StatefulWidget {
  const _LocalMedia({required this.file, required this.playing});
  final XFile file;
  final bool playing;
  @override
  State<_LocalMedia> createState() => _LocalMediaState();
}

class _LocalMediaState extends State<_LocalMedia> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (_isVideoPath(widget.file.path)) {
      final c = VideoPlayerController.file(File(widget.file.path));
      _video = c;
      c.initialize().then((_) async {
        await c.setLooping(true);
        await c.setVolume(0);
        if (widget.playing) await c.play();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(_LocalMedia old) {
    super.didUpdateWidget(old);
    final c = _video;
    if (c != null && c.value.isInitialized && old.playing != widget.playing) {
      widget.playing ? c.play() : c.pause();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _video;
    if (c == null) return Image.file(File(widget.file.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    if (!c.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      ),
    );
  }
}

// -- viewer --------------------------------------------------------------------------------

class ExperienceViewer extends ConsumerStatefulWidget {
  const ExperienceViewer({required this.items, super.key});
  final List<Map> items;
  @override
  ConsumerState<ExperienceViewer> createState() => _ExperienceViewerState();
}

class _ExperienceViewerState extends ConsumerState<ExperienceViewer> {
  final _pager = PageController();
  final _reply = TextEditingController();
  int _page = 0;
  String? _burst;

  @override
  void initState() {
    super.initState();
    _seen(0);
  }

  @override
  void dispose() {
    _pager.dispose();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _seen(int i) async {
    final item = widget.items[i];
    if (item['unread'] != true) return;
    try {
      await getIt<ApiClient>().dio.put('/social/memories/${item['id']}/seen');
    } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    final item = widget.items[_page];
    try {
      await getIt<ApiClient>().dio.put('/social/memories/${item['id']}/reaction', data: {'emoji': emoji});
      HapticFeedback.lightImpact();
      setState(() => _burst = emoji);
      ref.invalidate(memoriesProvider);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) setState(() => _burst = null);
    } catch (_) {
      _say('Could not send reaction. Try again.');
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    final author = widget.items.first['author'] as Map? ?? const {};
    if (text.isEmpty || author['username'] == null) return;
    try {
      await ref.read(messagingApiProvider).send('${author['username']}', 'Reply to your Experience: $text');
      _reply.clear();
      _say('Reply sent in messages.');
    } catch (_) {
      _say('Could not send reply. Try again.');
    }
  }

  void _say(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final me = ref.watch(authControllerProvider).valueOrNull?.id;
    final author = items.first['author'] as Map? ?? const {};
    final mine = author['id'] == me;
    final current = items[_page.clamp(0, items.length - 1)];
    final t = DateTime.tryParse('${current['created_at']}')?.toLocal();
    final avatar = author['avatar_url'] as String?;
    final caption = '${items.first['caption'] ?? ''}'.trim();
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(children: [
          const Row(mainAxisSize: MainAxisSize.min, children: [
            ExperienceMark(size: 20),
            SizedBox(width: 6),
            Text('Experience', style: TextStyle(fontWeight: FontWeight.w900)),
          ]),
          if (t != null)
            Text(_weekLabel(experienceWeek(t)),
                style: const TextStyle(color: Colors.white54, fontSize: 11.5, letterSpacing: 1.6, fontFamily: 'monospace')),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              PageView.builder(
                controller: _pager,
                itemCount: items.length,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _seen(i);
                },
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _Polaroid(item: items[i], autoplay: true),
                ),
              ),
              Positioned(
                right: 28,
                top: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                  child: Text('${_page + 1} / ${items.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
              ),
              if (_burst != null) Center(child: Text(_burst!, style: const TextStyle(fontSize: 96))),
            ]),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: PhlioColors.surfaceElevated,
              backgroundImage: avatar == null || avatar.isEmpty ? null : NetworkImage(AppConfig.mediaUrl(avatar)),
              child: avatar == null || avatar.isEmpty
                  ? Text('${author['display_name'] ?? author['username'] ?? '?'}'.characters.first.toUpperCase())
                  : null,
            ),
            title: Text('${author['display_name'] ?? author['username'] ?? 'Friend'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: Text(
                [if (t != null) _weekdays[t.weekday - 1], if (caption.isNotEmpty) caption].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60)),
            trailing: (current['reactions'] as List? ?? const []).isEmpty
                ? null
                : Text((current['reactions'] as List).map((r) => r['emoji']).take(4).join(' '),
                    style: const TextStyle(fontSize: 18)),
          ),
          if (!mine)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                for (final e in ['\u{1F602}', '\u{2764}\u{FE0F}', '\u{1F60D}', '\u{1F525}'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _react(e),
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: PhlioColors.surfaceElevated, shape: BoxShape.circle),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _reply,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Leave a comment…',
                      isDense: true,
                      filled: true,
                      fillColor: PhlioColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
