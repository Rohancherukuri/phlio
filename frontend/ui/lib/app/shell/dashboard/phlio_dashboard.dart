// The all-in-one dashboard: every Phlio platform, not just Social.
//
// GET /profile/dashboard (backend/app/api/v1/dashboard.py) returns an
// overview plus one section per platform — Social (with your DMs), Pay, Rooms,
// Stream, News, Shop, Book, Foxy (the Agent) — all in the same shape, so one set of widgets
// draws them all:
//
//   [DashboardTabs]     platform chips in each platform's colour; the
//                       selected one fills in and the content cross-fades
//   [DashboardOverview] "Your Phlio": total activity counting up, an
//                       active-days ring, the Phlio mix donut (tap a slice),
//                       a stacked day-by-day chart (drag to scrub), a card
//                       per platform with its sparkline (tap to open it) and
//                       plain-language takeaways
//   [DashboardSection]  a platform: headline number, takeaways, KPI tiles,
//                       a drawn-in chart with toggles and scrubbing, a
//                       breakdown donut / bars, top people or items — and for
//                       Pay the full money picture: in vs out, net flow and
//                       savings rate, biggest payment, spending by weekday and
//                       hour, open bill splits
//
// Everything animates in (count-ups, staggered reveals, growing bars) so the
// numbers read as a story rather than a table.

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../design_system/colors.dart';
import '../../../shared/notifications/notification_center.dart' show NotifPlatform;
import '../../../shared/pay/phlio_currency.dart';
import '../../config/app_config.dart';

final phlioDashboardProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, days) async {
  final res = await getIt<ApiClient>().dio.get('/profile/dashboard', queryParameters: {'days': days});
  return (res.data as Map).cast<String, dynamic>();
});

// -- look ----------------------------------------------------------------------------------------

/// Colour and icon for a dashboard tab (same as the notification badges).
NotifPlatform dashStyle(String id) => switch (id) {
      'all' => const NotifPlatform('all', 'All', Icons.dashboard_rounded, Color(0xFFFFB58F), Color(0xFF8D78FF)),
      'messages' => NotifPlatform.of('dm'),
      _ => NotifPlatform.of(id),
    };

const _tabs = ['all', 'social', 'pay', 'rooms', 'stream', 'news', 'shop', 'book', 'agent'];
const _tabLabels = {
  'all': 'All',
  'social': 'Social',
  'pay': 'Pay',
  'rooms': 'Rooms',
  'stream': 'Stream',
  'news': 'News',
  'shop': 'Shop',
  'book': 'Book',
  'agent': 'Foxy',
};

/// A second colour for two-line charts (in vs out, sent vs received…).
Color _partner(Color c) => HSLColor.fromColor(c).withHue((HSLColor.fromColor(c).hue + 150) % 360).withLightness(.62).toColor();

const _cardRadius = 22.0;

BoxDecoration _card([Color? glow]) => BoxDecoration(
      color: PhlioColors.surface,
      borderRadius: BorderRadius.circular(_cardRadius),
      border: Border.all(color: Colors.white.withValues(alpha: .06)),
      gradient: glow == null
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [glow.withValues(alpha: .16), PhlioColors.surface, PhlioColors.surface],
            ),
    );

String fmtValue(num value, String format, PhlioCurrency currency, {bool compact = false}) {
  if (format == 'money') {
    if (compact && value.abs() >= 100000 * 100) {
      return '${currency.symbol}${_compact(value / 100)}';
    }
    final text = currency.format(value.abs().round());
    return value < 0 ? '−$text' : text;
  }
  if (format == 'percent') return '${value.toStringAsFixed(0)}%';
  return compact || value >= 10000 ? _compact(value) : value.round().toString();
}

String _compact(num v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e7) return '$sign${(a / 1e7).toStringAsFixed(a >= 1e8 ? 0 : 1)}Cr';
  if (a >= 1e5 && a < 1e6) return '$sign${(a / 1e3).toStringAsFixed(0)}K';
  if (a >= 1e6) return '$sign${(a / 1e6).toStringAsFixed(1)}M';
  if (a >= 1e3) return '$sign${(a / 1e3).toStringAsFixed(1)}K';
  return '$sign${a.round()}';
}

// -- small animated pieces ---------------------------------------------------------------------------

/// Fades and slides its child in, [index] steps after the first.
class Reveal extends StatelessWidget {
  const Reveal({required this.index, required this.child, super.key});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 420 + 70 * index.clamp(0, 10)),
        curve: Curves.easeOutCubic,
        builder: (_, t, c) => Opacity(
          opacity: (t * 1.4 - .4 * (index.clamp(0, 10) / 10)).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: c),
        ),
        child: child,
      );
}

/// A number that counts up to [value].
class CountUp extends StatelessWidget {
  const CountUp({required this.value, required this.format, required this.currency, this.style, this.compact = false, super.key});
  final num value;
  final String format;
  final PhlioCurrency currency;
  final TextStyle? style;
  final bool compact;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey('$value$format'),
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(fmtValue(v, format, currency, compact: compact), style: style),
      );
}

