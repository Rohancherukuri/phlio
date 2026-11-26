// Phlio Move card stack on Phlio Social's Posts tab.
//
// Recent activities from everyone, as a deck: the front card shows the
// person, title, sport, time and kudos; the next two peek out above it.
// Tap or swipe right for the next one: the front card slides off to the
// right while the one behind moves forward. Swipe left to bring the
// previous one back in from the left. The deck loops. The round button
// opens the activity (route replay, stats, kudos and comments).
//
// Backend: GET /activities/feed (backend/app/api/v1/activities.py).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';
import 'package:phlio/design_system/widgets/phlio_card.dart' show PhlioAvatar;

import 'move_activity_screen.dart';
import 'move_api.dart';

final moveFeedProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await moveDio.get('/activities/feed', queryParameters: {'limit': 12});
  return [for (final a in ((res.data as Map)['items'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
});

// Phlio's dark surfaces, flat: no glow, gradient or shadow. The front card
// is the lightest; cards behind step down towards the feed's background.
const _card = PhlioColors.surfaceElevated;
const _cardBehind = PhlioColors.surface;
const _chip = PhlioColors.surfaceInput;
const _ink = PhlioColors.textPrimary;
const _inkSoft = PhlioColors.textMuted;

const _cardHeight = 286.0;
const _peek = 13.0; // how much of each card behind shows above
const _depth = 3; // cards drawn behind the front one

class MoveActivityDeck extends ConsumerStatefulWidget {
  const MoveActivityDeck({super.key});

  @override
  ConsumerState<MoveActivityDeck> createState() => _MoveActivityDeckState();
}

class _MoveActivityDeckState extends ConsumerState<MoveActivityDeck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);
  int _front = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Which way the front card leaves: +1 to the right (next), -1 to the left.
  int _dir = 1;

  /// Next activity: the front card slides off to the right and the one
  /// behind it moves forward.
  Future<void> _next(int count) async {
    if (count < 2 || _c.isAnimating) return;
    HapticFeedback.selectionClick();
    setState(() => _dir = 1);
    await _c.forward(from: 0);
    if (!mounted) return;
    setState(() => _front = (_front + 1) % count);
    _c.value = 0;
  }

  /// Previous activity: it slides back in from the left onto the stack.
  Future<void> _previous(int count) async {
    if (count < 2 || _c.isAnimating) return;
    HapticFeedback.selectionClick();
    setState(() {
      _dir = -1;
      _front = (_front - 1 + count) % count;
    });
    _c.value = 1;
    await _c.reverse(from: 1);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(moveFeedProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final n = items.length;
    final front = _front % n;
    final behind = (n - 1).clamp(0, _depth);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(children: [
            Text('Activities', style: PhlioTypography.title.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: moveAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
              child: Text('Phlio Move', style: PhlioTypography.caption.copyWith(color: moveAccent, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            if (n > 1)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text('${front + 1} / $n', key: ValueKey(front), style: PhlioTypography.caption),
              ),
          ]),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _next(n),
          // Swipe right for the next activity, left to go back.
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v > 120) {
              _next(n);
            } else if (v < -120) {
              _previous(n);
            }
          },
          child: SizedBox(
            height: _cardHeight + _peek * 2,
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final t = _t.value;
                return Stack(clipBehavior: Clip.none, children: [
                  // Back to front.
                  for (var d = behind; d >= 0; d--) _placed(items[(front + d) % n], d, t, n),
                ]);
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget _placed(Map<String, dynamic> a, int d, double t, int n) {
    double x = 0, turn = 0, y, scale, opacity, shade;
    if (d == 0) {
      // The front card slides sideways (the swipe's direction) with a slight
      // tilt and fades, while the next one takes its place.
      x = _dir * t * 160;
      turn = _dir * t * .06;
      y = _peek * 2 + t * 12;
      scale = 1 - .04 * t;
      opacity = (1 - t * 1.3).clamp(0.0, 1.0);
      shade = 0;
    } else {
      final e = d - t; // where it's heading: one step forward
      y = _peek * 2 - e * _peek;
      scale = 1 - e * .05;
      shade = e * .07;
      // The deepest card fades in as it joins the visible stack.
      opacity = d == _depth ? t : 1;
    }
    final full = d <= 1; // only the front card and the next one need content
    return Positioned(
      left: 0,
      right: 0,
      top: y,
      height: _cardHeight,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(x, 0),
          child: Transform.rotate(
            angle: turn,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: _ActivityCard(
                key: ValueKey('${a['id']}'),
                a: a,
                shade: shade,
                showContent: full,
                onNext: () => _next(n),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.a, required this.shade, required this.showContent, required this.onNext, super.key});
  final Map<String, dynamic> a;
  final double shade;
  final bool showContent;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(_card, _cardBehind, (shade * 7).clamp(0.0, 1.0))!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: PhlioColors.border),
      ),
      child: showContent ? _content(context) : const SizedBox.expand(),
    );
  }

  Widget _content(BuildContext context) {
    final author = (a['author'] as Map?) ?? const {};
    final name = '${author['display_name'] ?? author['username'] ?? 'Someone'}';
    final sport = sportOf(a['sport'] as String?);
    final dist = (a['distance_m'] as num?) ?? 0;
    final moving = (a['moving_s'] as num?) ?? (a['elapsed_s'] as num?) ?? 0;
    final faces = [for (final p in (a['kudos_people'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
    final kudos = (a['kudos_count'] as num?)?.toInt() ?? 0;
    final description = '${a['description'] ?? ''}'.trim();

    final elevation = (a['elevation_m'] as num?) ?? 0;
    final calories = (a['calories'] as num?) ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
              decoration: BoxDecoration(color: _chip, borderRadius: BorderRadius.circular(30)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                PhlioAvatar(name: name, imageUrl: author['avatar_url'] as String?, profileId: author['id'] as String?, size: 36),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.bodyStrong.copyWith(color: _ink)),
                ),
              ]),
            ),
          ),
          const Spacer(),
          _RoundButton(
            color: _chip,
            size: 44,
            onTap: onNext,
            tooltip: 'Next activity',
            child: const Icon(Icons.unfold_more_rounded, color: _ink, size: 22),
          ),
        ]),
        const SizedBox(height: 10),
        // Everything between the header and the footer scrolls when it
        // doesn't fit (long titles, descriptions, extra stats).
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['title'] ?? ''}',
                    style: PhlioTypography.headline.copyWith(color: _ink, fontSize: 24, height: 1.2, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${sport.label} · ${_when(a['started_at'] as String?)}',
                    style: PhlioTypography.caption.copyWith(color: moveAccent, fontWeight: FontWeight.w700)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(description, style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary, height: 1.35)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Chip(
                      icon: sport.icon,
                      accent: true,
                      text: sport.distance && dist > 0 ? '${(dist / 1000).toStringAsFixed(1)} km' : sport.label),
                  _Chip(icon: Icons.schedule_rounded, text: _span(a['started_at'] as String?, a['elapsed_s'] as num? ?? moving)),
                  _Chip(icon: Icons.timer_outlined, text: fmtShortDuration(moving)),
                  if (sport.distance && dist > 0)
                    _Chip(
                      icon: Icons.speed_rounded,
                      text: sport.pace ? '${fmtPace(a['pace_s_per_km'] as num?)} /km' : '${a['speed_kmh'] ?? 0} km/h',
                    ),
                  if (elevation > 0) _Chip(icon: Icons.terrain_rounded, text: '${elevation.round()} m climb'),
                  if (calories > 0) _Chip(icon: Icons.local_fire_department_outlined, text: '${calories.round()} kcal'),
                ]),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          if (faces.isEmpty)
            Text('Be the first to give kudos', style: PhlioTypography.caption.copyWith(color: _inkSoft))
          else
            _Faces(faces: faces, extra: kudos - faces.length),
          const Spacer(),
          _RoundButton(
            color: moveAccent,
            size: 52,
            tooltip: 'Open activity',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context, rootNavigator: true)
                  .push(moveActivityRoute('${a['id']}', heroImage: a['image_url'] as String?));
            },
            child: const Icon(Icons.north_east_rounded, color: PhlioColors.textOnBrand, size: 24),
          ),
        ]),
      ]),
    );
  }

  static String _clock(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _span(String? iso, num seconds) {
    final start = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (start == null) return fmtShortDuration(seconds);
    return '${_clock(start)} – ${_clock(start.add(Duration(seconds: seconds.round())))}';
  }

  static String _when(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.accent = false});
  final IconData icon;
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _chip, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: accent ? moveAccent : PhlioColors.textSecondary),
          const SizedBox(width: 6),
          Text(text, style: PhlioTypography.caption.copyWith(color: _ink, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Faces extends StatelessWidget {
  const _Faces({required this.faces, required this.extra});
  final List<Map<String, dynamic>> faces;
  final int extra;

  @override
  Widget build(BuildContext context) {
    const size = 40.0, step = 28.0;
    final count = faces.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: step * (count - 1) + size,
      height: size,
      child: Stack(children: [
        for (final (i, p) in faces.indexed)
          Positioned(
            left: i * step,
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _card, width: 2.5)),
              child: PhlioAvatar(
                name: '${p['display_name'] ?? p['username'] ?? '?'}',
                imageUrl: p['avatar_url'] as String?,
                size: size - 5,
                showMomentRing: false,
              ),
            ),
          ),
        if (extra > 0)
          Positioned(
            left: faces.length * step,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _chip, shape: BoxShape.circle, border: Border.all(color: _card, width: 2.5)),
              child: Text('+$extra', style: PhlioTypography.caption.copyWith(color: _ink, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.color, required this.onTap, required this.child, required this.tooltip, this.size = 48});
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Center(child: child)),
          ),
        ),
      );
}
