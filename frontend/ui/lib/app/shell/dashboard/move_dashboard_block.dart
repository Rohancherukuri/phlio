// Phlio Move in the profile dashboard (Foxy tab): goal rings that fill in,
// a per-day bar chart you can tap or drag across, sports you did, your
// bests, recent activities, and shortcuts to record or open Phlio Move.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/colors.dart';
import '../../../features/phlio_agent/presentation/screens/move/move_activity_screen.dart' show moveActivityRoute;
import '../../../features/phlio_agent/presentation/screens/move/move_api.dart';
import '../../../features/phlio_agent/presentation/screens/move/move_home_screen.dart';
import '../../../features/phlio_agent/presentation/screens/move/move_record_screen.dart';

class MoveDashboardBlock extends StatefulWidget {
  const MoveDashboardBlock({required this.move, super.key});
  final Map<String, dynamic> move;

  @override
  State<MoveDashboardBlock> createState() => _MoveDashboardBlockState();
}

class _MoveDashboardBlockState extends State<MoveDashboardBlock> {
  int? _day; // selected bar
  String? _sport; // highlighted sport

  Map<String, dynamic> get m => widget.move;

  void _open(Map a) {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(moveActivityRoute('${a['id']}', heroImage: a['image_url'] as String?));
  }

  @override
  Widget build(BuildContext context) {
    final days = ((m['days'] as List?) ?? const []).cast<Map>();
    final weeks = math.max(1, (days.length / 7).round());
    final distance = ((m['distance_m'] as num?) ?? 0).toDouble();
    final moving = ((m['moving_s'] as num?) ?? 0).toDouble();
    final count = ((m['count'] as num?) ?? 0).toInt();
    // Gentle weekly goals: 10 km, 150 active minutes (WHO), 3 sessions.
    final rings = [
      (label: 'Distance', value: '${fmtKm(distance)} km', frac: distance / (10000.0 * weeks), color: moveAccent),
      (label: 'Active time', value: fmtShortDuration(moving), frac: moving / (150 * 60.0 * weeks), color: PhlioColors.success),
      (label: 'Sessions', value: '$count', frac: count / (3.0 * weeks), color: PhlioColors.brandViolet),
    ];
    final sports = ((m['sports'] as List?) ?? const []).cast<Map>();
    final recent = ((m['recent'] as List?) ?? const []).cast<Map>();
    final longest = m['longest'] as Map?;
    final fastest = m['fastest'] as Map?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: moveAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.directions_run_rounded, color: moveAccent),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Phlio Move', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (((m['streak_days'] as num?) ?? 0) > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: moveAccent.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_fire_department_rounded, size: 15, color: moveAccent),
                const SizedBox(width: 4),
                Text('${m['streak_days']} day streak', style: const TextStyle(color: moveAccent, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
        ]),
        const SizedBox(height: 18),
        // Goal rings.
        Row(children: [
          for (final r in rings)
            Expanded(
              child: Column(children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: r.frac.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, __) => CustomPaint(
                      painter: _Ring(t, r.color),
                      child: Center(
                        child: Text('${(t * 100).round()}%',
                            style: TextStyle(color: r.color, fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(r.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(r.label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Goals: 10 km, 150 active minutes and 3 sessions a week.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .38), fontSize: 11.5)),
        ),
        const SizedBox(height: 18),
        // Day bars (tap or drag).
        _DayBars(days: days, selected: _day, onSelect: (i) => setState(() => _day = i)),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            key: ValueKey(_day),
            _day == null ? 'Tap a day to see it' : _dayLine(days[_day!]),
            textAlign: TextAlign.center,
            style: TextStyle(color: _day == null ? Colors.white38 : Colors.white, fontSize: 13, fontWeight: _day == null ? FontWeight.w500 : FontWeight.w700),
          ),
        ),
        if (sports.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('What you did', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
          const SizedBox(height: 8),
          for (final s in sports) _SportRow(s: s, total: count, selected: _sport == s['sport'], onTap: () => setState(() => _sport = _sport == s['sport'] ? null : '${s['sport']}')),
        ],
        if (longest != null || fastest != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            if (longest != null)
              Expanded(child: _Best(icon: Icons.straighten_rounded, label: 'Longest', value: '${fmtKm(longest['distance_m'] as num)} km', title: '${longest['title']}', onTap: () => _open(longest))),
            if (longest != null && fastest != null) const SizedBox(width: 10),
            if (fastest != null)
              Expanded(child: _Best(icon: Icons.speed_rounded, label: 'Fastest pace', value: '${fmtPace(fastest['pace_s_per_km'] as num?)} /km', title: '${fastest['title']}', onTap: () => _open(fastest))),
          ]),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Recent', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
          const SizedBox(height: 4),
          for (final a in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              onTap: () => _open(a),
              leading: CircleAvatar(
                backgroundColor: moveAccent.withValues(alpha: .14),
                child: Icon(sportOf(a['sport'] as String?).icon, color: moveAccent, size: 20),
              ),
              title: Text('${a['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${((a['distance_m'] as num?) ?? 0) > 0 ? '${fmtKm(a['distance_m'] as num)} km · ' : ''}${fmtShortDuration((a['moving_s'] as num?) ?? 0)} · ${fmtWhen('${a['started_at']}').split(' · ').first}',
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.insights_rounded),
              label: const Text('Open Move'),
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute<void>(builder: (_) => const MoveHomeScreen())),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: moveAccent, foregroundColor: Colors.white),
              icon: const Icon(Icons.radio_button_checked_rounded),
              label: const Text('Record'),
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute<void>(builder: (_) => const MoveRecordScreen())),
            ),
          ),
        ]),
      ]),
    );
  }

  String _dayLine(Map d) {
    final date = DateTime.tryParse('${d['date']}');
    const wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final when = date == null ? '' : '${wk[date.weekday - 1]} ${date.day}/${date.month}';
    final n = (d['count'] as num?) ?? 0;
    if (n == 0) return '$when · rest day';
    final dist = (d['distance_m'] as num?) ?? 0;
    return '$when · ${dist > 0 ? '${fmtKm(dist)} km · ' : ''}${fmtShortDuration((d['moving_s'] as num?) ?? 0)} · $n activit${n == 1 ? 'y' : 'ies'}';
  }
}