class ChangeChip extends StatelessWidget {
  const ChangeChip(this.change, {this.inverse = false, super.key});
  final num? change;

  /// For spending: going up is not "good".
  final bool inverse;
  @override
  Widget build(BuildContext context) {
    final c = change;
    if (c == null) return const SizedBox.shrink();
    final up = c >= 0;
    final good = inverse ? !up : up;
    final color = c.abs() < 3 ? Colors.white54 : (good ? const Color(0xFF3DD6A0) : const Color(0xFFFF6B7A));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: color),
        const SizedBox(width: 2),
        Text('${c.abs().toStringAsFixed(c.abs() < 10 ? 1 : 0)}%',
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

// -- tabs --------------------------------------------------------------------------------------------

class DashboardTabs extends StatelessWidget {
  const DashboardTabs({required this.selected, required this.onChanged, super.key});
  final String selected;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: _tabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final id = _tabs[i];
            final s = dashStyle(id);
            final on = id == selected;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(id);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: on ? s.gradient : null,
                  color: on ? null : Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: on ? [BoxShadow(color: s.color.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 4))] : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(s.icon, size: 16, color: on ? Colors.white : s.color),
                  const SizedBox(width: 6),
                  Text(_tabLabels[id]!,
                      style: TextStyle(color: on ? Colors.white : Colors.white70, fontWeight: FontWeight.w800, fontSize: 13.5)),
                ]),
              ),
            );
          },
        ),
      );
}

// -- overview ------------------------------------------------------------------------------------------

class DashboardOverview extends StatelessWidget {
  const DashboardOverview({required this.data, required this.onOpen, super.key});
  final Map<String, dynamic> data;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final ov = (data['overview'] as Map).cast<String, dynamic>();
    final days = data['days'] as int;
    final sections = {for (final s in (data['sections'] as List).cast<Map>()) '${s['id']}': s.cast<String, dynamic>()};
    final mix = (ov['mix'] as List).cast<Map>();
    final fav = ov['favourite'] as String?;
    final series = (ov['series'] as Map).cast<String, dynamic>();
    final inr = currencyByCode('INR');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Reveal(
        index: 0,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _card(fav == null ? const Color(0xFFFFB58F) : dashStyle(fav).color),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Phlio · last $days days', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 6),
                CountUp(
                    value: ov['total'] as num,
                    format: 'count',
                    currency: inr,
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
                const Text('things you did across Phlio', style: TextStyle(color: Colors.white70)),
                if (fav != null) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(dashStyle(fav).icon, size: 16, color: dashStyle(fav).color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Most used: ${_tabLabels[fav]}',
                          style: TextStyle(color: dashStyle(fav).color, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ],
              ]),
            ),
            _Ring(value: (ov['active_days'] as num).toDouble(), max: days.toDouble(), label: 'active\ndays'),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Reveal(
        index: 1,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _Title('Your Phlio mix'),
            Donut(
              items: [for (final m in mix) DonutItem('${m['label']}', (m['value'] as num).toDouble(), dashStyle('${m['id']}').color, id: '${m['id']}')],
              format: 'count',
              currency: inr,
              centerCaption: 'actions',
              onOpen: onOpen,
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Reveal(
        index: 2,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _Title('Day by day', trailing: Text('drag to explore', style: TextStyle(color: Colors.white38, fontSize: 12))),
            StackedBars(
              keys: [for (final k in (series['keys'] as List).cast<Map>()) '${k['id']}'],
              days: (series['days'] as List).cast<Map>(),
              colorOf: (k) => dashStyle(k).color,
              labelOf: (k) => _tabLabels[k] ?? k,
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      const _Title('Every platform'),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 640 ? 3 : 2;
        final w = (box.maxWidth - (cols - 1) * 12) / cols;
        final heads = (ov['headlines'] as List).cast<Map>();
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (i, h) in heads.indexed)
            SizedBox(
              width: w,
              child: Reveal(index: 3 + i, child: _PlatformCard(head: h.cast<String, dynamic>(), section: sections['${h['id']}'], onTap: () => onOpen('${h['id']}'))),
            ),
        ]);
      }),
      if ((ov['insights'] as List).isNotEmpty) ...[
        const SizedBox(height: 18),
        _Insights(lines: (ov['insights'] as List).cast<String>(), color: const Color(0xFFFFB58F)),
      ],
    ]);
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.head, required this.section, required this.onTap});
  final Map<String, dynamic> head;
  final Map<String, dynamic>? section;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = dashStyle('${head['id']}');
    final series = section?['series'] as Map?;
    final firstKey = series == null ? null : '${((series['keys'] as List).first as Map)['id']}';
    final points = series == null
        ? const <double>[]
        : [for (final d in (series['days'] as List).cast<Map>()) ((d[firstKey] as num?) ?? 0).toDouble()];
    final has = head['has_data'] == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(_cardRadius),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: _card(s.color),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(gradient: s.gradient, borderRadius: BorderRadius.circular(10)),
                child: Icon(s.icon, color: Colors.white, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('${head['label']}', style: const TextStyle(fontWeight: FontWeight.w800))),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ]),
            const SizedBox(height: 10),
            Text('${head['metric']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CountUp(
                    value: (head['value'] as num?) ?? 0,
                    format: '${head['format']}',
                    currency: currencyByCode((head['currency'] as String?) ?? 'INR'),
                    compact: true,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: has ? Colors.white : Colors.white38),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: ChangeChip(head['change'] as num?, inverse: head['id'] == 'pay'),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: has && points.any((p) => p > 0)
                  ? Sparkline(points: points, color: s.color)
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Nothing yet', style: TextStyle(color: Colors.white.withValues(alpha: .3), fontSize: 12))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.max, required this.label});
  final double value, max;
  final String label;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: max == 0 ? 0 : value / max),
        duration: const Duration(milliseconds: 1300),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => SizedBox(
          width: 96,
          height: 96,
          child: CustomPaint(
            painter: _RingPainter(t),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(t * max).round()}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1)),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.1)),
              ]),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(6);
    canvas.drawArc(r, 0, math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..color = Colors.white.withValues(alpha: .08));
    canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * t,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(
            colors: [Color(0xFFFFB58F), Color(0xFFFF5FA2), Color(0xFF8D78FF), Color(0xFFFFB58F)],
            transform: GradientRotation(-math.pi / 2),
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

class _Insights extends StatelessWidget {
  const _Insights({required this.lines, required this.color});
  final List<String> lines;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _Title('What this means'),
        for (final (i, line) in lines.indexed)
          Reveal(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: .18)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_rounded, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(line, style: const TextStyle(height: 1.35))),
              ]),
            ),
          ),
      ]);
}

