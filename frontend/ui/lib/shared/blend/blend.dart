// Blend (Instagram-style) for Phlio Social: a shared feed of posts, videos
// and clips for you and a friend, made from what you both like.
//
//   [BlendsScreen]        your Blends + start a new one (search people)
//   [BlendScreen]         one Blend: the two of you, hashtags you share, and
//                         the feed (All / Posts / Videos / Clips), each tile
//                         saying why it's there ("You both liked",
//                         "Liked by Neha", "You both like #travel")
//   [BlendInviteCard]     the invite card in a DM (Join / Open)
//   [startBlendWith]      invite someone from their DM or profile
//
// Backend: backend/app/api/v1/blends.py.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../content/mentions.dart' show searchMentionPeople;
import 'package:phlio/core/network/media_cache.dart';

final _dio = getIt<ApiClient>().dio;

const _blendGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF8D78FF), Color(0xFFFF5FA2), Color(0xFFFFB58F)],
);

/// Invite [username] to a Blend (or open the one you already have).
Future<void> startBlendWith(BuildContext context, String username) async {
  try {
    final res = await _dio.post('/blends', data: {'username': username});
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    await openBlend(context, '${(res.data as Map)['id']}');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not start a Blend.')));
    }
  }
}

Future<void> openBlend(BuildContext context, String id) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(builder: (_) => BlendScreen(blendId: id)));

Future<void> openBlends(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const BlendsScreen()));

/// Two faces overlapping on a gradient ring — the Blend mark.
class BlendFaces extends StatelessWidget {
  const BlendFaces({required this.a, required this.b, this.size = 44, super.key});
  final Map? a, b;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.6,
        height: size,
        child: Stack(children: [
          for (final (i, p) in [a, b].indexed)
            Positioned(
              left: i * size * .6,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _blendGradient),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: PhlioColors.background),
                  child: PhlioAvatar(
                      name: '${p?['display_name'] ?? p?['username'] ?? ''}',
                      imageUrl: p?['avatar_url'] as String?,
                      size: size - 8,
                      showMomentRing: false),
                ),
              ),
            ),
        ]),
      );
}

// -- your Blends ------------------------------------------------------------------------------------------

class BlendsScreen extends StatefulWidget {
  const BlendsScreen({super.key});
  @override
  State<BlendsScreen> createState() => _BlendsScreenState();
}

class _BlendsScreenState extends State<BlendsScreen> {
  late Future<List<Map>> _blends = _load();
  List<Map> _people = [];
  final _search = TextEditingController();

  Future<List<Map>> _load() async =>
      (((await _dio.get('/blends')).data as Map)['items'] as List).cast<Map>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find(String q) async {
    final found = q.trim().isEmpty ? <Map>[] : (await searchMentionPeople(q.trim())).cast<Map>();
    if (mounted) setState(() => _people = found);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Blends')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: _blendGradient, borderRadius: BorderRadius.circular(24)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.join_inner_rounded, color: Colors.white, size: 30),
              SizedBox(height: 8),
              Text('Blend your feeds', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              SizedBox(height: 4),
              Text('A shared feed of posts, videos and clips made from what you and a friend both like.',
                  style: TextStyle(color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            onChanged: _find,
            decoration: InputDecoration(
              hintText: 'Start a Blend with…',
              prefixIcon: const Icon(Icons.person_search_rounded),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
          for (final p in _people)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PhlioAvatar(name: '${p['display_name'] ?? p['username']}', imageUrl: p['avatar_url'] as String?, size: 42, showMomentRing: false),
              title: Text('${p['display_name'] ?? p['username']}'),
              subtitle: Text('@${p['username']}'),
              trailing: FilledButton(onPressed: () => startBlendWith(context, '${p['username']}'), child: const Text('Blend')),
            ),
          const SizedBox(height: 18),
          const Text('Your Blends', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          FutureBuilder<List<Map>>(
            future: _blends,
            builder: (context, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              final items = snap.data!;
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No Blends yet. Search a friend above.', style: TextStyle(color: Colors.white54)),
                );
              }
              return Column(children: [
                for (final b in items)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: BlendFaces(a: b['me'] as Map?, b: b['partner'] as Map?, size: 40),
                    title: Text('You and ${(b['partner'] as Map?)?['display_name'] ?? (b['partner'] as Map?)?['username'] ?? ''}'),
                    subtitle: Text(b['status'] == 'active'
                        ? 'Blend'
                        : b['invited_by_me'] == true
                            ? 'Waiting for them to join'
                            : 'Invited you'),
                    onTap: () async {
                      await openBlend(context, '${b['id']}');
                      if (mounted) setState(() => _blends = _load());
                    },
                  ),
              ]);
            },
          ),
        ]),
      );
}

// -- one Blend ---------------------------------------------------------------------------------------------

class BlendScreen extends StatefulWidget {
  const BlendScreen({required this.blendId, super.key});
  final String blendId;
  @override
  State<BlendScreen> createState() => _BlendScreenState();
}

