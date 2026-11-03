// Your snaps — the archive of every snap you've shared, like Instagram's
// "Your instants".
//
//   Archive  your snaps, newest first, grouped by month ("October 2026"),
//            three to a row in rounded frames; each shows its top reaction
//            and how many people reacted.
//   Detail   the snap itself, when you took it, the caption, who it was
//            shared with, and every reaction: who, which emoji, when.
//            Delete from the ⋯ menu.
//
// Data: GET /social/memories (your own snaps never expire for you); each
// reaction carries the reacting person (user: {username, display_name,
// avatar_url}) and reacted_at.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../shared/content/memory_photo.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import 'memories_screen.dart' show memoriesProvider;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

DateTime? _when(Map item) => DateTime.tryParse('${item['created_at']}')?.toLocal();

String _clock(DateTime t) =>
    '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';

/// "Saturday, 31 October 2026 · 3:26 PM".
String snapDate(DateTime t) => '${_days[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]} ${t.year} · ${_clock(t)}';

/// The most used reaction and how many reacted, e.g. ("❤️", 2).
(String, int)? topReaction(Map item) {
  final reactions = (item['reactions'] as List? ?? const []).cast<Map>();
  if (reactions.isEmpty) return null;
  final counts = <String, int>{};
  for (final r in reactions) {
    counts.update('${r['emoji']}', (n) => n + 1, ifAbsent: () => 1);
  }
  final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return (top.key, reactions.length);
}

/// The rounded "instant" frame used for snap tiles.
class _SnapFrame extends StatelessWidget {
  const _SnapFrame({required this.item, required this.radius, this.autoplay = false});
  final Map item;
  final double radius;
  final bool autoplay;

  @override
  Widget build(BuildContext context) => ClipPath(
        clipper: ShapeBorderClipper(shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius))),
        child: ColoredBox(
          color: const Color(0xFF1B1B1F),
          child: MemoryPhoto('${item['image_url']}', decorations: (item['decorations'] as List?) ?? const [],
              isVideo: item['media_kind'] == 'video', filter: item['filter'] as String?, autoplay: autoplay),
        ),
      );
}

class SnapArchiveScreen extends ConsumerWidget {
  const SnapArchiveScreen({super.key, this.onCamera});

  /// Opens the snap camera (the top-right button).
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull?.id;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Your snaps', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          if (onCamera != null)
            IconButton(
              tooltip: 'Take a snap',
              onPressed: () {
                Navigator.pop(context);
                onCamera!();
              },
              icon: const Icon(Icons.photo_camera_outlined),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(memoriesProvider.future),
        child: ref.watch(memoriesProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => ListView(children: [
                const SizedBox(height: 160),
                Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(memoriesProvider),
                    child: const Text('Could not load your snaps. Retry'),
                  ),
                ),
              ]),
              data: (all) => _grid(context, [
                for (final m in all)
                  if (m['author'] is Map && m['author']['id'] == me && (m['kind'] ?? 'snap') == 'snap') m,
              ]),
            ),
      ),
    );
  }

  Widget _grid(BuildContext context, List<Map> mine) {
    if (mine.isEmpty) {
      return ListView(padding: const EdgeInsets.all(32), children: const [
        SizedBox(height: 120),
        Icon(Icons.photo_library_outlined, color: Colors.white38, size: 64),
        SizedBox(height: 16),
        Text('No snaps yet',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text('Snaps you share are kept here, with everyone\'s reactions.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
      ]);
    }
    // Newest first, grouped by month.
    mine.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    final groups = <String, List<Map>>{};
    for (final m in mine) {
      final t = _when(m);
      groups.putIfAbsent(t == null ? 'Earlier' : '${_months[t.month - 1]} ${t.year}', () => []).add(m);
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final entry in groups.entries) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            sliver: SliverToBoxAdapter(
              child: Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1),
              itemCount: entry.value.length,
              itemBuilder: (context, i) => _tile(context, entry.value[i]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _tile(BuildContext context, Map item) {
    final top = topReaction(item);
    final t = _when(item);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SnapDetailScreen(item: item))),
      child: Stack(fit: StackFit.expand, children: [
        Hero(tag: 'snap-${item['id']}', child: _SnapFrame(item: item, radius: 56)),
        if (item['media_kind'] == 'video')
          const Positioned(
            left: 10,
            top: 8,
            child: Icon(Icons.videocam_rounded, color: Colors.white, size: 18, shadows: [Shadow(color: Colors.black87, blurRadius: 6)]),
          ),
        if (top != null)
          Positioned(
            top: 8,
            right: 10,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(top.$1, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 3),
              Text('${top.$2}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, shadows: [Shadow(color: Colors.black87, blurRadius: 6)])),
            ]),
          ),
        if (t != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Text(_clock(t),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: PhlioColors.brandPeach,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
          ),
      ]),
    );
  }
}