// -- a platform ------------------------------------------------------------------------------------------

class DashboardSection extends StatelessWidget {
  const DashboardSection({required this.section, required this.days, super.key});
  final Map<String, dynamic> section;
  final int days;

  @override
  Widget build(BuildContext context) {
    final id = '${section['id']}';
    final s = dashStyle(id);
    final currency = currencyByCode((section['currency'] as String?) ?? 'INR');
    final head = (section['headline'] as Map).cast<String, dynamic>();
    final kpis = (section['kpis'] as List).cast<Map>();
    final series = section['series'] as Map?;
    final breakdown = section['breakdown'] as Map?;
    final top = section['top'] as Map?;
    // More lists: top chats (Social), what Foxy found (Agent)…
    final tops = [for (final t in (section['tops'] as List? ?? const [])) t as Map];
    final insights = (section['insights'] as List).cast<String>();
    final extra = ((section['extra'] as Map?) ?? const {}).cast<String, dynamic>();
    final spend = id == 'pay';
    var i = 0;
    if (section['has_data'] != true) return _Nothing(style: s, label: '${section['label']}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Reveal(
        index: i++,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _card(s.color),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(gradient: s.gradient, borderRadius: BorderRadius.circular(16)),
              child: Icon(s.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${head['label']} · last $days days', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CountUp(
                    value: head['value'] as num,
                    format: '${head['format']}',
                    currency: currency,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                ),
              ]),
            ),
            ChangeChip(head['change'] as num?, inverse: spend),
          ]),
        ),
      ),
      if (spend) ...[const SizedBox(height: 14), Reveal(index: i++, child: _InOut(extra: extra, currency: currency))],
      const SizedBox(height: 14),
      Reveal(
        index: i++,
        child: LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth > 640 ? 3 : 2;
          final w = (box.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (n, k) in kpis.indexed)
              SizedBox(width: w, child: _KpiTile(kpi: k.cast<String, dynamic>(), currency: currency, color: s.color, index: n, inverse: spend && k['id'] == 'sent')),
          ]);
        }),
      ),
      if (insights.isNotEmpty) ...[const SizedBox(height: 16), _Insights(lines: insights, color: s.color)],
      if (series != null) ...[
        const SizedBox(height: 8),
        Reveal(
          index: i++,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _Title('Over time', trailing: Text('drag to explore', style: TextStyle(color: Colors.white38, fontSize: 12))),
              LineChart(
                keys: [for (final k in (series['keys'] as List).cast<Map>()) (id: '${k['id']}', label: '${k['label']}')],
                days: (series['days'] as List).cast<Map>(),
                colors: [s.color, _partner(s.color), Colors.white70],
                format: spend ? 'money' : 'count',
                currency: currency,
              ),
            ]),
          ),
        ),
      ],
      if (spend) ...[
        const SizedBox(height: 14),
        Reveal(index: i++, child: _PayHabits(extra: extra, currency: currency, color: s.color)),
      ],
      if (breakdown != null && (breakdown['items'] as List).any((x) => ((x as Map)['value'] as num) > 0)) ...[
        const SizedBox(height: 14),
        Reveal(
          index: i++,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Title('${breakdown['title']}'),
              _breakdown(breakdown, s.color, currency),
            ]),
          ),
        ),
      ],
      if (top != null && (top['items'] as List).isNotEmpty) ...[
        const SizedBox(height: 14),
        Reveal(
          index: i++,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Title('${top['title']}'),
              _TopList(items: (top['items'] as List).cast<Map>(), color: s.color, currency: currency),
            ]),
          ),
        ),
      ],
      for (final t in tops)
        if ((t['items'] as List).isNotEmpty) ...[
          const SizedBox(height: 14),
          Reveal(
            index: i++,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: _card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Title('${t['title']}'),
                _TopList(items: (t['items'] as List).cast<Map>(), color: _partner(s.color), currency: currency),
              ]),
            ),
          ),
        ],
    ]);
  }

  Widget _breakdown(Map breakdown, Color color, PhlioCurrency currency) {
    final items = [for (final x in (breakdown['items'] as List).cast<Map>()) if ((x['value'] as num) > 0) x];
    final palette = _palette(color, items.length);
    if (items.length <= 6) {
      return Donut(
        items: [for (final (n, x) in items.indexed) DonutItem('${x['label']}', (x['value'] as num).toDouble(), palette[n])],
        format: '${breakdown['format']}',
        currency: currency,
        centerCaption: 'total',
      );
    }
    return BarList(
      items: [for (final x in items) (label: '${x['label']}', value: (x['value'] as num).toDouble())],
      color: color,
      format: '${breakdown['format']}',
      currency: currency,
    );
  }
}

