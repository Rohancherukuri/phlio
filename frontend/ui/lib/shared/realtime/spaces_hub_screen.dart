// Spaces hub — everything live audio in one place.
//
//   Live      Spaces happening now (tap → join sheet)
//   Recorded  finished Spaces that were recorded (tap → player)
//   Upcoming  your scheduled Spaces (start when you're ready)
//
// "Start a Space" opens Create your Space.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import 'create_space_screen.dart';
import 'space_recording_screen.dart';
import 'space_room_screen.dart';
import 'spaces.dart';

const _violet = PhlioColors.brandViolet;
const _rec = Color(0xFFFF4F79);

class SpacesHubScreen extends ConsumerStatefulWidget {
  const SpacesHubScreen({this.initialTab = 0, super.key});
  final int initialTab;
  @override
  ConsumerState<SpacesHubScreen> createState() => _SpacesHubScreenState();
}

class _SpacesHubScreenState extends ConsumerState<SpacesHubScreen> {
  late int _tab = widget.initialTab;

  Future<void> _refresh() async {
    ref.invalidate(liveSpacesProvider);
    ref.invalidate(spaceRecordingsProvider);
    ref.invalidate(scheduledSpacesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(children: [
              IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded)),
              const Spacer(),
              IconButton(
                  tooltip: 'About Spaces',
                  onPressed: () => showGetToKnowSpaces(context),
                  icon: const Icon(Icons.info_outline_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Spaces',
                  style: PhlioTypography.displayLarge.copyWith(fontSize: 32)),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SpaceEqualiser(height: 20, bars: 4),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: Text('Live audio conversations on Phlio Social',
                style: PhlioTypography.body.copyWith(fontSize: 15)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _Segments(
              labels: const ['Live', 'Recorded', 'Upcoming'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator(
              color: _violet,
              onRefresh: _refresh,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, .03), end: Offset.zero)
                            .animate(a),
                        child: child)),
                child: switch (_tab) {
                  0 => const _LiveList(key: ValueKey('live')),
                  1 => const _RecordedList(key: ValueKey('rec')),
                  _ => const _UpcomingList(key: ValueKey('up')),
                },
              ),
            ),
          ),
        ]),
      ),
      floatingActionButton: _StartButton(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const CreateSpaceScreen()))),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments(
      {required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: PhlioColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PhlioColors.border.withValues(alpha: .6)),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / labels.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: PhlioColors.sunsetGradient,
                ),
              ),
            ),
            Row(children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: PhlioTypography.bodyStrong.copyWith(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: i == index
                                ? PhlioColors.textOnBrand
                                : PhlioColors.textSecondary),
                        child: Text(labels[i]),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      );
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: PhlioColors.sunsetGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
                color: _violet.withValues(alpha: .35),
                blurRadius: 22,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mic_rounded, color: PhlioColors.textOnBrand),
                SizedBox(width: 8),
                Text('Start a Space',
                    style: TextStyle(
                        color: PhlioColors.textOnBrand,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5)),
              ]),
            ),
          ),
        ),
      );
}

// -- Live -------------------------------------------------------------------------

