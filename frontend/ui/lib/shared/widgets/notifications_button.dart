import '../../features/profile/presentation/widgets/memories_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../notifications/notification_center.dart';

class PhlioNotificationsButton extends ConsumerWidget {
  const PhlioNotificationsButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationCenterProvider.select((c) => c.unread));
    final snaps = ref.watch(memoriesProvider).valueOrNull?.where((m) => m['unread'] == true).length ?? 0;
    final total = unread + snaps;
    return IconButton(
        tooltip: 'Notifications',
        onPressed: () => context.push('/notifications'),
        icon: Badge(
            isLabelVisible: total > 0,
            label: Text(total > 99 ? '99+' : '$total'),
            child: const Icon(Icons.notifications_outlined)));
  }
}