List<Color> _palette(Color base, int n) {
  final h = HSLColor.fromColor(base);
  return [
    for (var i = 0; i < math.max(n, 1); i++)
      h.withHue((h.hue + i * (300 / math.max(n, 1))) % 360).withSaturation(.72).withLightness(i == 0 ? .64 : .6).toColor(),
  ];
}

class _Nothing extends StatelessWidget {
  const _Nothing({required this.style, required this.label});
  final NotifPlatform style;
  final String label;
  @override
  Widget build(BuildContext context) => Reveal(
        index: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: _card(style.color),
          child: Column(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(gradient: style.gradient, borderRadius: BorderRadius.circular(20)),
              child: Icon(style.icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 14),
            Text('No $label activity yet', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Use $label and your stats show up here, with charts and takeaways.',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
          ]),
        ),
      );
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.kpi, required this.currency, required this.color, required this.index, this.inverse = false});
  final Map<String, dynamic> kpi;
  final PhlioCurrency currency;
  final Color color;
  final int index;
  final bool inverse;
  @override
  Widget build(BuildContext context) => Reveal(
        index: index,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: _card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${kpi['label']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUp(
                value: kpi['value'] as num,
                format: '${kpi['format']}',
                currency: currency,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: kpi['id'] == 'net' ? ((kpi['value'] as num) >= 0 ? const Color(0xFF3DD6A0) : const Color(0xFFFF6B7A)) : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 20,
              child: kpi['change'] != null
                  ? Align(alignment: Alignment.centerLeft, child: ChangeChip(kpi['change'] as num?, inverse: inverse))
                  : kpi['hint'] != null
                      ? Text('${kpi['hint']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 11.5))
                      : null,
            ),
          ]),
        ),
      );
}

// -- Pay -------------------------------------------------------------------------------------------------

/// Money in vs money out, one bar split in two, plus the net and savings rate.
class _InOut extends StatelessWidget {
  const _InOut({required this.extra, required this.currency});
  final Map<String, dynamic> extra;
  final PhlioCurrency currency;
  @override
  Widget build(BuildContext context) {
    final io = ((extra['in_out'] as Map?) ?? const {}).cast<String, dynamic>();
    final sent = ((io['sent'] as num?) ?? 0).toDouble();
    final received = ((io['received'] as num?) ?? 0).toDouble();
    final total = sent + received;
    final rate = extra['savings_rate'] as num?;
    const inColor = Color(0xFF3DD6A0), outColor = Color(0xFFFF8A65);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _Title('Money in vs out'),
        Row(children: [
          Expanded(child: _money('In', received, inColor, Icons.south_west_rounded)),
          Expanded(child: _money('Out', sent, outColor, Icons.north_east_rounded)),
        ]),
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: total == 0 ? .5 : received / total),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(children: [
                Expanded(flex: math.max(1, (t * 1000).round()), child: const ColoredBox(color: inColor)),
                const SizedBox(width: 3),
                Expanded(flex: math.max(1, ((1 - t) * 1000).round()), child: const ColoredBox(color: outColor)),
              ]),
            ),
          ),
        ),
        if (rate != null) ...[
          const SizedBox(height: 12),
          Text(
            rate >= 0
                ? 'You kept ${rate.toStringAsFixed(0)}% of the money that came in.'
                : 'You spent ${(-rate).toStringAsFixed(0)}% more than came in.',
            style: TextStyle(color: rate >= 0 ? inColor : outColor, fontWeight: FontWeight.w700),
          ),
        ],
      ]),
    );
  }

  Widget _money(String label, double v, Color color, IconData icon) => Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: .15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUp(value: v, format: 'money', currency: currency, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            ),
          ]),
        ),
      ]);
}

