// All notifications, across every Phlio platform: filter chips per platform
// (each in its own colour), Today / Earlier, unread dots, swipe to remove.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/widgets/phlio_card.dart';
import 'notification_center.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String? _platform;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(notificationCenterProvider).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final center = ref.watch(notificationCenterProvider);
    final present = {for (final n in center.items) n.platform.id};
    final shown = center.items.where((n) => _platform == null || n.platform.id == _platform).toList();
    final today = DateTime.now();
    bool isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;
    final fresh = shown.where((n) => isToday(n.at)).toList();
    final older = shown.where((n) => !isToday(n.at)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Preview banners',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final made = await center.preview();
                messenger.showSnackBar(SnackBar(
                    content: Text(made.isEmpty
                        ? 'Nothing to preview yet'
                        : 'Sending ${made.length} sample banners: tap or pull one down to expand it')));
              } catch (_) {
                messenger.showSnackBar(const SnackBar(content: Text('Could not start the preview')));
              }
            },
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
          if (center.unread > 0)
            TextButton(onPressed: center.markAllRead, child: const Text('Mark all read')),
          IconButton(
            tooltip: 'Activity',
            onPressed: () => context.push('/activity'),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _Chip(label: 'All', color: Colors.white, selected: _platform == null, onTap: () => setState(() => _platform = null)),
              for (final p in NotifPlatform.all.where((p) => present.contains(p.id)))
                _Chip(
                  label: p.label,
                  icon: p.icon,
                  color: p.color,
                  selected: _platform == p.id,
                  onTap: () => setState(() => _platform = _platform == p.id ? null : p.id),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: center.refresh,
            child: shown.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Icon(Icons.notifications_none_rounded, size: 56, color: Colors.white30),
                    SizedBox(height: 12),
                    Center(child: Text("You're all caught up", style: TextStyle(color: Colors.white60))),
                  ])
                : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                    if (fresh.isNotEmpty) const _Header('Today'),
                    for (final n in fresh) _Tile(n: n),
                    if (older.isNotEmpty) const _Header('Earlier'),
                    for (final n in older) _Tile(n: n),
                  ]),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.selected, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? color.withValues(alpha: .22) : Colors.white.withValues(alpha: .06),
          shape: StadiumBorder(side: BorderSide(color: selected ? color : Colors.white12)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 6)],
                Text(label, style: TextStyle(color: selected ? color : Colors.white70, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.n});
  final PhlioNotification n;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final center = ref.read(notificationCenterProvider);
    final actor = n.actor;
    final p = n.platform;
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFFB3123A),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => center.remove(n),
      child: InkWell(
        onTap: () {
          center.markRead([n]);
          final route = n.route;
          if (route != null) context.push(route);
        },
        child: Container(
          color: n.read ? null : p.color.withValues(alpha: .06),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              actor == null
                  ? Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(gradient: p.gradient, borderRadius: BorderRadius.circular(14)),
                      child: Icon(p.icon, color: Colors.white),
                    )
                  : PhlioAvatar(
                      name: '${actor['display_name'] ?? actor['username'] ?? ''}',
                      imageUrl: actor['avatar_url'] as String?,
                      size: 46,
                      showMomentRing: false),
              if (actor != null)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: p.gradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                    child: Icon(p.icon, size: 12, color: Colors.white),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(p.label, style: TextStyle(color: p.color, fontSize: 12, fontWeight: FontWeight.w800)),
                  Text(' · ${notifAgo(n.at)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
                const SizedBox(height: 2),
                Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(n.count > 1 ? '${n.body}  ·  ${n.count} new' : n.body,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
            if (!n.read)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 18),
                child: Container(width: 9, height: 9, decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
              ),
          ]),
        ),
      ),
    );
  }
}