class _BlendScreenState extends State<BlendScreen> {
  String _kind = 'all';
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _dio.get('/blends/${widget.blendId}', queryParameters: {'kind': _kind});
      if (mounted) setState(() => _data = (res.data as Map).cast<String, dynamic>());
    } catch (_) {
      if (mounted) setState(() => _data = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    await _dio.post('/blends/${widget.blendId}/accept');
    HapticFeedback.mediumImpact();
    _load();
  }

  Future<void> _leave() async {
    await _dio.delete('/blends/${widget.blendId}');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final partner = d?['partner'] as Map?;
    final name = '${partner?['display_name'] ?? partner?['username'] ?? ''}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blend'),
        actions: [
          if (d != null)
            PopupMenuButton<String>(
              onSelected: (_) => _leave(),
              itemBuilder: (_) => [const PopupMenuItem(value: 'leave', child: Text('Leave Blend'))],
            ),
        ],
      ),
      body: d == null
          ? Center(child: _loading ? const CircularProgressIndicator() : const Text('This Blend is no longer available.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(
                  child: Column(children: [
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: .6, end: 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutBack,
                      builder: (_, t, child) => Transform.scale(scale: t, child: child),
                      child: BlendFaces(a: d['me'] as Map?, b: partner, size: 78),
                    ),
                    const SizedBox(height: 12),
                    Text('You and $name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                        d['status'] == 'active'
                            ? 'Posts, videos and clips from what you both like'
                            : d['invited_by_me'] == true
                                ? 'Waiting for $name to join your Blend'
                                : '$name invited you to Blend',
                        style: const TextStyle(color: Colors.white60)),
                    if (d['status'] != 'active' && d['invited_by_me'] != true) ...[
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(gradient: _blendGradient, borderRadius: BorderRadius.circular(22)),
                        child: TextButton(
                          onPressed: _accept,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: Text('Join Blend', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ],
                    if ((d['shared_tags'] as List? ?? const []).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                          for (final t in (d['shared_tags'] as List))
                            Chip(label: Text('#$t'), visualDensity: VisualDensity.compact),
                        ]),
                      ),
                    if (d['status'] == 'active')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('All')),
                            ButtonSegment(value: 'post', label: Text('Posts')),
                            ButtonSegment(value: 'video', label: Text('Videos')),
                            ButtonSegment(value: 'clip', label: Text('Clips')),
                          ],
                          selected: {_kind},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) {
                            setState(() => _kind = s.first);
                            _load();
                          },
                        ),
                      ),
                  ]),
                ),
                if (d['status'] == 'active')
                  if ((d['items'] as List).isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Like and save a few posts, videos and clips — your Blend fills up from both of you.',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(2),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: .62),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _BlendTile(item: (d['items'] as List)[i] as Map, index: i),
                          childCount: (d['items'] as List).length,
                        ),
                      ),
                    ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ]),
            ),
    );
  }
}

class _BlendTile extends StatelessWidget {
  const _BlendTile({required this.item, required this.index});
  final Map item;
  final int index;
  @override
  Widget build(BuildContext context) {
    final image = item['image_url'] as String?;
    final type = '${item['object_type']}';
    final by = (item['by'] as List? ?? const []).cast<Map>();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + 30 * index.clamp(0, 15)),
      builder: (_, t, child) => Opacity(opacity: t, child: child),
      child: GestureDetector(
        onTap: () => context.push('/shared/social/${Uri.encodeComponent('${item['ref']}')}'),
        child: Stack(fit: StackFit.expand, children: [
          if (image != null && image.isNotEmpty)
            CachedNetworkImage(cacheManager: PhlioMediaCache.images, imageUrl: AppConfig.mediaUrl(image), fit: BoxFit.cover)
          else
            DecoratedBox(
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2A2350), Color(0xFF13182A)])),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Center(
                  child: Text('${item['description'] ?? item['title'] ?? ''}',
                      maxLines: 6, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),
          if (type != 'social.post')
            Positioned(
              top: 6,
              right: 6,
              child: Icon(type == 'social.clip' ? Icons.slow_motion_video_rounded : Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 20),
            ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [.55, 1], colors: [Colors.transparent, Colors.black87]),
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Row(children: [
              for (final p in by.take(2))
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: PhlioAvatar(
                      name: '${p['display_name'] ?? p['username'] ?? ''}',
                      imageUrl: p['avatar_url'] as String?,
                      size: 18,
                      showMomentRing: false),
                ),
              const SizedBox(width: 3),
              Expanded(
                child: Text('${item['reason']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// -- DM card ---------------------------------------------------------------------------------------------------

/// The Blend id in a "phlio-blend:<id>" DM message.
String? blendIdIn(String? text) => RegExp(r'phlio-blend:([A-Za-z0-9]+)').firstMatch(text ?? '')?.group(1);

class BlendInviteCard extends StatelessWidget {
  const BlendInviteCard({required this.blendId, required this.mine, super.key});
  final String blendId;
  final bool mine;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => openBlend(context, blendId),
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: _blendGradient, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.join_inner_rounded, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(mine ? 'You invited them to a Blend' : 'Let’s make a Blend',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('A shared feed of posts, videos and clips you both like.', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Text(mine ? 'Open Blend' : 'Join Blend',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
}