/// When you spend: by weekday, by hour, the biggest payment and open splits.
class _PayHabits extends StatelessWidget {
  const _PayHabits({required this.extra, required this.currency, required this.color});
  final Map<String, dynamic> extra;
  final PhlioCurrency currency;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final weekday = ((extra['weekday'] as List?) ?? const []).cast<Map>();
    final hours = [for (final h in (extra['hours'] as List? ?? const [])) (h as num).toDouble()];
    final biggest = extra['biggest'] as Map?;
    final split = (extra['split'] as Map?) ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Title('When you spend'),
          ColumnBars(
            items: [for (final w in weekday) (label: '${w['label']}', value: (w['value'] as num).toDouble())],
            color: color,
            format: 'money',
            currency: currency,
          ),
          if (hours.any((h) => h > 0)) ...[
            const SizedBox(height: 18),
            const Text('By hour of day', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
            const SizedBox(height: 8),
            HourStrip(hours: hours, color: color),
          ],
        ]),
      ),
      if (biggest != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(color),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withValues(alpha: .18), shape: BoxShape.circle),
              child: Icon(Icons.emoji_events_rounded, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(biggest['type'] == 'sent' ? 'Biggest payment' : 'Biggest amount received',
                    style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                Text(currency.format((biggest['amount'] as num).round()),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                Text(
                  [
                    if (biggest['type'] == 'sent') 'to ${biggest['counterparty']}' else 'from ${biggest['counterparty']}',
                    if ('${biggest['note'] ?? ''}'.isNotEmpty) '“${biggest['note']}”',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ]),
            ),
          ]),
        ),
      ],
      if (((split['open'] as num?) ?? 0) > 0) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(),
          child: Row(children: [
            const Icon(Icons.call_split_rounded, color: Color(0xFF8D78FF)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${split['open']} open bill split${split['open'] == 1 ? '' : 's'} · '
                '${currency.format(((split['owed_to_you'] as num?) ?? 0).round())} still to come back to you',
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

// -- charts --------------------------------------------------------------------------------------------------

class DonutItem {
  const DonutItem(this.label, this.value, this.color, {this.id});
  final String label;
  final double value;
  final Color color;
  final String? id;
}

/// An animated donut: slices sweep in; tap a slice (or its legend row) to
/// focus it; with [onOpen] a second tap opens that platform.
class Donut extends StatefulWidget {
  const Donut({required this.items, required this.format, required this.currency, this.centerCaption = '', this.onOpen, super.key});
  final List<DonutItem> items;
  final String format, centerCaption;
  final PhlioCurrency currency;
  final ValueChanged<String>? onOpen;
  @override
  State<Donut> createState() => _DonutState();
}

class _DonutState extends State<Donut> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  int? _focus;

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  void _tap(int? i) {
    HapticFeedback.selectionClick();
    if (i != null && i == _focus && widget.onOpen != null && widget.items[i].id != null) {
      widget.onOpen!(widget.items[i].id!);
      return;
    }
    setState(() => _focus = i == _focus ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final total = items.fold<double>(0, (a, b) => a + b.value);
    final shown = _focus == null ? null : items[_focus!];
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 420;
      final size = math.min(190.0, box.maxWidth * (wide ? .45 : .62));
      final chart = SizedBox.square(
        dimension: size,
        child: GestureDetector(
          onTapUp: (d) {
            if (total == 0) return;
            final c = Offset(size / 2, size / 2);
            final v = d.localPosition - c;
            final r = v.distance;
            if (r < size * .28 || r > size / 2) return _tap(null);
            var a = math.atan2(v.dy, v.dx) + math.pi / 2;
            if (a < 0) a += math.pi * 2;
            var acc = 0.0;
            for (var i = 0; i < items.length; i++) {
              acc += items[i].value / total * math.pi * 2;
              if (a <= acc) return _tap(i);
            }
          },
          child: AnimatedBuilder(
            animation: _in,
            builder: (_, __) => CustomPaint(
              painter: _DonutPainter(items, total, Curves.easeOutCubic.transform(_in.value), _focus),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Column(
                    key: ValueKey(_focus),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fmtValue(shown?.value ?? total, widget.format, widget.currency, compact: true),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: shown?.color ?? Colors.white),
                      ),
                      Text(
                        shown == null ? widget.centerCaption : '${shown.label} · ${total == 0 ? 0 : (shown.value * 100 / total).round()}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final legend = Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (i, it) in items.indexed)
          if (it.value > 0 || widget.onOpen != null)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _tap(i),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _focus == null || _focus == i ? 1 : .4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: it.color, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(fmtValue(it.value, widget.format, widget.currency, compact: true),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
      ]);
      if (wide) {
        return Row(children: [chart, const SizedBox(width: 20), Expanded(child: legend)]);
      }
      return Column(children: [chart, const SizedBox(height: 14), legend]);
    });
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.items, this.total, this.t, this.focus);
  final List<DonutItem> items;
  final double total, t;
  final int? focus;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    if (total == 0) {
      canvas.drawCircle(c, radius - 9, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..color = Colors.white.withValues(alpha: .07));
      return;
    }
    var start = -math.pi / 2;
    final sweepAll = math.pi * 2 * t;
    for (var i = 0; i < items.length; i++) {
      final sweep = items[i].value / total * sweepAll;
      if (sweep <= 0) continue;
      final focused = focus == i;
      final w = focused ? 26.0 : 18.0;
      final gap = items.where((x) => x.value > 0).length > 1 ? .025 : 0.0;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius - 9 + (focused ? 4 : 0)),
        start + gap,
        math.max(0.001, sweep - gap * 2),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.butt
          ..color = focus == null || focused ? items[i].color : items[i].color.withValues(alpha: .35),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.t != t || old.focus != focus || old.items != items;
}

/// Tiny trend line for platform cards.
class Sparkline extends StatelessWidget {
  const Sparkline({required this.points, required this.color, super.key});
  final List<double> points;
  final Color color;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(size: Size.infinite, painter: _SparkPainter(points, color, t)),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color, this.t);
  final List<double> points;
  final Color color;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final hi = points.reduce(math.max);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height - (hi == 0 ? 0 : points[i] / hi) * (size.height - 3) - 1.5;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, -4, size.width * t, size.height + 8));
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .35), color.withValues(alpha: 0)])
              .createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t || old.points != points;
}

