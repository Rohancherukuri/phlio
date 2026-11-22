// The bell, colour-coded by platform: the badge takes the colour of the
// newest unread notification's platform, so you can tell at a glance where
// it's from — pink Messages, violet Social, teal Rooms, orange Shop, blue
// News, red Stream, rose Book, gold Pay, peach Foxy (the same colours as the
// island and the notifications screen; NotifPlatform). When more than one
// platform is waiting, a small ring of their colours goes round the bell.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/profile/presentation/widgets/memories_screen.dart';
import '../notifications/notification_center.dart';

class PhlioNotificationsButton extends ConsumerWidget {
  const PhlioNotificationsButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final center = ref.watch(notificationCenterProvider);
    final snaps = ref.watch(memoriesProvider).valueOrNull?.where((m) => m['unread'] == true).length ?? 0;
    final total = center.unread + snaps;
    // Unread platforms, newest first (snaps are Social).
    final platforms = <NotifPlatform>[];
    for (final n in center.items) {
      if (!n.read && !platforms.any((p) => p.id == n.platform.id)) platforms.add(n.platform);
    }
    if (snaps > 0 && !platforms.any((p) => p.id == 'social')) platforms.add(NotifPlatform.of('social'));
    final lead = platforms.isEmpty ? null : platforms.first;
    final names = platforms.map((p) => p.label).join(', ');
    return IconButton(
      tooltip: total == 0 ? 'Notifications' : 'Notifications: $total new from $names',
      onPressed: () => context.push('/notifications'),
      icon: Stack(clipBehavior: Clip.none, children: [
        if (platforms.length > 1)
          Positioned.fill(
            child: Transform.scale(
              scale: 1.55,
              child: CustomPaint(painter: _Ring([for (final p in platforms.take(6)) p.color])),
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: Icon(
            total > 0 ? Icons.notifications_rounded : Icons.notifications_outlined,
            key: ValueKey(lead?.id),
            color: lead?.color,
          ),
        ),
        if (total > 0)
          Positioned(
            right: -7,
            top: -6,
            child: TweenAnimationBuilder<double>(
              key: ValueKey('$total${lead?.id}'),
              tween: Tween(begin: .4, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: (lead ?? NotifPlatform.of('social')).gradient,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                ),
                child: Text(total > 99 ? '99+' : '$total',
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, height: 1)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Thin ring split into the colours of the platforms waiting.
class _Ring extends CustomPainter {
  _Ring(this.colors);
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - 1);
    final sweep = math.pi * 2 / colors.length;
    for (var i = 0; i < colors.length; i++) {
      canvas.drawArc(rect, -math.pi / 2 + i * sweep + .12, sweep - .24, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(_Ring old) => old.colors.length != colors.length || !Iterable.generate(colors.length).every((i) => old.colors[i] == colors[i]);
}
