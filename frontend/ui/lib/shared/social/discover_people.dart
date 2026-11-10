// Discover people — Instagram's "Suggested for you", in Phlio's style.
//
//   [ Edit profile ] [ Share profile ] [🌐]     your profile
//   [ Follow ]       [ Message ]       [🌐]     someone else's profile
//
// The globe button opens a strip of suggestion cards under the buttons:
//
//   Discover people                                         See all
//   ┌──────────┐ ┌──────────┐ ┌──────────┐
//   │        ✕ │ │        ✕ │ │        ✕ │
//   │   (◉)    │ │   (◉)    │ │   (◉)    │
//   │  Name    │ │  Name    │ │  Name    │
//   │ ◉◉ Fol-  │ │ Follows  │ │ Popular  │
//   │ lowed by │ │   you    │ │ on Phlio │
//   │ [Follow] │ │[Follow b]│ │ [Follow] │
//   └──────────┘ └──────────┘ └──────────┘
//
// Data: GET /social/suggestions[?for_user=handle] (mutual-first ranking),
// ✕ → POST /social/suggestions/{id}/dismiss, Follow → PUT/DELETE
// /social/creators/{username}/follow.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/social/presentation/controllers/video_library.dart';

/// Suggestions for you (`null`) or accounts similar to `forUser`.
final suggestionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, forUser) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final response = await getIt<ApiClient>().dio.get('/social/suggestions',
      queryParameters: {
        'limit': 30,
        if (forUser != null) 'for_user': forUser,
      });
  return ((response.data as Map)['items'] as List)
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
});

// -- The globe icon ------------------------------------------------------------

/// An earth with a latitude/longitude grid (the "discover" glyph).
class EarthGridIcon extends StatelessWidget {
  const EarthGridIcon({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
            painter: _EarthGridPainter(
                color ?? IconTheme.of(context).color ?? Colors.white)),
      );
}

class _EarthGridPainter extends CustomPainter {
  _EarthGridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final c = Offset(12 * s, 12 * s);
    final r = 9.2 * s;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, paint);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * s;
    // Meridians: ellipses of shrinking width.
    for (final w in [0.0, .45, .8]) {
      if (w == 0) {
        canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), thin);
      } else {
        canvas.drawOval(
            Rect.fromCenter(center: c, width: 2 * r * w, height: 2 * r), thin);
      }
    }
    // Parallels: equator plus two either side (curving like a globe).
    for (final t in [-0.55, 0.0, 0.55]) {
      final y = c.dy + r * t;
      final half = r * math.sqrt(1 - t * t);
      final path = Path()
        ..moveTo(c.dx - half, y)
        ..quadraticBezierTo(c.dx, y + (t == 0 ? 0 : r * .18 * t.sign), c.dx + half, y);
      canvas.drawPath(path, thin);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EarthGridPainter old) => old.color != color;
}

/// The square button beside Share profile / Message.
class DiscoverToggleButton extends StatelessWidget {
  const DiscoverToggleButton(
      {super.key, required this.open, required this.onTap, this.height = 44});
  final bool open;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: open ? 'Hide suggestions' : 'Discover people',
        child: Material(
          color: open
              ? PhlioColors.brandViolet.withValues(alpha: .2)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: open ? PhlioColors.brandViolet : PhlioColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: height,
              height: height,
              child: Center(
                child: EarthGridIcon(
                    size: 22,
                    color: open
                        ? PhlioColors.brandLavender
                        : PhlioColors.textPrimary),
              ),
            ),
          ),
        ),
      );
}

// -- Shared follow / dismiss state ----------------------------------------------

/// Usernames followed or dismissed from suggestions in this session, so the
/// strip and the See all page agree.
final _followedProvider = StateProvider<Set<String>>((ref) => {});
final _dismissedProvider = StateProvider<Set<String>>((ref) => {});

Future<void> _toggleFollow(
    BuildContext context, WidgetRef ref, Map<String, dynamic> person) async {
  final username = '${person['username']}';
  final followed = ref.read(_followedProvider);
  final on = !followed.contains(username);
  ref.read(_followedProvider.notifier).state = on
      ? {...followed, username}
      : ({...followed}..remove(username));
  try {
    await ref.read(socialVideoApiProvider).follow(username, on);
    ref.invalidate(creatorFollowingProvider);
  } catch (_) {
    ref.read(_followedProvider.notifier).state = followed;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update follow. Try again.')));
    }
  }
}

Future<void> _dismiss(WidgetRef ref, Map<String, dynamic> person) async {
  final username = '${person['username']}';
  ref.read(_dismissedProvider.notifier).state = {
    ...ref.read(_dismissedProvider),
    username
  };
  try {
    await getIt<ApiClient>()
        .dio
        .post('/social/suggestions/${Uri.encodeComponent(username)}/dismiss');
  } catch (_) {
    // Hidden for this session either way.
  }
}

// -- Strip ------------------------------------------------------------------------

/// The suggestion cards that open under the profile buttons.
class DiscoverPeoplePanel extends ConsumerWidget {
  const DiscoverPeoplePanel({super.key, this.forUser});

