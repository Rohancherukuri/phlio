// Seasonal festival / event banner (Diwali, Christmas, Eid, Lunar New Year,
// Holi, Black Friday...). The server decides which events are on today for
// this platform and the phone's region (GET /api/v1/events/banners); this
// widget draws them as a flat card in the event's colour with an animated
// illustration on the right: Lottie scenes from assets/lottie/festival/
// (diyas, lanterns, crescent & fanous, tree in the snow, fireworks...),
// built by scripts/media/festival_lottie/build.py.
//
// Drop `FestivalBanner(platform: 'shop')` at the top of a platform home.
// It renders nothing when no event is on, and people can dismiss a banner
// for the rest of the session.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/typography.dart';

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

/// Which animation an event gets: by event id first, then by its motif.
const _artById = {
  'ramadan': 'crescent',
  'eid-al-fitr': 'crescent',
  'eid-al-adha': 'crescent',
  'black-friday': 'sale',
  'singles-day': 'sale',
};
const _artByMotif = {
  'diyas': 'diyas',
  'candles': 'candles',
  'lanterns': 'lanterns',
  'snow': 'snow',
  'hearts': 'hearts',
  'petals': 'petals',
  'fireworks': 'fireworks',
  'colors': 'colors',
  'splash': 'splash',
  'kites': 'kites',
  'leaves': 'leaves',
  'bats': 'bats',
  'rainbow': 'rainbow',
  'confetti': 'confetti',
  'sparkles': 'sparkles',
};

String festivalArt(Map<String, dynamic> event) =>
    'assets/lottie/festival/${_artById['${event['id']}'] ?? _artByMotif['${event['motif']}'] ?? 'sparkles'}.json';

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.event, required this.onClose, this.onTap});
  final Map<String, dynamic> event;
  final VoidCallback onClose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final colors = [for (final c in (e['colors'] as List? ?? const ['#2A0845'])) _hex('$c')];
    // One flat colour: the event's first, deepened a touch so the art pops.
    final base = Color.lerp(colors.first, Colors.black, colors.first.computeLuminance() > .5 ? 0 : .12)!;
    final live = e['status'] == 'live';
    final daysTo = (e['days_to'] as num?)?.toInt() ?? 0;
    final when = live
        ? 'Today'
        : daysTo == 1
            ? 'Tomorrow'
            : 'In $daysTo days';
    final light = base.computeLuminance() > 0.5;
    final fg = light ? const Color(0xFF14161C) : Colors.white;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Semantics(
      container: true,
      label: '${e['greeting']}. ${e['line']}',
      child: Material(
        color: base,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 140,
            child: Stack(children: [
              // The scene, anchored right (its quiet disc runs off the edge).
              Positioned(
                right: -12,
                top: 2,
                bottom: 2,
                child: ExcludeSemantics(
                  child: AspectRatio(
                    aspectRatio: 320 / 256,
                    child: Lottie.asset(
                      festivalArt(e),
                      animate: !reduceMotion,
                      repeat: true,
                      fit: BoxFit.contain,
                      frameRate: FrameRate.max,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 146, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: live ? (colors.length > 1 ? colors[1] : fg) : fg.withValues(alpha: .5),
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${'${e['name']}'.toUpperCase()} · ${when.toUpperCase()}'
                          '${!live && e['approximate'] == true ? ' (APPROX.)' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: fg.withValues(alpha: .72),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('${e['greeting']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: PhlioTypography.displayFamily,
                            color: fg,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.12,
                            letterSpacing: -.2)),
                    const SizedBox(height: 5),
                    Text('${e['line']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg.withValues(alpha: .78), fontSize: 13, height: 1.3)),
                  ],
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: Colors.black.withValues(alpha: light ? .06 : .18),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClose,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(Icons.close_rounded, size: 15, color: fg.withValues(alpha: .85), semanticLabel: 'Hide'),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
