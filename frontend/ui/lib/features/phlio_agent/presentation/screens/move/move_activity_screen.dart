// Phlio Move — one activity: route, stats, splits, people tagged, kudos
// (emoji reactions) and the comment thread (stickers, GIFs, @mentions,
// voice notes and 30-second song snippets).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';
import 'package:phlio/design_system/widgets/phlio_card.dart';
import 'package:phlio/shared/content/mentions.dart';
import 'package:phlio/shared/content/social_comments_sheet.dart' show ContentDiscussion;

import 'move_api.dart';

const _emojis = ['👏', '🔥', '💪', '❤️', '😮', '🏅'];

class MoveActivityScreen extends StatefulWidget {
  const MoveActivityScreen({required this.id, super.key});
  final String id;

  @override
  State<MoveActivityScreen> createState() => _MoveActivityScreenState();
}

class _MoveActivityScreenState extends State<MoveActivityScreen> {
  Map<String, dynamic>? _a;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await moveDio.get('/activities/${widget.id}');
      if (mounted) setState(() => _a = Map<String, dynamic>.from(res.data as Map));
    } catch (_) {
      if (mounted) setState(() => _error = 'This activity isn’t available.');
    }
  }

  Future<void> _react(String emoji) async {
    final a = _a!;
    HapticFeedback.selectionClick();
    final mine = a['my_kudos'] == emoji;
    try {
      final res = mine
          ? await moveDio.delete('/activities/${widget.id}/kudos')
          : await moveDio.put('/activities/${widget.id}/kudos', data: {'emoji': emoji});
      if (!mounted) return;
      final r = res.data as Map;
      setState(() {
        a['kudos'] = r['kudos'];
        a['kudos_count'] = r['kudos_count'];
        a['my_kudos'] = r['my_kudos'];
      });
      _load();
    } catch (_) {}
  }

  Future<void> _ownerMenu() async {
    final a = _a!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(a['visibility'] == 'everyone' ? Icons.lock_rounded : Icons.public_rounded),
            title: Text(a['visibility'] == 'everyone' ? 'Make private' : 'Show to everyone'),
            onTap: () => Navigator.pop(ctx, 'visibility'),
          ),
          if ((a['route'] as List?)?.isNotEmpty == true || a['hide_endpoints'] == false)
            ListTile(
              leading: const Icon(Icons.visibility_off_rounded),
              title: Text(a['hide_endpoints'] == true ? 'Show full route' : 'Hide start and end'),
              onTap: () => Navigator.pop(ctx, 'endpoints'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: PhlioColors.danger),
            title: const Text('Delete activity', style: TextStyle(color: PhlioColors.danger)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    try {
      if (choice == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this activity?'),
            content: const Text('It’s removed from your activities and from Phlio Social, with its comments.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok != true) return;
        await moveDio.delete('/activities/${widget.id}');
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await moveDio.patch('/activities/${widget.id}', data: {
        if (choice == 'visibility') 'visibility': a['visibility'] == 'everyone' ? 'only_me' : 'everyone',
        if (choice == 'endpoints') 'hide_endpoints': a['hide_endpoints'] != true,
      });
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t update the activity.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Scaffold(
      appBar: AppBar(
        title: Text(a == null ? 'Activity' : '${a['sport_label']}'),
        actions: [
          if (a?['mine'] == true) IconButton(onPressed: _ownerMenu, icon: const Icon(Icons.more_horiz_rounded)),
        ],
      ),
      body: a == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!, style: PhlioTypography.body),
            )
          : RefreshIndicator(onRefresh: _load, child: _body(a)),
    );
  }

  Widget _body(Map<String, dynamic> a) {
    final sport = sportOf(a['sport'] as String?);
    final author = (a['author'] as Map?) ?? const {};
    final route = [
      for (final p in (a['route'] as List? ?? const [])) [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()]
    ];
    final splits = (a['splits'] as List? ?? const []).cast<Map>();
    final tagged = (a['tagged'] as List? ?? const []).cast<Map>();
    final kudos = Map<String, dynamic>.from((a['kudos'] as Map?) ?? const {});
    final givers = (a['kudos_people'] as List? ?? const []).cast<Map>();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
      Row(children: [
        GestureDetector(
          onTap: () => context.push('/creator/${author['username']}'),
          child: PhlioAvatar(name: '${author['display_name'] ?? ''}', imageUrl: author['avatar_url'] as String?, size: 44),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${author['display_name'] ?? author['username'] ?? ''}', style: PhlioTypography.bodyStrong),
            Row(children: [
              Icon(sport.icon, size: 14, color: PhlioColors.textMuted),
              const SizedBox(width: 4),
              Flexible(child: Text(fmtWhen('${a['started_at']}'), style: PhlioTypography.caption, overflow: TextOverflow.ellipsis)),
              if (a['visibility'] == 'only_me') ...[
                const SizedBox(width: 6),
                const Icon(Icons.lock_rounded, size: 13, color: PhlioColors.textMuted),
              ],
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Text('${a['title']}', style: PhlioTypography.headline),
      if ('${a['description'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: 6),
        MentionText('${a['description']}', style: PhlioTypography.body.copyWith(height: 1.4)),
      ],
      if (tagged.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('With', style: PhlioTypography.caption),
          for (final p in tagged)
            ActionChip(
              avatar: PhlioAvatar(name: '${p['display_name'] ?? ''}', imageUrl: p['avatar_url'] as String?, size: 22, showMomentRing: false),
              label: Text('${p['display_name'] ?? p['username']}'),
              onPressed: () => context.push('/creator/${p['username']}'),
            ),
        ]),
      ],
      const SizedBox(height: 16),
      // Route (or a sport tile for indoor activities).
      AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C131E),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: route.length > 1
              ? Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: RoutePainter(route, stroke: 5))),
                  if (a['hide_endpoints'] == true)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: _Pill(icon: Icons.visibility_off_rounded, text: a['mine'] == true ? 'Start & end hidden from others' : 'Start & end hidden'),
                    ),
                ])
              : Center(child: Icon(sport.icon, size: 72, color: moveAccent.withValues(alpha: .8))),
        ),
      ),
      const SizedBox(height: 16),
      _StatsGrid(a: a, sport: sport),
      if (splits.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Splits', style: PhlioTypography.title),
        const SizedBox(height: 10),
        _Splits(splits: splits),
      ],
      const SizedBox(height: 20),
      // Kudos.
      Text('Kudos${(a['kudos_count'] ?? 0) > 0 ? ' · ${a['kudos_count']}' : ''}', style: PhlioTypography.title),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _emojis)
          ChoiceChip(
            showCheckmark: false,
            selected: a['my_kudos'] == e,
            onSelected: (_) => _react(e),
            label: Text('$e${kudos[e] != null ? '  ${kudos[e]}' : ''}', style: const TextStyle(fontSize: 16)),
          ),
      ]),
      if (givers.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final g in givers)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(clipBehavior: Clip.none, children: [
                  PhlioAvatar(name: '${g['display_name'] ?? ''}', imageUrl: g['avatar_url'] as String?, size: 36, showMomentRing: false),
                  Positioned(right: -4, bottom: -4, child: Text('${g['emoji']}', style: const TextStyle(fontSize: 14))),
                ]),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      if (a['post_id'] != null)
        ContentDiscussion(contentId: '${a['post_id']}')
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.lock_outline_rounded, color: PhlioColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                a['visibility'] == 'only_me'
                    ? 'Only you can see this activity, so there are no comments.'
                    : 'This activity wasn’t shared to Phlio Social, so there are no comments.',
                style: PhlioTypography.caption,
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text, style: PhlioTypography.caption.copyWith(color: Colors.white)),
        ]),
      );
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.a, required this.sport});
  final Map a;
  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final dist = (a['distance_m'] as num?) ?? 0;
    final items = <(String, String)>[
      if (sport.distance && dist > 0) ('${fmtKm(dist)} km', 'Distance'),
      if (sport.distance && dist > 0)
        sport.pace ? ('${fmtPace(a['pace_s_per_km'] as num?)} /km', 'Avg pace') : ('${a['speed_kmh'] ?? 0} km/h', 'Avg speed'),
      (fmtDuration((a['moving_s'] as num?) ?? 0), 'Moving time'),
      if (((a['elevation_m'] as num?) ?? 0) > 0) ('${(a['elevation_m'] as num).round()} m', 'Elevation gain'),
      ('${a['calories'] ?? 0}', 'Calories'),
      (fmtDuration((a['elapsed_s'] as num?) ?? 0), 'Elapsed time'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: LayoutBuilder(
        builder: (_, box) => Wrap(runSpacing: 16, children: [
          for (final (v, l) in items) SizedBox(width: (box.maxWidth - 1) / 2, child: MoveStat(value: v, label: l)),
        ]),
      ),
    );
  }
}

class _Splits extends StatelessWidget {
  const _Splits({required this.splits});
  final List<Map> splits;

  @override
  Widget build(BuildContext context) {
    // Seconds per km; a final partial split is scaled up to a full km.
    double pace(Map s) {
      final frac = s['partial'] == true ? (s['km'] as num) % 1 : 1;
      return (s['seconds'] as num) / (frac == 0 ? 1 : frac);
    }

    final secs = [for (final s in splits) pace(s)];
    final slowest = secs.reduce((a, b) => a > b ? a : b);
    return Column(children: [
      for (var i = 0; i < splits.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 44, child: Text('${splits[i]['km']}', style: PhlioTypography.caption)),
            SizedBox(width: 60, child: Text(fmtPace(secs[i]), style: PhlioTypography.bodyStrong)),
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 10,
                    width: box.maxWidth * (.25 + .75 * (secs[i] / slowest)),
                    decoration: BoxDecoration(color: moveAccent.withValues(alpha: .8), borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}