class _LiveList extends ConsumerWidget {
  const _LiveList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveSpacesProvider);
    final hidden = ref.watch(hiddenSpacesProvider);
    final items = (state.valueOrNull ?? const <Map>[])
        .where((s) => !hidden.contains(s['id']))
        .toList();
    if (state.isLoading && state.valueOrNull == null) {
      return const _Loading();
    }
    if (items.isEmpty) {
      return const _Empty(
          icon: Icons.graphic_eq_rounded,
          title: "No one's live right now",
          body: 'Start a Space and your followers will see it at the top of their feed.');
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
      itemCount: items.length,
      itemBuilder: (_, i) => _Stagger(
          index: i, child: _LiveCard(space: items[i], index: i)),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.space, required this.index});
  final Map space;
  final int index;

  static const _tints = [
    [Color(0xFF8D78FF), Color(0xFFE795D7)],
    [Color(0xFF72A7FF), Color(0xFF8D78FF)],
    [Color(0xFFE795D7), Color(0xFFFFB58F)],
    [Color(0xFF68D7CD), Color(0xFF72A7FF)],
  ];

  @override
  Widget build(BuildContext context) {
    final preview =
        ((space['preview'] as List?) ?? const []).whereType<Map>().toList();
    final listening = (space['participants_count'] as num?)?.toInt() ?? 0;
    final topics = ((space['topics'] as List?) ?? const []).cast<String>();
    final tint = _tints[index % _tints.length];
    final started = DateTime.tryParse(space['started_at'] as String? ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => showSpacePreview(context, space),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                      tint[0].withValues(alpha: .30), PhlioColors.surface),
                  Color.alphaBlend(
                      tint[1].withValues(alpha: .12), PhlioColors.surface),
                ],
              ),
              border: Border.all(color: tint[0].withValues(alpha: .35)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const _LiveTag(),
                      if (space['record'] == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: _rec.withValues(alpha: .6))),
                          child: Text('REC',
                              style: PhlioTypography.caption.copyWith(
                                  color: _rec,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11)),
                        ),
                      ],
                      const Spacer(),
                      if (started != null)
                        Text('started ${timeago.format(started)}',
                            style: PhlioTypography.caption
                                .copyWith(color: PhlioColors.textMuted)),
                    ]),
                    const SizedBox(height: 12),
                    Text(space['title'] as String? ?? 'Space',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.headline
                            .copyWith(fontSize: 19, height: 1.25)),
                    if (topics.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final t in topics)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .07),
                                borderRadius: BorderRadius.circular(999)),
                            child: Text(t,
                                style: PhlioTypography.caption.copyWith(
                                    color: PhlioColors.textSecondary)),
                          ),
                      ]),
                    ],
                    const SizedBox(height: 14),
                    Row(children: [
                      SpaceFaces(people: preview, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: space['name'] as String? ?? '',
                                style: const TextStyle(
                                    color: PhlioColors.textPrimary,
                                    fontWeight: FontWeight.w700)),
                            TextSpan(text: '  ·  $listening in the Space'),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.caption.copyWith(
                              color: PhlioColors.textMuted, fontSize: 13),
                        ),
                      ),
                      SpaceEqualiser(height: 16, color: tint[1]),
                    ]),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveTag extends StatelessWidget {
  const _LiveTag();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: _rec, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.graphic_eq_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text('LIVE',
              style: PhlioTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: .6)),
        ]),
      );
}

// -- Recorded ------------------------------------------------------------------------

class _RecordedList extends ConsumerWidget {
  const _RecordedList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spaceRecordingsProvider);
    if (state.hasError && state.valueOrNull == null) {
      return _Empty(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load recordings',
          body: 'Pull down to try again.',
          action: () => ref.invalidate(spaceRecordingsProvider));
    }
    if (state.valueOrNull == null) return const _Loading();
    final items = state.value!;
    if (items.isEmpty) {
      return const _Empty(
          icon: Icons.album_outlined,
          title: 'No recordings yet',
          body: 'Turn on "Record Space" when you start one and it lands here when it ends.');
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          _Stagger(index: i, child: _RecordingCard(item: items[i])),
    );
  }
}

String formatSpaceDuration(num seconds) {
  final d = Duration(seconds: seconds.round());
  if (d.inHours > 0) {
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds}s';
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.item});
  final Map item;
  @override
  Widget build(BuildContext context) {
    final speakers =
        ((item['speakers'] as List?) ?? const []).whereType<Map>().toList();
    final peaks = ((item['peaks'] as List?) ?? const [])
        .map((e) => (e as num).toDouble())
        .toList();
    final ended = DateTime.tryParse(item['ended_at'] as String? ?? '');
    final plays = (item['plays'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SpaceRecordingScreen(item: item))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B2F7A), Color(0xFF8D78FF)],
                  ),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
                      child: CustomPaint(
                          painter: MiniWavePainter(peaks,
                              color: Colors.white.withValues(alpha: .22))),
                    ),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: PhlioColors.sunsetGradient),
                    child: const Icon(Icons.play_arrow_rounded,
                        size: 20, color: PhlioColors.textOnBrand),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'] as String? ?? 'Space',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.title
                              .copyWith(fontSize: 15.5, height: 1.25)),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (speakers.isNotEmpty) ...[
                          SpaceFaces(people: speakers.take(3).toList(), size: 22),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                              [
                                formatSpaceDuration(
                                    (item['duration'] as num?) ?? 0),
                                if (ended != null) timeago.format(ended),
                                if (plays > 0) '$plays plays',
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PhlioTypography.caption
                                  .copyWith(color: PhlioColors.textMuted)),
                        ),
                      ]),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small static waveform (recording cards).