typedef SeriesKey = ({String id, String label});

/// Smooth lines with soft fills that draw in from the left. Tap a legend
/// chip to hide / show a line; drag across to read any day.
class LineChart extends StatefulWidget {
  const LineChart({required this.keys, required this.days, required this.colors, required this.format, required this.currency, super.key});
  final List<SeriesKey> keys;
  final List<Map> days;
  final List<Color> colors;
  final String format;
  final PhlioCurrency currency;
  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..forward();
  final _hidden = <String>{};
  int? _at;

  @override
  void didUpdateWidget(LineChart old) {
    super.didUpdateWidget(old);
    if (old.days != widget.days) _draw.forward(from: 0);
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _scrub(Offset p, double width) {
    final n = widget.days.length;
    if (n == 0) return;
    final i = ((p.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _at) HapticFeedback.selectionClick();
    setState(() => _at = i);
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.keys;
    final visible = [for (final (i, k) in keys.indexed) if (!_hidden.contains(k.id)) (i, k)];
    final at = _at;
    final day = at == null ? null : widget.days[at];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final (i, k) in keys.indexed)
          GestureDetector(
            onTap: () => setState(() => _hidden.contains(k.id) ? _hidden.remove(k.id) : (_hidden.length < keys.length - 1 ? _hidden.add(k.id) : null)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _hidden.contains(k.id) ? Colors.transparent : widget.colors[i % widget.colors.length].withValues(alpha: .15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.colors[i % widget.colors.length].withValues(alpha: _hidden.contains(k.id) ? .3 : .6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.colors[i % widget.colors.length], shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(k.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _hidden.contains(k.id) ? Colors.white38 : Colors.white)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 44,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: day == null
              ? Align(
                  key: const ValueKey('total'),
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 16, children: [
                    for (final (i, k) in visible)
                      _legendValue(k.label, widget.days.fold<num>(0, (a, d) => a + ((d[k.id] as num?) ?? 0)), widget.colors[i % widget.colors.length], 'Total '),
                  ]),
                )
              : Align(
                  key: ValueKey(at),
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.end, children: [
                    Text(_day('${day['day']}'), style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                    for (final (i, k) in visible) _legendValue(k.label, (day[k.id] as num?) ?? 0, widget.colors[i % widget.colors.length], ''),
                  ]),
                ),
        ),
      ),
      LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onHorizontalDragStart: (d) => _scrub(d.localPosition, box.maxWidth),
          onHorizontalDragUpdate: (d) => _scrub(d.localPosition, box.maxWidth),
          onHorizontalDragEnd: (_) => setState(() => _at = null),
          onTapDown: (d) => _scrub(d.localPosition, box.maxWidth),
          onTapUp: (_) => Future<void>.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) setState(() => _at = null);
          }),
          child: AnimatedBuilder(
            animation: _draw,
            builder: (_, __) => CustomPaint(
              size: Size(box.maxWidth, 170),
              painter: _LinePainter(
                lines: [
                  for (final (i, k) in visible)
                    (color: widget.colors[i % widget.colors.length], values: [for (final d in widget.days) ((d[k.id] as num?) ?? 0).toDouble()]),
                ],
                t: Curves.easeInOutCubic.transform(_draw.value),
                at: _at,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      if (widget.days.isNotEmpty)
        Row(children: [
          Text(_day('${widget.days.first['day']}'), style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const Spacer(),
          Text(_day('${widget.days.last['day']}'), style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
    ]);
  }

  Widget _legendValue(String label, num v, Color color, String prefix) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$prefix${label.toLowerCase()}', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
          Text(fmtValue(v, widget.format, widget.currency), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      );
}

String _day(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.lines, required this.t, required this.at});
  final List<({Color color, List<double> values})> lines;
  final double t;
  final int? at;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final n = lines.isEmpty ? 0 : lines.first.values.length;
    if (n < 2) return;
    final hi = lines.expand((l) => l.values).fold<double>(0, math.max);
    double x(int i) => size.width * i / (n - 1);
    double y(double v) => size.height - (hi == 0 ? 0 : v / hi) * (size.height - 10) - 2;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, -10, size.width * t, size.height + 20));
    for (final line in lines) {
      final path = Path()..moveTo(x(0), y(line.values[0]));
      for (var i = 1; i < n; i++) {
        final px = x(i - 1), py = y(line.values[i - 1]);
        final cx = x(i), cy = y(line.values[i]);
        final mid = (px + cx) / 2;
        path.cubicTo(mid, py, mid, cy, cx, cy);
      }
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [line.color.withValues(alpha: .28), line.color.withValues(alpha: 0)],
            ).createShader(Offset.zero & size));
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = line.color);
    }
    canvas.restore();
    final i = at;
    if (i != null) {
      canvas.drawLine(Offset(x(i), 0), Offset(x(i), size.height), Paint()
        ..color = Colors.white.withValues(alpha: .35)
        ..strokeWidth = 1.2);
      for (final line in lines) {
        final p = Offset(x(i), y(line.values[i]));
        canvas.drawCircle(p, 6.5, Paint()..color = line.color.withValues(alpha: .3));
        canvas.drawCircle(p, 4, Paint()..color = line.color);
        canvas.drawCircle(p, 1.8, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.t != t || old.at != at || old.lines != lines;
}

/// One bar per day, stacked by platform, growing in; drag to read a day.
class StackedBars extends StatefulWidget {
  const StackedBars({required this.keys, required this.days, required this.colorOf, required this.labelOf, super.key});
  final List<String> keys;
  final List<Map> days;
  final Color Function(String) colorOf;
  final String Function(String) labelOf;
  @override
  State<StackedBars> createState() => _StackedBarsState();
}

class _StackedBarsState extends State<StackedBars> with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  int? _at;

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  void _scrub(Offset p, double w) {
    final n = widget.days.length;
    if (n == 0) return;
    final i = (p.dx / w * n).floor().clamp(0, n - 1);
    if (i != _at) HapticFeedback.selectionClick();
    setState(() => _at = i);
  }

  @override
  Widget build(BuildContext context) {
    final day = _at == null ? null : widget.days[_at!];
    final parts = day == null
        ? const <(String, num)>[]
        : [for (final k in widget.keys) if (((day[k] as num?) ?? 0) > 0) (k, day[k] as num)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 40,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: day == null
              ? const Align(
                  key: ValueKey('hint'),
                  alignment: Alignment.centerLeft,
                  child: Text('Each bar is a day, coloured by platform.', style: TextStyle(color: Colors.white54)),
                )
              : Align(
                  key: ValueKey(_at),
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      Text('${_day('${day['day']}')}   ', style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (parts.isEmpty) const Text('Quiet day', style: TextStyle(color: Colors.white54)),
                      for (final (k, v) in parts) ...[
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.colorOf(k), shape: BoxShape.circle)),
                        Text(' ${widget.labelOf(k)} $v   ', style: const TextStyle(fontSize: 12.5)),
                      ],
                    ]),
                  ),
                ),
        ),
      ),
      LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onHorizontalDragStart: (d) => _scrub(d.localPosition, box.maxWidth),
          onHorizontalDragUpdate: (d) => _scrub(d.localPosition, box.maxWidth),
          onTapDown: (d) => _scrub(d.localPosition, box.maxWidth),
          child: AnimatedBuilder(
            animation: _grow,
            builder: (_, __) => CustomPaint(
              size: Size(box.maxWidth, 140),
              painter: _StackPainter(widget.keys, widget.days, widget.colorOf, _grow.value, _at),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      if (widget.days.isNotEmpty)
        Row(children: [
          Text(_day('${widget.days.first['day']}'), style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const Spacer(),
          Text(_day('${widget.days.last['day']}'), style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
    ]);
  }
}

class _StackPainter extends CustomPainter {
  _StackPainter(this.keys, this.days, this.colorOf, this.t, this.at);
  final List<String> keys;
  final List<Map> days;
  final Color Function(String) colorOf;
  final double t;
  final int? at;
  @override
  void paint(Canvas canvas, Size size) {
    final n = days.length;
    if (n == 0) return;
    final totals = [for (final d in days) keys.fold<num>(0, (a, k) => a + ((d[k] as num?) ?? 0))];
    final hi = totals.fold<num>(0, (a, b) => math.max(a, b));
    final slot = size.width / n;
    final w = math.max(2.0, slot * .62);
    for (var i = 0; i < n; i++) {
      // Staggered: each bar starts growing a little after the one before.
      final local = ((t * 1.6) - i / n * .6).clamp(0.0, 1.0);
      final grow = Curves.easeOutBack.transform(local).clamp(0.0, 1.2);
      var y = size.height;
      final x = slot * i + (slot - w) / 2;
      final dim = at != null && at != i;
      if (totals[i] == 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - 3, w, 3), const Radius.circular(2)),
            Paint()..color = Colors.white.withValues(alpha: .08));
        continue;
      }
      for (final k in keys) {
        final v = ((days[i][k] as num?) ?? 0).toDouble();
        if (v <= 0) continue;
        final double h = (hi == 0 ? 0.0 : v / hi) * (size.height - 6) * grow;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y - h, w, math.max(0.0, h - 1.5)), Radius.circular(math.min(4.0, w / 2))),
          Paint()..color = colorOf(k).withValues(alpha: dim ? .3 : 1),
        );
        y -= h;
      }
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.t != t || old.at != at || old.days != days;
}

