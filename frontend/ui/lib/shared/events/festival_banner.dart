// Seasonal festival / event banner (Diwali, Christmas, Eid, Lunar New Year,
// Holi, Black Friday...). The server decides which events are on today for
// this platform and the phone's region (GET /api/v1/events/banners); this
// widget draws them as a gradient card with an animated motif: floating
// diyas, falling snow, lanterns, hearts, confetti, fireworks...
//
// Drop `FestivalBanner(platform: 'shop')` at the top of a platform home.
// It renders nothing when no event is on, and people can dismiss a banner
// for the rest of the session.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

/// Active banners for a platform (`social`, `shop`, `book`, `stream`...).
final festivalBannersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, platform) async {
  final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
  final res = await getIt<ApiClient>().dio.get<dynamic>('/events/banners', queryParameters: {
    'platform': platform,
    if (region != null && RegExp(r'^[A-Za-z]{2}$').hasMatch(region)) 'region': region,
  });
  return [
    for (final b in ((res.data as Map)['items'] as List? ?? const [])) Map<String, dynamic>.from(b as Map),
  ];
});

/// Banners dismissed this session (event ids).
final _dismissedProvider = StateProvider<Set<String>>((ref) => const {});

class FestivalBanner extends ConsumerWidget {
  const FestivalBanner({required this.platform, super.key, this.padding = const EdgeInsets.only(bottom: 14), this.onTap});

  final String platform;
  final EdgeInsetsGeometry padding;

  /// What tapping does (e.g. open a festive collection); null = nothing.
  final void Function(Map<String, dynamic> event)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(_dismissedProvider);
    final items = (ref.watch(festivalBannersProvider(platform)).valueOrNull ?? const [])
        .where((b) => !dismissed.contains(b['id']))
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final event = items.first;
    return Padding(
      padding: padding,
      child: _BannerCard(
        event: event,
        onTap: onTap == null ? null : () => onTap!(event),
        onClose: () {
          HapticFeedback.selectionClick();
          ref.read(_dismissedProvider.notifier).state = {...dismissed, '${event['id']}'};
        },
      ),
    );
  }
}