class MiniWavePainter extends CustomPainter {
  MiniWavePainter(this.peaks, {required this.color});
  final List<double> peaks;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    const n = 14;
    final w = size.width / n;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * .55;
    for (var i = 0; i < n; i++) {
      final v = peaks[(i * peaks.length / n).floor()];
      final h = math.max(2.0, size.height * v);
      final x = w * (i + .5);
      canvas.drawLine(Offset(x, size.height / 2 - h / 2),
          Offset(x, size.height / 2 + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(MiniWavePainter old) => old.peaks != peaks;
}

// -- Upcoming ----------------------------------------------------------------------

class _UpcomingList extends ConsumerWidget {
  const _UpcomingList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scheduledSpacesProvider);
    if (state.valueOrNull == null && !state.hasError) return const _Loading();
    final items = state.valueOrNull ?? const <Map>[];
    if (items.isEmpty) {
      return const _Empty(
          icon: Icons.event_available_outlined,
          title: 'Nothing scheduled',
          body: 'Schedule a Space from Create your Space and start it here when the time comes.');
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final when = DateTime.tryParse(item['starts_at'] as String? ?? '')
            ?.toLocal();
        return _Stagger(
          index: i,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: PhlioColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Container(
                width: 52,
                height: 56,
                decoration: BoxDecoration(
                  color: _violet.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: when == null
                    ? const Icon(Icons.event_rounded, color: _violet)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Text(
                                const [
                                  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
                                  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
                                ][when.month - 1],
                                style: PhlioTypography.caption.copyWith(
                                    color: _violet,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11)),
                            Text('${when.day}',
                                style: PhlioTypography.headline
                                    .copyWith(fontSize: 20, height: 1.1)),
                          ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'] as String? ?? 'Space',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.title.copyWith(fontSize: 15.5)),
                      if (when != null)
                        Text(
                            '${MaterialLocalizations.of(context).formatShortDate(when)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(when))}',
                            style: PhlioTypography.caption
                                .copyWith(color: PhlioColors.textMuted)),
                    ]),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _violet,
                    foregroundColor: PhlioColors.textOnBrand,
                    shape: const StadiumBorder()),
                onPressed: () async {
                  await openSpace(context,
                      scheduledId: item['id'].toString(),
                      title: item['title'] as String? ?? 'Space',
                      topics: ((item['topics'] as List?) ?? const [])
                          .cast<String>(),
                      record: item['record'] == true);
                  ref.invalidate(scheduledSpacesProvider);
                },
                child: const Text('Start',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// -- shared bits -----------------------------------------------------------------------

class _Stagger extends StatelessWidget {
  const _Stagger({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final delay = math.min(index, 6) * 60;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + delay),
      curve: Interval(delay / (380 + delay), 1, curve: Curves.easeOutCubic),
      builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
              offset: Offset(0, 18 * (1 - v)), child: child)),
      child: child,
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: SpaceEqualiser(height: 28, bars: 5)),
        ],
      );
}

class _Empty extends StatelessWidget {
  const _Empty(
      {required this.icon,
      required this.title,
      required this.body,
      this.action});
  final IconData icon;
  final String title, body;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(36, 70, 36, 120),
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _violet.withValues(alpha: .35),
                  _violet.withValues(alpha: .05),
                ]),
              ),
              child: Icon(icon, size: 42, color: PhlioColors.textPrimary),
            ),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: PhlioTypography.headline.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: PhlioTypography.body.copyWith(fontSize: 15)),
          if (action != null) ...[
            const SizedBox(height: 16),
            Center(
                child:
                    TextButton(onPressed: action, child: const Text('Retry'))),
          ],
        ],
      );
}