class _Ring extends CustomPainter {
  _Ring(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = color.withValues(alpha: .14));
    if (t <= 0) return;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * t, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color);
  }

  @override
  bool shouldRepaint(_Ring old) => old.t != t || old.color != color;
}

class _DayBars extends StatelessWidget {
  const _DayBars({required this.days, required this.selected, required this.onSelect});
  final List<Map> days;
  final int? selected;
  final ValueChanged<int?> onSelect;

  double _value(Map d) {
    final dist = ((d['distance_m'] as num?) ?? 0).toDouble();
    // Distance when there is any; otherwise minutes (gym days still show).
    return dist > 0 ? dist / 1000 : ((d['moving_s'] as num?) ?? 0) / 600;
  }

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final hi = days.map(_value).fold<double>(0, math.max);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth / days.length;
      void at(Offset p) {
        final i = (p.dx / w).floor().clamp(0, days.length - 1);
        if (i != selected) HapticFeedback.selectionClick();
        onSelect(i);
      }

      return GestureDetector(
        onTapDown: (d) => at(d.localPosition),
        onHorizontalDragUpdate: (d) => at(d.localPosition),
        child: SizedBox(
          height: 110,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: days.length > 14 ? 1 : 3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: hi == 0 ? 0 : _value(d) / hi),
                    duration: Duration(milliseconds: 500 + 25 * i),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, __) => AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: math.max(4.0, 96 * t),
                      decoration: BoxDecoration(
                        color: (d['count'] as num? ?? 0) == 0
                            ? Colors.white.withValues(alpha: .08)
                            : moveAccent.withValues(alpha: selected == null || selected == i ? 1 : .35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _SportRow extends StatelessWidget {
  const _SportRow({required this.s, required this.total, required this.selected, required this.onTap});
  final Map s;
  final int total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sport = sportOf(s['sport'] as String?);
    final n = (s['count'] as num).toInt();
    final frac = total == 0 ? 0.0 : n / total;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(sport.icon, size: 18, color: selected ? moveAccent : Colors.white70),
            const SizedBox(width: 8),
            Expanded(child: Text('${s['label']}', style: TextStyle(fontWeight: FontWeight.w700, color: selected ? moveAccent : Colors.white))),
            Text('$n', style: const TextStyle(color: Colors.white60)),
          ]),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: frac),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, t, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: t, minHeight: 6, color: moveAccent, backgroundColor: Colors.white.withValues(alpha: .08)),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${((s['distance_m'] as num?) ?? 0) > 0 ? '${fmtKm(s['distance_m'] as num)} km · ' : ''}${fmtShortDuration((s['moving_s'] as num?) ?? 0)} in total',
                      style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}

class _Best extends StatelessWidget {
  const _Best({required this.icon, required this.label, required this.value, required this.title, required this.onTap});
  final IconData icon;
  final String label, value, title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PhlioColors.surfaceInput,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: moveAccent),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ),
      );
}