  /// Someone else's profile: "Suggested for you" based on them.
  final String? forUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(suggestionsProvider(forUser));
    final dismissed = ref.watch(_dismissedProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
                forUser == null ? 'Discover people' : 'Suggested for you',
                style: PhlioTypography.bodyStrong
                    .copyWith(fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DiscoverPeopleScreen(forUser: forUser))),
            style: TextButton.styleFrom(
                foregroundColor: PhlioColors.brandLavender,
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            child: const Text('See all'),
          ),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 236,
          child: data.when(
            loading: () => const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(suggestionsProvider(forUser)),
                  child: const Text('Could not load suggestions. Retry')),
            ),
            data: (items) {
              final shown = items
                  .where((p) => !dismissed.contains('${p['username']}'))
                  .toList();
              if (shown.isEmpty) {
                return Center(
                    child: Text("You're all caught up",
                        style: PhlioTypography.caption));
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _SuggestionCard(person: shown[i]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _MutualFaces extends StatelessWidget {
  const _MutualFaces({required this.people, this.size = 18});
  final List<Map<String, dynamic>> people;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(2).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final step = size * .6;
    return SizedBox(
      width: size + step * (shown.length - 1) + 2,
      height: size + 2,
      child: Stack(children: [
        for (final (i, p) in shown.indexed)
          Positioned(
            left: i * step,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: const BoxDecoration(
                  color: PhlioColors.surface, shape: BoxShape.circle),
              child: PhlioAvatar(
                  profileId: '${p['id']}',
                  name: '${p['display_name'] ?? p['username']}',
                  imageUrl: p['avatar_url'] as String?,
                  size: size,
                  showMomentRing: false),
            ),
          ),
      ]),
    );
  }
}

List<Map<String, dynamic>> _mutuals(Map<String, dynamic> person) =>
    (person['mutuals'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.person, this.expand = false});
  final Map<String, dynamic> person;
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(_followedProvider).contains('${person['username']}');
    final label = on
        ? 'Following'
        : person['reason'] == 'Follows you'
            ? 'Follow back'
            : 'Follow';
    final button = Material(
      color: on ? PhlioColors.surfaceElevated : PhlioColors.brandViolet,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleFollow(context, ref, person),
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(label,
                  style: PhlioTypography.label.copyWith(
                      fontWeight: FontWeight.w800,
                      color: on ? PhlioColors.textPrimary : Colors.white)),
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.person});
  final Map<String, dynamic> person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = '${person['display_name'] ?? person['username']}';
    final mutuals = _mutuals(person);
    return SizedBox(
      width: 158,
      child: Material(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(
              '/creator/${Uri.encodeComponent('${person['username']}')}'),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              child: Column(children: [
                PhlioAvatar(
                    profileId: '${person['id']}',
                    name: name,
                    imageUrl: person['avatar_url'] as String?,
                    size: 78),
                const SizedBox(height: 10),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.label
                        .copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (mutuals.isNotEmpty) ...[
                        _MutualFaces(people: mutuals, size: 16),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text('${person['reason'] ?? 'Suggested for you'}',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: PhlioTypography.caption
                                .copyWith(fontSize: 11.5)),
                      ),
                    ],
                  ),
                ),
                _FollowButton(person: person, expand: true),
              ]),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: () => _dismiss(ref, person),
                icon: const Icon(Icons.close_rounded,
                    color: PhlioColors.textMuted),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// -- See all ----------------------------------------------------------------------

class DiscoverPeopleScreen extends ConsumerWidget {
  const DiscoverPeopleScreen({super.key, this.forUser});
  final String? forUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(suggestionsProvider(forUser));
    final dismissed = ref.watch(_dismissedProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(forUser == null ? 'Discover people' : 'Suggested for you'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
              onPressed: () => ref.invalidate(suggestionsProvider(forUser)),
              child: const Text('Could not load suggestions. Retry')),
        ),
        data: (items) {
          final shown = items
              .where((p) => !dismissed.contains('${p['username']}'))
              .toList();
          if (shown.isEmpty) {
            return Center(
                child: Text("You're all caught up",
                    style: PhlioTypography.body));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(suggestionsProvider(forUser)),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final p = shown[i];
                final name = '${p['display_name'] ?? p['username']}';
                final mutuals = _mutuals(p);
                return ListTile(
                  onTap: () => context.push(
                      '/creator/${Uri.encodeComponent('${p['username']}')}'),
                  leading: PhlioAvatar(
                      profileId: '${p['id']}',
                      name: name,
                      imageUrl: p['avatar_url'] as String?,
                      size: 48),
                  title: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.label
                          .copyWith(fontWeight: FontWeight.w800)),
                  subtitle: Row(children: [
                    if (mutuals.isNotEmpty) ...[
                      _MutualFaces(people: mutuals, size: 16),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                          '@${p['username']} · ${p['reason'] ?? 'Suggested for you'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.caption),
                    ),
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _FollowButton(person: p),
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: () => _dismiss(ref, p),
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: PhlioColors.textMuted),
                    ),
                  ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