Color _hex(String s) {
  final v = int.tryParse(s.replaceFirst('#', ''), radix: 16) ?? 0x8D78FF;
  return Color(0xFF000000 | v);
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({required this.event, required this.onClose, this.onTap});
  final Map<String, dynamic> event;
  final VoidCallback onClose;
  final VoidCallback? onTap;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final colors = [for (final c in (e['colors'] as List? ?? const ['#8D78FF', '#E795D7'])) _hex('$c')];
    if (colors.length == 1) colors.add(colors.first);
    final live = e['status'] == 'live';
    final daysTo = (e['days_to'] as num?)?.toInt() ?? 0;
    final when = live
        ? 'Today'
        : daysTo == 1
            ? 'Tomorrow'
            : 'In $daysTo days';
    // Light gradients (Easter, Republic Day) need dark text.
    final light = colors.map((c) => c.computeLuminance()).reduce((a, b) => a + b) / colors.length > 0.55;
    final fg = light ? const Color(0xFF14161C) : Colors.white;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Semantics(
      container: true,
      label: '${e['greeting']}. ${e['line']}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Ink(
            height: 128,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Stack(children: [
              Positioned.fill(
                child: reduceMotion
                    ? CustomPaint(painter: _MotifPainter('${e['motif']}', 0.35))
                    : AnimatedBuilder(
                        animation: _t,
                        builder: (_, __) => CustomPaint(painter: _MotifPainter('${e['motif']}', _t.value)),
                      ),
              ),
              Positioned(
                right: 14,
                bottom: 6,
                child: ExcludeSemantics(child: Text('${e['emoji'] ?? '✨'}', style: const TextStyle(fontSize: 58))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 90, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: fg.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      live ? '${e['name']} · $when' : '${e['name']} · $when${e['approximate'] == true ? ' (approx.)' : ''}',
                      style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${e['greeting']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 21, fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 3),
                  Text('${e['line']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13.5)),
                ]),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  tooltip: 'Hide',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: fg.withValues(alpha: 0.8)),
                  onPressed: widget.onClose,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Draws the festival motif. [t] runs 0→1 and loops; particles are placed
/// from a fixed seed so they don't jump between frames.
class _MotifPainter extends CustomPainter {
  _MotifPainter(this.motif, this.t);
  final String motif;
  final double t;

  static final _seeds = List.generate(26, (i) {
    final r = math.Random(i * 7919 + 13);
    return (r.nextDouble(), r.nextDouble(), r.nextDouble(), r.nextDouble());
  });

  static const _confetti = [Color(0xFFFFD166), Color(0xFFEF476F), Color(0xFF06D6A0), Color(0xFF118AB2), Colors.white];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint();
    for (var i = 0; i < _seeds.length; i++) {
      final (a, b, c, d) = _seeds[i];
      final phase = (t + a) % 1.0;
      switch (motif) {
        case 'snow':
          final x = (b * w + math.sin((phase + c) * math.pi * 2) * 12) % w;
          final y = phase * (h + 10) - 5;
          canvas.drawCircle(Offset(x, y), 1.2 + c * 2.2, p..color = Colors.white.withValues(alpha: 0.5 + d * 0.4));
        case 'diyas' || 'candles':
          // Warm floating lights that rise and flicker.
          final x = b * w;
          final y = h - phase * h * 0.9;
          final flicker = 0.6 + 0.4 * math.sin((t * 40 + i) * 1.3);
          final r = 2.0 + c * 3;
          canvas.drawCircle(Offset(x, y), r * 3,
              p..color = const Color(0xFFFFB703).withValues(alpha: 0.12 * flicker * (1 - phase)));
          canvas.drawCircle(Offset(x, y), r, p..color = const Color(0xFFFFE8A3).withValues(alpha: 0.9 * (1 - phase)));
        case 'lanterns':
          if (i > 9) continue;
          final x = (i + 0.5) / 10 * w;
          final y = 8 + math.sin((t + a) * math.pi * 2) * 5 + c * 18;
          canvas.drawLine(Offset(x, 0), Offset(x, y), p..color = Colors.white24..strokeWidth = 1);
          final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y + 9), width: 13, height: 17),
              const Radius.circular(6));
          canvas.drawRRect(rect, p..color = const Color(0xFFFF4D4D).withValues(alpha: 0.75));
          canvas.drawRRect(rect.deflate(3), p..color = const Color(0xFFFFD27D).withValues(alpha: 0.55));
        case 'hearts' || 'petals':
          final x = b * w + math.sin((phase + c) * math.pi * 2) * 10;
          final y = h - phase * (h + 20) + 10;
          final s = 4 + c * 5;
          final path = Path()
            ..moveTo(x, y + s * 0.9)
            ..cubicTo(x - s * 1.4, y - s * 0.2, x - s * 0.5, y - s * 1.2, x, y - s * 0.35)
            ..cubicTo(x + s * 0.5, y - s * 1.2, x + s * 1.4, y - s * 0.2, x, y + s * 0.9);
          canvas.drawPath(path, p..color = Colors.white.withValues(alpha: 0.28 * (1 - phase) + 0.1));
        case 'fireworks':
          if (i > 4) continue;
          final cx = (0.15 + b * 0.7) * w, cy = (0.2 + c * 0.45) * h;
          final burst = phase < 0.6 ? phase / 0.6 : 1.0;
          final fade = phase < 0.6 ? 1.0 : 1 - (phase - 0.6) / 0.4;
          for (var k = 0; k < 12; k++) {
            final ang = k / 12 * math.pi * 2;
            final o = Offset(cx + math.cos(ang) * burst * 26, cy + math.sin(ang) * burst * 26);
            canvas.drawCircle(o, 1.6, p..color = _confetti[(i + k) % _confetti.length].withValues(alpha: 0.8 * fade));
          }
        case 'colors' || 'splash':
          final x = b * w, y = c * h;
          final r = 10 + d * 26 * (0.6 + 0.4 * math.sin((t + a) * math.pi * 2));
          canvas.drawCircle(Offset(x, y), r, p..color = _confetti[i % 4].withValues(alpha: 0.18));
        case 'kites':
          if (i > 6) continue;
          final x = (b * w + t * w * 0.3) % w;
          final y = 10 + c * h * 0.5 + math.sin((t + a) * math.pi * 4) * 6;
          final kite = Path()
            ..moveTo(x, y - 9)
            ..lineTo(x + 7, y)
            ..lineTo(x, y + 9)
            ..lineTo(x - 7, y)
            ..close();
          canvas.drawPath(kite, p..color = _confetti[i % _confetti.length].withValues(alpha: 0.6));
        case 'leaves' || 'bats':
          final x = (b * w + phase * 40) % w;
          final y = phase * (h + 20) - 10;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate((t + a) * math.pi * 4);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 10, height: 5),
              p..color = (motif == 'bats' ? Colors.black : const Color(0xFFFFD6A5)).withValues(alpha: 0.45));
          canvas.restore();
        case 'rainbow' || 'confetti':
          final x = (b * w + math.sin((phase + c) * math.pi * 2) * 8) % w;
          final y = phase * (h + 10) - 5;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate((t * 6 + a) * math.pi);
          canvas.drawRect(const Rect.fromLTWH(-3, -1.5, 6, 3), p..color = _confetti[i % _confetti.length].withValues(alpha: 0.75));
          canvas.restore();
        default: // sparkles
          final tw = (math.sin((t * 3 + a) * math.pi * 2) + 1) / 2;
          canvas.drawCircle(Offset(b * w, c * h), 0.8 + 2 * tw, p..color = Colors.white.withValues(alpha: 0.2 + 0.6 * tw));
      }
    }
  }

  @override
  bool shouldRepaint(_MotifPainter old) => old.t != t || old.motif != motif;
}