/// Labelled horizontal bars that grow in.
class BarList extends StatelessWidget {
  const BarList({required this.items, required this.color, required this.format, required this.currency, super.key});
  final List<({String label, double value})> items;
  final Color color;
  final String format;
  final PhlioCurrency currency;
  @override
  Widget build(BuildContext context) {
    final hi = items.fold<double>(0, (a, b) => math.max(a, b.value));
    return Column(children: [
      for (final (i, it) in items.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 110, child: Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: hi == 0 ? 0 : it.value / hi),
                duration: Duration(milliseconds: 700 + i * 90),
                curve: Curves.easeOutCubic,
                builder: (_, t, __) => Stack(children: [
                  Container(height: 12, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(6))),
                  FractionallySizedBox(
                    widthFactor: t,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.white, .25)!]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Text(fmtValue(it.value, format, currency, compact: true), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
    ]);
  }
}

/// Vertical bars (weekdays) that grow in; tap one to read it.
class ColumnBars extends StatefulWidget {
  const ColumnBars({required this.items, required this.color, required this.format, required this.currency, super.key});
  final List<({String label, double value})> items;
  final Color color;
  final String format;
  final PhlioCurrency currency;
  @override
  State<ColumnBars> createState() => _ColumnBarsState();
}

class _ColumnBarsState extends State<ColumnBars> {
  int? _at;
  @override
  Widget build(BuildContext context) {
    final hi = widget.items.fold<double>(0, (a, b) => math.max(a, b.value));
    final peak = hi == 0 ? -1 : widget.items.indexWhere((x) => x.value == hi);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, it) in widget.items.indexed)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _at = _at == i ? null : i),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _at == i || (_at == null && i == peak) ? 1 : 0,
                  child: FittedBox(
                    child: Text(fmtValue(it.value, widget.format, widget.currency, compact: true),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: hi == 0 ? 0 : it.value / hi),
                  duration: Duration(milliseconds: 700 + i * 80),
                  curve: Curves.easeOutBack,
                  builder: (_, t, __) => Container(
                    height: math.max(4.0, 100 * t.clamp(0.0, 1.1)),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: i == peak || _at == i
                            ? [widget.color, Color.lerp(widget.color, Colors.white, .35)!]
                            : [widget.color.withValues(alpha: .35), widget.color.withValues(alpha: .55)],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(it.label, style: TextStyle(fontSize: 11.5, color: i == peak ? Colors.white : Colors.white54)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// 24 cells, brighter where there's more.
class HourStrip extends StatelessWidget {
  const HourStrip({required this.hours, required this.color, super.key});
  final List<double> hours;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final hi = hours.fold<double>(0, math.max);
    return Column(children: [
      Row(children: [
        for (final (i, h) in hours.indexed)
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: hi == 0 ? 0 : h / hi),
              duration: Duration(milliseconds: 500 + i * 30),
              builder: (_, t, __) => Container(
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: Color.lerp(Colors.white.withValues(alpha: .05), color, t),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('12 AM', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
        Text('6 AM', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
        Text('12 PM', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
        Text('6 PM', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
        Text('11 PM', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
      ]),
    ]);
  }
}

class _TopList extends StatelessWidget {
  const _TopList({required this.items, required this.color, required this.currency});
  final List<Map> items;
  final Color color;
  final PhlioCurrency currency;
  @override
  Widget build(BuildContext context) {
    final values = [for (final x in items) ((x['value'] as num?) ?? 0).toDouble()];
    final hi = values.fold<double>(0, math.max);
    return Column(children: [
      for (final (i, x) in items.indexed)
        Reveal(
          index: i,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(x['username'] != null ? 22 : 10),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: x['image_url'] != null && '${x['image_url']}'.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: AppConfig.mediaUrl('${x['image_url']}'),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _initial(x),
                        )
                      : _initial(x),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${x['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ('${x['subtitle'] ?? ''}'.isNotEmpty)
                    Text('${x['subtitle']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                  if (x['value'] != null && hi > 0) ...[
                    const SizedBox(height: 5),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: values[i] / hi),
                      duration: Duration(milliseconds: 800 + i * 100),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, __) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: math.max(.02, t),
                        child: Container(height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                      ),
                    ),
                  ],
                ]),
              ),
              if (x['value'] != null) ...[
                const SizedBox(width: 10),
                Text(fmtValue(x['value'] as num, '${x['format'] ?? 'count'}', currency, compact: true),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ]),
          ),
        ),
    ]);
  }

  Widget _initial(Map x) => DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, .4)!])),
        child: Center(
          child: Text('${x['title']}'.trim().isEmpty ? '?' : '${x['title']}'.trim().characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ),
      );
}