/// One snap: the photo, its date, caption and everyone's reactions.
class SnapDetailScreen extends ConsumerWidget {
  const SnapDetailScreen({required this.item, super.key});
  final Map item;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete snap?'),
        content: const Text('It\'s removed from your snaps and from everyone\'s view.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await getIt<ApiClient>().dio.delete('/social/memories/${item['id']}');
      ref.invalidate(memoriesProvider);
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show the freshest reactions if the list reloaded while we're open.
    final live = ref.watch(memoriesProvider).valueOrNull?.where((m) => m['id'] == item['id']).firstOrNull ?? item;
    final t = _when(live);
    final reactions = (live['reactions'] as List? ?? const []).cast<Map>();
    final caption = '${live['caption'] ?? ''}'.trim();
    final audience = switch (live['audience']) {
      'everyone' => 'Everyone',
      'close_friends' => 'Close friends',
      _ => 'Friends',
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(t == null ? 'Snap' : '${_months[t.month - 1]} ${t.day}, ${t.year}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(context, ref);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete snap'))],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        AspectRatio(
          aspectRatio: 1,
          child: Hero(tag: 'snap-${live['id']}', child: _SnapFrame(item: live, radius: 120, autoplay: true)),
        ),
        const SizedBox(height: 16),
        if (t != null)
          Row(children: [
            const Icon(Icons.schedule_rounded, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(snapDate(t), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.people_alt_outlined, color: Colors.white54, size: 18),
          const SizedBox(width: 8),
          Text('Shared with $audience', style: const TextStyle(color: Colors.white70)),
        ]),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(caption, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
        const SizedBox(height: 22),
        Row(children: [
          const Text('Reactions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          if (reactions.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10)),
              child: Text('${reactions.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ]),
        if (reactions.isNotEmpty) ...[
          const SizedBox(height: 10),
          // Summary chips: ❤️ 2 · 😂 1
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _counts(reactions).entries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF202020), borderRadius: BorderRadius.circular(18)),
                child: Text('${e.key}  ${e.value}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 6),
          for (final r in reactions) _ReactionRow(reaction: r),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('No reactions yet. Friends\' reactions show up here.', style: TextStyle(color: Colors.white54)),
          ),
      ]),
    );
  }

  static Map<String, int> _counts(List<Map> reactions) {
    final counts = <String, int>{};
    for (final r in reactions) {
      counts.update('${r['emoji']}', (n) => n + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.reaction});
  final Map reaction;

  @override
  Widget build(BuildContext context) {
    final user = reaction['user'] is Map ? reaction['user'] as Map : const {};
    final name = '${user['display_name'] ?? user['username'] ?? 'Someone'}';
    final avatar = user['avatar_url'] as String?;
    final at = DateTime.tryParse('${reaction['reacted_at'] ?? ''}')?.toLocal();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: PhlioColors.surfaceElevated,
        backgroundImage: avatar == null || avatar.isEmpty ? null : NetworkImage(AppConfig.mediaUrl(avatar)),
        child: avatar == null || avatar.isEmpty
            ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white))
            : null,
      ),
      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      subtitle: Text(
        [if (user['username'] != null) '@${user['username']}', if (at != null) timeago.format(at)].join(' · '),
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: Text('${reaction['emoji']}', style: const TextStyle(fontSize: 26)),
    );
  }
}
