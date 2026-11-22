// The bell: its badge (the dot with the count) takes the colour of the
// newest unread notification's platform, so you can tell at a glance where
// it's from — pink Messages, violet Social, teal Rooms, orange Shop, blue
// News, red Stream, rose Book, gold Pay, peach Foxy (the same colours as the
// island and the notifications screen; NotifPlatform).

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
        const Icon(Icons.notifications_outlined),
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
                  color: (lead ?? NotifPlatform.of('social')).color,
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
