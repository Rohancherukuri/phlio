import 'playlists_screen.dart';
import '../../features/profile/presentation/widgets/snap_audience.dart';
import 'stream_screen.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';
import 'dart:ui' show FontFeature;
import 'social_comments_sheet.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/authentication/domain/entities/user_entity.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/social/presentation/controllers/video_library.dart';
import '../../features/social/presentation/controllers/video_playback_controller.dart';

final engagementProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, path) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/content/$path/engagement')).data
      as Map;
});
final contentProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, path) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final result =
      (await getIt<ApiClient>().dio.get('/content/$path')).data as Map;
  try {
    await getIt<ApiClient>().dio.put('/content/$path/actions/viewed');
  } catch (_) {}
  ref.invalidate(engagementProvider(path));
  return result;
});
final catalogProvider =
    FutureProvider.autoDispose.family<List, String>((ref, platform) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return ((await getIt<ApiClient>().dio.get('/content/$platform')).data
      as Map)['items'] as List;
});
final groupsProvider = FutureProvider.autoDispose<List>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/messaging/groups')).data as List;
});

Future<void> trackContentView(BuildContext context, String path) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await getIt<ApiClient>().dio.put('/content/$path/actions/viewed');
    container.invalidate(engagementProvider(path));
  } catch (_) {}
}

Future<void> saveContentToPlaylist(
    BuildContext context, WidgetRef ref, String path) async {
  final platform = path.split('/').first;
  final contentRef = path.substring(platform.length + 1);
  final api = getIt<ApiClient>().dio;
  try {
    final rows =
        ((await api.get('/playlists', queryParameters: {'platform': platform}))
            .data as Map)['items'] as List;
    if (!context.mounted) return;
    String? selected;
    if (rows.isNotEmpty) {
      selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                const ListTile(title: Text('Save or move to playlist')),
                for (final row in rows)
                  ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: Text(row['name'] as String),
                      subtitle: row['media_mode'] == null
                          ? null
                          : Text(row['media_mode'] as String),
                      onTap: () => Navigator.pop(c, row['id'] as String)),
                ListTile(
                    leading: const Icon(Icons.playlist_add_rounded),
                    title: const Text('New playlist'),
                    onTap: () => Navigator.pop(c, 'new')),
                ListTile(
                    leading: const Icon(Icons.bookmark_remove_outlined),
                    title: const Text('Remove bookmark'),
                    onTap: () => Navigator.pop(c, 'remove')),
              ])));
      if (selected == null || !context.mounted) return;
    }
    if (selected == 'remove') {
      final current = (await api.get('/content/$path/engagement')).data as Map;
      if (current['saved_by_me'] == true)
        await api.put('/content/$path/actions/saved');
    } else {
      if (selected == 'new') {
        final name = TextEditingController();
        final value = await showDialog<String>(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('New playlist'),
                    content: TextField(
                        controller: name,
                        maxLength: 80,
                        decoration:
                            const InputDecoration(hintText: 'Playlist name')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () {
                            if (name.text.trim().isNotEmpty)
                              Navigator.pop(c, name.text.trim());
                          },
                          child: const Text('Create'))
                    ]));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        name.dispose();
        if (value == null) return;
        selected = ((await api.post('/playlists',
                data: {'platform': platform, 'name': value}))
            .data as Map)['id'] as String;
      }
      final saved = (await api.post('/playlists/save/bookmark', data: {
        'platform': platform,
        'ref': contentRef,
        if (selected != null) 'playlist_id': selected
      }))
          .data as Map;
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Saved to ${saved['name']}'),
            action: SnackBarAction(
                label: 'Playlists',
                onPressed: () => showPlaylists(context, platform))));
    }
    ref.invalidate(engagementProvider(path));
    ref.invalidate(contentLibraryProvider);
    ref.invalidate(playlistsProvider(platform));
    ref.invalidate(playlistItemsProvider);
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not save. Choose a matching playlist and try again.')));
  }
}

/// Platforms whose engagement stays lightweight. Commerce (Shop), ticketing
/// (Book) and media catalogues (Stream) are not conversation surfaces, so
/// they don't show reposts or view counts — just likes, comments, bookmarks
/// and share.
const Set<String> lightEngagementPlatforms = {'shop', 'book', 'stream'};

/// Whether [platform] (the first segment of a content path) shows the full
/// social metric set (reposts + views).
bool platformShowsSocialMetrics(String platform) =>
    !lightEngagementPlatforms.contains(platform);

/// Shared visual tokens for every engagement row, so all eight platforms
/// render identical icon sizes, hit targets and count typography.
abstract final class _EngagementStyle {
  static const Color idle = PhlioColors.textMuted;
  static const Color like = Color(0xFFFF4F79);
  static const Color repost = PhlioColors.success;
  static const Color bookmark = PhlioColors.brandOrange;

  static const TextStyle count = TextStyle(
    fontFamily: PhlioTypography.uiFamily,
    fontSize: 12.5,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class ContentSurface extends StatelessWidget {
  const ContentSurface(
      {required this.platform,
      required this.contentId,
      required this.child,
      super.key,
      this.showEngagement = true});
  final String platform, contentId;
  final Widget child;
  final bool showEngagement;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onLongPress: () => showContentShare(context, '$platform/$contentId'),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              child,
              if (showEngagement)
                Padding(
                    padding: const EdgeInsets.only(top: PhlioSpacing.xs),
                    child: EngagementRow(path: '$platform/$contentId')),
            ]),
      );
}

/// The one engagement bar used by every Phlio platform.
///
/// Layout (single line, edge-aligned with the content above it):
///
///   [avatar stack ×3] ♥ 128            💬  ⟲ 12  ▥ 4.2K  🔖 9  ⇪ 3
///
/// * The stack shows up to three people who liked the content (you first,
///   once you've liked it) and sits immediately left of the like button.
///   Tapping the stack or the like count opens the "Likes" sheet.
/// * Shop, Book and Stream drop reposts and views (see
///   [lightEngagementPlatforms]).
/// * On narrow cards (grid tiles, horizontal rails) secondary actions are
///   shed in priority order — views, repost, comment, bookmark — so the row
///   never wraps or overflows; share and like always stay.
class EngagementRow extends ConsumerStatefulWidget {
  const EngagementRow({required this.path, this.compact = false, super.key});
  final bool compact;
  final String path;
  @override
  ConsumerState<EngagementRow> createState() => _EngagementRowState();
}

enum _ActionKind { comment, repost, views, bookmark, share }

class _EngagementAction {
  const _EngagementAction({
    required this.kind,
    required this.tooltip,
    required this.icon,
    this.activeIcon,
    this.count,
    this.active = false,
    this.activeColor = PhlioColors.brandViolet,
    this.onTap,
  });
  final _ActionKind kind;
  final String tooltip;
  final IconData icon;
  final IconData? activeIcon;
  final num? count;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;
}

class _EngagementRowState extends ConsumerState<EngagementRow> {
  bool _likeBusy = false, _actionBusy = false;
  bool? _likedOverride;
  int? _countOverride;
  bool? _repostedOverride;
  int? _repostCountOverride;

  String get _platform => widget.path.split('/').first;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Optimistic like: the heart, count and avatar stack flip instantly and
  /// reconcile with the server once the request settles.
  Future<void> _toggleLike(bool liked, int count) async {
    if (_likeBusy) return;
    HapticFeedback.lightImpact();
    final next = count + (liked ? -1 : 1);
    setState(() {
      _likeBusy = true;
      _likedOverride = !liked;
      _countOverride = next < 0 ? 0 : next;
    });
    try {
      await getIt<ApiClient>().dio.put('/content/${widget.path}/like');
      ref.invalidate(contentLibraryProvider);
      await ref.refresh(engagementProvider(widget.path).future);
    } catch (_) {
      _snack('Could not update like. Try again.');
    } finally {
      if (mounted) {
        setState(() {
          _likeBusy = false;
          _likedOverride = null;
          _countOverride = null;
        });
      }
    }
  }

  /// Optimistic repost: icon and count flip instantly, then reconcile.
  Future<void> _repost(bool reposted, int count) async {
    if (_actionBusy) return;
    HapticFeedback.selectionClick();
    final next = count + (reposted ? -1 : 1);
    setState(() {
      _actionBusy = true;
      _repostedOverride = !reposted;
      _repostCountOverride = next < 0 ? 0 : next;
    });
    try {
      await getIt<ApiClient>()
          .dio
          .put('/content/${widget.path}/actions/reposted');
      ref.invalidate(contentLibraryProvider);
      await ref.refresh(engagementProvider(widget.path).future);
    } catch (_) {
      _snack('Could not update repost. Try again.');
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
          _repostedOverride = null;
          _repostCountOverride = null;
        });
      }
    }
  }

  Future<void> _bookmark() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await saveContentToPlaylist(context, ref, widget.path);
      // Pull the new bookmark count straight away.
      await ref.refresh(engagementProvider(widget.path).future);
    } catch (_) {
      // saveContentToPlaylist reports its own errors.
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(engagementProvider(widget.path)).valueOrNull;
    final liked = _likedOverride ?? data?['liked_by_me'] == true;
    final count = _countOverride ?? (data?['count'] as num?)?.toInt() ?? 0;
    final people = likerPreview(data,
        liked: liked, me: ref.watch(authControllerProvider).valueOrNull);
    final social = platformShowsSocialMetrics(_platform);
    num? metric(String key) =>
        data == null ? null : (data[key] as num? ?? 0);

    final allActions = <_EngagementAction>[
      _EngagementAction(
          kind: _ActionKind.comment,
          tooltip: 'Comments',
          icon: Icons.chat_bubble_outline_rounded,
          count: data?['comments_count'] as num? ?? (data == null ? null : 0),
          onTap: () => showSocialComments(context, widget.path)),
      if (social)
        _EngagementAction(
            kind: _ActionKind.repost,
            tooltip: 'Repost',
            icon: Icons.repeat_rounded,
            count: _repostCountOverride ?? metric('reposts_count'),
            active: _repostedOverride ?? data?['reposted_by_me'] == true,
            activeColor: _EngagementStyle.repost,
            onTap: _actionBusy || data == null
                ? null
                : () => _repost(data['reposted_by_me'] == true,
                    (data['reposts_count'] as num? ?? 0).toInt())),
      if (social)
        _EngagementAction(
            kind: _ActionKind.views,
            tooltip: 'Views',
            icon: Icons.bar_chart_rounded,
            count: metric('views_count')),
      _EngagementAction(
          kind: _ActionKind.bookmark,
          tooltip: 'Bookmark',
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          count: metric('bookmarks_count'),
          active: data?['saved_by_me'] == true,
          activeColor: _EngagementStyle.bookmark,
          onTap: _actionBusy ? null : _bookmark),
      _EngagementAction(
          kind: _ActionKind.share,
          tooltip: 'Share',
          icon: Icons.ios_share_rounded,
          count: metric('shares_count'),
          onTap: () => showContentShare(context, widget.path)),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth =
          constraints.maxWidth.isFinite ? constraints.maxWidth : 420.0;
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final dense = widget.compact || maxWidth < 300;
      final hit = dense ? 32.0 : 38.0;
      final iconSize = dense ? 18.0 : 20.0;
      final avatarSize = dense ? 18.0 : 22.0;
      // Horizontal padding inside each action; the gaps between actions
      // come from spaceBetween, so these stay tight.
      final inset = dense ? 3.0 : 6.0;

      double countWidth(num? value) => value == null
          ? 0
          : formatEngagementCount(value).length * 7.2 * scale + 4;
      double actionWidth(_EngagementAction a) =>
          iconSize + inset * 2 + countWidth(a.count);
      double stackWidth(int n) =>
          n == 0 ? 0 : avatarSize + (n - 1) * avatarSize * .62 + 4;

      var stack = people;
      final actions = [...allActions];
      double total() =>
          stackWidth(stack.length) +
          iconSize +
          8 +
          countWidth(count) +
          actions.fold<double>(0, (sum, a) => sum + actionWidth(a)) +
          actions.length * 4; // minimum breathing room between items
      void shed(_ActionKind kind) {
        if (total() > maxWidth) actions.removeWhere((a) => a.kind == kind);
      }

      void trimStack(int to) {
        if (total() > maxWidth && stack.length > to) {
          stack = stack.sublist(0, to);
        }
      }

      // Narrow cards shed in this order; like (with its stack), comments and
      // share are the last to go.
      shed(_ActionKind.views);
      shed(_ActionKind.repost);
      trimStack(2);
      shed(_ActionKind.bookmark);
      trimStack(1);
      shed(_ActionKind.comment);

      final likeCount = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showContentLikers(context, data, count),
          child: SizedBox(
              height: hit,
              child: Center(
                  widthFactor: 1,
                  child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: _EngagementStyle.count.copyWith(
                          color: liked
                              ? _EngagementStyle.like
                              : PhlioColors.textSecondary),
                      child: Text(formatEngagementCount(count),
                          maxLines: 1)))));

      final likeGroup = Row(mainAxisSize: MainAxisSize.min, children: [
        if (stack.isNotEmpty) ...[
          Semantics(
              button: true,
              label: 'See who liked this',
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showContentLikers(context, data, count),
                  child: _LikerAvatarStack(
                      people: stack,
                      size: avatarSize,
                      ringColor:
                          Theme.of(context).scaffoldBackgroundColor))),
          SizedBox(width: dense ? 3 : 5),
        ],
        _LikeButton(
            liked: liked,
            hit: hit,
            iconSize: iconSize + 1,
            leadingEdge: stack.isEmpty,
            onTap: () => _toggleLike(liked, count)),
        likeCount,
      ]);

      // Like group on the left, actions evenly distributed to the right
      // edge — no dead gap after the like count. On very wide layouts the
      // bar is capped so icons don't drift apart.
      return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dense ? maxWidth : 560),
              child: SizedBox(
                  height: hit,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        likeGroup,
                        for (var i = 0; i < actions.length; i++)
                          _EngagementActionButton(
                              action: actions[i],
                              hit: hit,
                              iconSize: iconSize,
                              inset: inset,
                              trailingEdge: i == actions.length - 1),
                      ]))));
    });
  }
}

/// Up to three likers for the stack. Once you've liked something you lead
/// the stack, so the tap feels acknowledged before the server responds.
List<Map> likerPreview(Map? data,
    {required bool liked, UserEntity? me}) {
  // People you follow come first, then any other likers the API returned.
  final seen = <String>{};
  final people = [
    ...?(data?['follower_avatars'] as List?),
    ...?(data?['avatars'] as List?),
    ...?(data?['people'] as List?),
  ]
      .whereType<Map>()
      .where((p) => p['id'] != null && seen.add(p['id'].toString()))
      .toList();
  if (me != null) {
    people.removeWhere((p) =>
        p['id'] == me.id ||
        p['id'] == me.username ||
        p['id'] == '@${me.username}');
    if (liked) {
      people.insert(0, {
        'id': me.id,
        'display_name': me.fullName,
        'avatar_url': me.avatarUrl,
      });
    }
  }
  return people.take(3).toList();
}

void showContentLikers(BuildContext context, Map? data, int count) {
  if (data == null) return;
  final people =
      ((data['people'] as List?) ?? const []).whereType<Map>().toList();
  final hidden = count - people.length;
  showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheet).height * .7),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(
                          PhlioSpacing.xl, 0, PhlioSpacing.xl, PhlioSpacing.md),
                      child: Row(children: [
                        const Icon(Icons.favorite_rounded,
                            size: 20, color: _EngagementStyle.like),
                        const SizedBox(width: PhlioSpacing.sm),
                        Text('Likes', style: PhlioTypography.title),
                        const Spacer(),
                        Text(formatEngagementCount(count),
                            style: _EngagementStyle.count
                                .copyWith(color: PhlioColors.textMuted)),
                      ])),
                  const Divider(height: 1, color: PhlioColors.borderSubtle),
                  if (people.isEmpty && hidden <= 0)
                    Padding(
                        padding: const EdgeInsets.all(PhlioSpacing.xxl),
                        child: Text('No likes yet — be the first.',
                            textAlign: TextAlign.center,
                            style: PhlioTypography.body))
                  else
                    Flexible(
                        child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(
                                vertical: PhlioSpacing.sm),
                            itemCount: people.length + (hidden > 0 ? 1 : 0),
                            itemBuilder: (_, index) {
                              if (index == people.length) {
                                return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: PhlioSpacing.xl),
                                    leading: const CircleAvatar(
                                        radius: 20,
                                        backgroundColor:
                                            PhlioColors.surfaceElevated,
                                        child: Icon(
                                            Icons.visibility_off_outlined,
                                            size: 18,
                                            color: PhlioColors.textMuted)),
                                    title: Text(
                                        '${formatEngagementCount(hidden)} more liked privately',
                                        style: PhlioTypography.body));
                              }
                              final person = people[index];
                              final id = person['id'].toString();
                              final name =
                                  person['display_name'] as String? ?? '';
                              final handle = person['username'] as String?;
                              return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: PhlioSpacing.xl),
                                  leading: IgnorePointer(
                                      child: ContentAuthorAvatar(
                                          author: id,
                                          name: name,
                                          imageUrl:
                                              person['avatar_url'] as String?,
                                          size: 40)),
                                  title: Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: PhlioTypography.bodyStrong),
                                  subtitle: handle == null
                                      ? null
                                      : Text('@$handle',
                                          style: PhlioTypography.caption),
                                  trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                      color: PhlioColors.textMuted),
                                  onTap: () {
                                    Navigator.pop(sheet);
                                    context.push(
                                        '/creator/${Uri.encodeComponent(id)}');
                                  });
                            })),
                ]),
          ));
}

/// Up to three people who liked a piece of content, as overlapping circles —
/// the preview that sits immediately left of every like button in Phlio
/// (feeds, video pages and the clips rail alike). Once you've liked it, you
/// lead the stack. Tapping opens the "Likes" sheet. Renders nothing until
/// someone has liked the content.
class LikersAvatarStack extends ConsumerWidget {
  const LikersAvatarStack(
      {required this.path, this.size = 22, this.ringColor, super.key});
  final String path;
  final double size;

  /// Defaults to the scaffold background; pass the surface color when the
  /// stack sits on a card, or a dark tint when it sits over video.
  final Color? ringColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(engagementProvider(path)).valueOrNull;
    final people = likerPreview(data,
        liked: data?['liked_by_me'] == true,
        me: ref.watch(authControllerProvider).valueOrNull);
    if (people.isEmpty) return const SizedBox.shrink();
    return Semantics(
        button: true,
        label: 'See who liked this',
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showContentLikers(
                context, data, (data?['count'] as num?)?.toInt() ?? 0),
            child: _LikerAvatarStack(
                people: people,
                size: size,
                ringColor: ringColor ??
                    Theme.of(context).scaffoldBackgroundColor)));
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton(
      {required this.liked,
      required this.hit,
      required this.iconSize,
      required this.leadingEdge,
      required this.onTap});
  final bool liked, leadingEdge;
  final double hit, iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
        message: liked ? 'Unlike' : 'Like',
        child: Semantics(
            button: true,
            toggled: liked,
            label: 'Like',
            child: InkResponse(
                onTap: onTap,
                radius: hit * .6,
                child: SizedBox(
                    height: hit,
                    child: Padding(
                        padding: EdgeInsets.only(
                            left: leadingEdge ? 0 : 2, right: 4),
                        child: Center(
                            widthFactor: 1,
                            child: TweenAnimationBuilder<double>(
                                key: ValueKey(liked),
                                tween: Tween(begin: liked ? .6 : .85, end: 1),
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.elasticOut,
                                builder: (_, scale, child) =>
                                    Transform.scale(scale: scale, child: child),
                                child: Icon(
                                    liked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: iconSize,
                                    color: liked
                                        ? _EngagementStyle.like
                                        : PhlioColors.textSecondary))))))));
  }
}

class _EngagementActionButton extends StatelessWidget {
  const _EngagementActionButton(
      {required this.action,
      required this.hit,
      required this.iconSize,
      required this.inset,
      required this.trailingEdge});
  final _EngagementAction action;
  final double hit, iconSize, inset;
  final bool trailingEdge;

  @override
  Widget build(BuildContext context) {
    final color = action.active ? action.activeColor : _EngagementStyle.idle;
    return Tooltip(
        message: action.tooltip,
        child: Semantics(
            button: action.onTap != null,
            label: action.count == null
                ? action.tooltip
                : '${action.tooltip}, ${action.count}',
            child: InkResponse(
                onTap: action.onTap,
                radius: hit * .6,
                child: SizedBox(
                    height: hit,
                    child: Padding(
                        padding: EdgeInsets.only(
                            left: inset, right: trailingEdge ? 0 : inset),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                      scale: animation, child: child),
                              child: Icon(
                                  action.active
                                      ? action.activeIcon ?? action.icon
                                      : action.icon,
                                  key: ValueKey(action.active),
                                  size: iconSize,
                                  color: color)),
                          if (action.count != null) ...[
                            const SizedBox(width: 4),
                            Text(formatEngagementCount(action.count!),
                                maxLines: 1,
                                style: _EngagementStyle.count
                                    .copyWith(color: color)),
                          ],
                        ]))))));
  }
}

/// Up to three overlapping, ringed liker avatars — leftmost on top.
class _LikerAvatarStack extends StatelessWidget {
  const _LikerAvatarStack(
      {required this.people, required this.size, required this.ringColor});
  final List<Map> people;
  final double size;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final step = size * .62;
    return SizedBox(
        width: size + step * (people.length - 1),
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = people.length - 1; i >= 0; i--)
            Positioned(
                left: i * step,
                top: 0,
                child: Container(
                    width: size,
                    height: size,
                    padding: const EdgeInsets.all(1.5),
                    decoration:
                        BoxDecoration(color: ringColor, shape: BoxShape.circle),
                    child: IgnorePointer(
                        child: ContentAuthorAvatar(
                            author: people[i]['id'].toString(),
                            name: people[i]['display_name'] as String? ?? '',
                            imageUrl: people[i]['avatar_url'] as String?,
                            size: size - 3)))),
        ]));
  }
}

Future<void> showContentShare(BuildContext context, String path) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ShareSheet(path: path));

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.path});
  final String path;
  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  late Future<Map> destinations;
  String mode = 'dm', query = '';
  bool busy = false;
  final selected = <String>{};
  final name = TextEditingController(text: 'Shared plans');
  String? error;
  @override
  void initState() {
    super.initState();
    destinations = getIt<ApiClient>()
        .dio
        .get('/sharing/destinations')
        .then((r) => r.data as Map);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> send(String destination, String? target) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = (await getIt<ApiClient>()
              .dio
              .post('/content/${widget.path}/share', data: {
        'destination': destination,
        'target': target,
        'members': selected.toList(),
        'name': name.text.trim().isEmpty ? 'Shared plans' : name.text.trim()
      }))
          .data as Map;
      ref.invalidate(groupsProvider);
      ref.invalidate(engagementProvider(widget.path));
      ref.invalidate(contentLibraryProvider);
      if (!mounted) return;
      final parent = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      parent.pop();
      if (destination == 'group' || destination == 'new_group') {
        parent.push(MaterialPageRoute(
            builder: (_) =>
                GroupChatScreen(groupId: result['target'] as String)));
      } else
        messenger
            .showSnackBar(const SnackBar(content: Text('Content shared.')));
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Could not share. Check the recipients and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get link => 'phlio://app/shared/${widget.path}';
  Future<void> external(String action) async {
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: link));
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Link copied')));
      } else if (action == 'story') {
        final audience = await pickSnapAudience(context, const SnapAudience());
        if (audience == null) return;
        await getIt<ApiClient>().dio.post('/content/${widget.path}/story',
            data: {
              'audience': audience.mode,
              'recipients': audience.recipients
            });
        ref.invalidate(sharedStoriesProvider);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Added to your story for 24 hours')));
      } else if (action == 'whatsapp') {
        final opened = await launchUrl(Uri.https('wa.me', '/', {'text': link}),
            mode: LaunchMode.externalApplication);
        if (!opened) throw StateError('WhatsApp unavailable');
      } else {
        final box = context.findRenderObject() as RenderBox;
        final result = await SharePlus.instance.share(ShareParams(
            text: link,
            subject: 'Shared on Phlio',
            sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size));
        if (result.status != ShareResultStatus.success) return;
      }
      await getIt<ApiClient>()
          .dio
          .put('/content/${widget.path}/actions/shared');
      ref.invalidate(engagementProvider(widget.path));
    } catch (_) {
      if (mounted)
        setState(
            () => error = 'Could not complete this action. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(8))),
              Expanded(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        const Text('Share content',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.search_rounded),
                                      hintText: 'Search',
                                      filled: true,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          borderSide: BorderSide.none)),
                                  onChanged: (v) =>
                                      setState(() => query = v.toLowerCase()))),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                              tooltip: 'Create a group',
                              onPressed: busy
                                  ? null
                                  : () => setState(() => mode = 'new_group'),
                              icon: const Icon(Icons.group_add_outlined))
                        ]),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, children: [
                          for (final item in [
                            ('dm', 'Messages'),
                            ('new_group', 'New group'),
                            ('group', 'Groups'),
                            ('room', 'Rooms')
                          ])
                            ChoiceChip(
                                label: Text(item.$2),
                                selected: mode == item.$1,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() => mode = item.$1))
                        ]),
                        if (mode == 'new_group')
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextField(
                                  controller: name,
                                  maxLength: 80,
                                  decoration: const InputDecoration(
                                      labelText: 'Group name'))),
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(error!,
                                  style: const TextStyle(
                                      color: Colors.redAccent))),
                        const SizedBox(height: 20),
                        FutureBuilder<Map>(
                            future: destinations,
                            builder: (context, snapshot) {
                              if (snapshot.hasError)
                                return TextButton(
                                    onPressed: () => setState(() =>
                                        destinations = getIt<ApiClient>()
                                            .dio
                                            .get('/sharing/destinations')
                                            .then((r) => r.data as Map)),
                                    child: const Text(
                                        'Could not load recipients. Retry'));
                              if (!snapshot.hasData)
                                return const Center(
                                    child: CircularProgressIndicator());
                              final items = (snapshot.data![mode == 'room'
                                      ? 'rooms'
                                      : mode == 'group'
                                          ? 'groups'
                                          : 'people'] as List)
                                  .where((p) => (p['display_name'] ??
                                          p['name'] ??
                                          p['username'])
                                      .toString()
                                      .toLowerCase()
                                      .contains(query))
                                  .toList();
                              if (items.isEmpty)
                                return Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(mode == 'room'
                                        ? 'Join a room to share content there.'
                                        : 'No matching recipients.'));
                              return LayoutBuilder(
                                  builder: (context, bounds) =>
                                      GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: items.length,
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount:
                                                      bounds.maxWidth < 250
                                                          ? 2
                                                          : 3,
                                                  crossAxisSpacing: 12,
                                                  mainAxisSpacing: 12,
                                                  mainAxisExtent: 80 +
                                                      MediaQuery.textScalerOf(
                                                              context)
                                                          .scale(36)),
                                          itemBuilder: (context, index) {
                                            final p = items[index];
                                            final id = p['id'] as String;
                                            final label = (p['display_name'] ??
                                                p['name']) as String;
                                            return InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                onTap: busy
                                                    ? null
                                                    : () {
                                                        if (mode ==
                                                            'new_group') {
                                                          setState(() {
                                                            if (!selected
                                                                    .remove(
                                                                        id) &&
                                                                selected.length <
                                                                    20)
                                                              selected.add(id);
                                                          });
                                                        } else {
                                                          send(mode, id);
                                                        }
                                                      },
                                                child: Column(children: [
                                                  SizedBox(
                                                      height: 68,
                                                      width: 76,
                                                      child: Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            if (mode == 'dm' ||
                                                                mode ==
                                                                    'new_group')
                                                              PhlioAvatar(
                                                                  name: label,
                                                                  imageUrl: p[
                                                                          'avatar_url']
                                                                      as String?,
                                                                  size: 64)
                                                            else
                                                              CircleAvatar(
                                                                  radius: 32,
                                                                  child: Icon(
                                                                      mode == 'room'
                                                                          ? Icons
                                                                              .tag
                                                                          : Icons
                                                                              .group_outlined,
                                                                      size:
                                                                          30)),
                                                            if (selected
                                                                    .contains(
                                                                        id) &&
                                                                mode ==
                                                                    'new_group')
                                                              const Positioned(
                                                                  right: 0,
                                                                  bottom: 0,
                                                                  child: CircleAvatar(
                                                                      radius:
                                                                          12,
                                                                      child: Icon(
                                                                          Icons
                                                                              .check,
                                                                          size:
                                                                              16))),
                                                          ])),
                                                  const SizedBox(height: 8),
                                                  Text(label,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontSize: 13)),
                                                ]));
                                          }));
                            }),
                        if (mode == 'new_group')
                          FilledButton(
                              onPressed: busy || selected.length < 2
                                  ? null
                                  : () => send('new_group', null),
                              child: Text(
                                  'Create group & share (${selected.length})')),
                      ]))),
              if (busy) const LinearProgressIndicator(),
              const Divider(height: 1),
              SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Row(children: [
                        for (final item in [
                          ('story', 'Add to story',
                              Icons.add_circle_outline_rounded),
                          ('whatsapp', 'WhatsApp', Icons.chat_outlined),
                          ('copy', 'Copy link', Icons.link_rounded),
                          ('share', 'More', Icons.ios_share_rounded),
                          ('rooms', 'Rooms', Icons.tag_rounded),
                          ('saved', 'Bookmarks', Icons.bookmark_border_rounded),
                          if (platformShowsSocialMetrics(
                              widget.path.split('/').first))
                            ('reposted', 'Reposts', Icons.repeat_rounded)
                        ])
                          SizedBox(
                              width: 90,
                              child: Column(children: [
                                IconButton.filledTonal(
                                    iconSize: 24,
                                    padding: const EdgeInsets.all(16),
                                    onPressed: busy
                                        ? null
                                        : () {
                                            if (item.$1 == 'saved' ||
                                                item.$1 == 'reposted') {
                                              Navigator.of(context).push(
                                                  MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          ContentLibraryScreen(
                                                              verb: item.$1)));
                                            } else if (item.$1 == 'rooms') {
                                              setState(() => mode = 'room');
                                            } else {
                                              external(item.$1);
                                            }
                                          },
                                    icon: Icon(item.$3)),
                                const SizedBox(height: 7),
                                Text(item.$2,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12))
                              ])),
                      ]))),
            ])),
      );
}

class ContentDetailScreen extends ConsumerWidget {
  const ContentDetailScreen({required this.path, super.key});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: const Text('Shared content')),
      body: ref.watch(contentProvider(path)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) =>
              const Center(child: Text('Content is no longer available.')),
          data: (item) =>
              ListView(padding: const EdgeInsets.all(16), children: [
                if (item['image_url'] != null)
                  ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                          AppConfig.mediaUrl(item['image_url'] as String),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox(height: 120))),
                const SizedBox(height: 16),
                Text(item['title'] as String,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (item['demo'] == true)
                  const Text('Demo content', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Text(item['description'] as String? ?? ''),
                if (item['source_url'] != null)
                  TextButton.icon(
                      onPressed: () => launchUrl(
                          Uri.parse(item['source_url'] as String),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new),
                      label: Text('Read at ${item['publisher']}')),
                if ((item['media_url'] as String?)?.isNotEmpty == true)
                  FilledButton.icon(
                      onPressed: () => item['platform'] == 'stream' &&
                              ['Music', 'Podcasts']
                                  .contains(streamCategory(item))
                          ? Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => StreamScreen(initialItem: item)))
                          : ref.read(videoPlaybackProvider).open(PlayableVideo(
                              id: item['ref'] as String,
                              platform: item['platform'] as String,
                              title: item['title'] as String,
                              creator: '',
                              url: item['media_url'] as String)),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play')),
                const SizedBox(height: 8),
                EngagementRow(path: path),
                if (path.startsWith('social/')) ...[
                  const SizedBox(height: 24),
                  ContentDiscussion(contentId: path),
                ],
              ])));
}

class SharedContentText extends StatelessWidget {
  const SharedContentText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'phlio://(?:content/|app/shared/)([a-z]+)/([^\s]+)')
        .firstMatch(text);
    if (match == null) return Text(text, style: style);
    String decoded;
    try {
      decoded = Uri.decodeComponent(match[2]!);
    } on ArgumentError {
      return Text(text, style: style);
    }
    final path = '${match[1]}/$decoded';
    return OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ContentDetailScreen(path: path))),
        icon: const Icon(Icons.link),
        label: Text(text.split('\n').first,
            maxLines: 3, overflow: TextOverflow.ellipsis));
  }
}

class PlatformCatalogScreen extends ConsumerWidget {
  const PlatformCatalogScreen({required this.platform, super.key});
  final String platform;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(
          title: Text(
              'Phlio ${platform[0].toUpperCase()}${platform.substring(1)}')),
      body: ref.watch(catalogProvider(platform)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(catalogProvider(platform)),
                  child: const Text('Could not load content. Retry'))),
          data: (items) => ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final id = item['ref'] as String;
                return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ContentSurface(
                        platform: platform,
                        contentId: id,
                        child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                                onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => ContentDetailScreen(
                                            path: '$platform/$id'))),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (item['image_url'] != null)
                                        AspectRatio(
                                            aspectRatio: 16 / 9,
                                            child: Image.network(
                                                AppConfig.mediaUrl(
                                                    item['image_url']
                                                        as String),
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                        Icons.image_outlined))),
                                      Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(item['title'] as String,
                                                    style: const TextStyle(
                                                        fontSize: 19,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(height: 8),
                                                Text(
                                                    item['description']
                                                        as String,
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis)
                                              ])),
                                    ])))));
              })));
}

final groupMessagesProvider = FutureProvider.autoDispose.family<Map, String>(
    (ref, id) async =>
        (await getIt<ApiClient>().dio.get('/messaging/groups/$id/messages'))
            .data as Map);

class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({required this.groupId, super.key});
  final String groupId;
  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final text = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupMessagesProvider(widget.groupId));
    return Scaffold(
        appBar: AppBar(
            title:
                Text(state.valueOrNull?['name'] as String? ?? 'Group messages'),
            actions: [
              IconButton(
                  onPressed: () =>
                      ref.invalidate(groupMessagesProvider(widget.groupId)),
                  icon: const Icon(Icons.refresh))
            ]),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: state.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) =>
                      const Center(child: Text('Group unavailable.')),
                  data: (data) =>
                      ListView(padding: const EdgeInsets.all(16), children: [
                        for (final message in data['items'] as List)
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (message['author_profile'] != null)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Row(children: [
                                                PhlioAvatar(
                                                    name:
                                                        message['author_profile']
                                                                ['display_name']
                                                            as String,
                                                    imageUrl:
                                                        message['author_profile']
                                                                ['avatar_url']
                                                            as String?,
                                                    profileId: message['author']
                                                        as String,
                                                    size: 28),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                    child: Text(
                                                        message['author_profile']
                                                                ['display_name']
                                                            as String,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold))),
                                              ])),
                                        SharedContentText(
                                            message['text'] as String),
                                      ])))
                      ]))),
          Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        controller: text,
                        maxLines: null,
                        decoration:
                            const InputDecoration(hintText: 'Message group'))),
                IconButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (text.text.trim().isEmpty) return;
                            setState(() => busy = true);
                            try {
                              await getIt<ApiClient>().dio.post(
                                  '/messaging/groups/${widget.groupId}/messages',
                                  data: {'text': text.text.trim()});
                              text.clear();
                              ref.invalidate(
                                  groupMessagesProvider(widget.groupId));
                            } catch (_) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Message failed. Try again.')));
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.send))
              ]))
        ])));
  }
}

class GroupInboxScreen extends ConsumerWidget {
  const GroupInboxScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: const Text('Group messages')),
      body: ref.watch(groupsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(groupsProvider),
                  child: const Text('Retry'))),
          data: (groups) => groups.isEmpty
              ? const Center(
                  child: Text(
                      'Long-press content to create a group and share it.'))
              : ListView(children: [
                  for (final group in groups)
                    ListTile(
                        leading: const Icon(Icons.group),
                        title: Text(group['name'] as String),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => GroupChatScreen(
                                    groupId: group['id'] as String))))
                ])));
}

final sharedStoriesProvider = FutureProvider.autoDispose<List>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/social/shared-stories')).data
      as List;
});

class SharedStoriesScreen extends ConsumerWidget {
  const SharedStoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: const Text('Stories')),
      body: ref.watch(sharedStoriesProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(sharedStoriesProvider),
                  child: const Text('Retry stories'))),
          data: (items) => items.isEmpty
              ? const Center(
                  child: Text(
                      'Hold content and choose Add to story to share it for 24 hours.'))
              : ListView(children: [
                  for (final item in items)
                    ListTile(
                        leading: ContentAuthorAvatar(
                            author: item['author']['id'] as String,
                            name: item['author']['display_name'] as String,
                            imageUrl: item['author']['avatar_url'] as String?,
                            size: 44),
                        title: Text(item['author']['display_name'] as String),
                        subtitle: Text(item['content']['title'] as String),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ContentDetailScreen(
                                path:
                                    "${item['content']['platform']}/${item['content']['ref']}"))))
                ])));
}

final mutualsProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, target) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/social/creators/$target/mutuals'))
      .data as Map;
});

class MutualAvatars extends ConsumerWidget {
  const MutualAvatars({required this.target, super.key});
  final String target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(mutualsProvider(target)).valueOrNull;
    final known = data?['followed_by'] as Map?;
    final hasKnown = (known?['count'] as int? ?? 0) > 0;
    final people =
        (hasKnown ? known!['avatars'] : data?['avatars']) as List? ?? [];
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          SizedBox(
              width: 28 + (people.length - 1) * 18,
              height: 30,
              child: Stack(children: [
                for (var i = 0; i < people.length; i++)
                  Positioned(
                      left: i * 18.0,
                      child: ContentAuthorAvatar(
                          author: people[i]['id'] as String,
                          name: people[i]['display_name'] as String,
                          imageUrl: people[i]['avatar_url'] as String?,
                          size: 28))
              ])),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  hasKnown
                      ? 'Followed by ${people.first['display_name']}${(known!['count'] as int) > 1 ? ' and ${(known['count'] as int) - 1} others' : ''}'
                      : '${data!['count']} mutual friends',
                  style: const TextStyle(fontSize: 13))),
        ]));
  }
}

final contentLibraryProvider =
    FutureProvider.autoDispose.family<List, String>((ref, verb) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  return ((await getIt<ApiClient>().dio.get('/library/$verb')).data
      as Map)['items'] as List;
});

class ContentLibraryScreen extends ConsumerWidget {
  const ContentLibraryScreen({super.key, required this.verb});
  final String verb;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(verb == 'saved' ? 'Bookmarks' : 'Reposts')),
        body: ref.watch(contentLibraryProvider(verb)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () =>
                          ref.invalidate(contentLibraryProvider(verb)),
                      child: const Text('Try again'))),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('Nothing here yet.'))
                  : ListView(children: [
                      for (final item in items)
                        ListTile(
                            title: Text(item['title'] as String),
                            subtitle: Text(item['platform'] as String),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => ContentDetailScreen(
                                        path:
                                            '${item['platform']}/${item['ref']}')))),
                    ]),
            ),
      );
}

String formatEngagementCount(num value) {
  if (value >= 1000000)
    return '${(value / 1000000).toStringAsFixed(1).replaceAll(RegExp(r"\.0$"), "")}M';
  if (value >= 1000)
    return '${(value / 1000).toStringAsFixed(1).replaceAll(RegExp(r"\.0$"), "")}K';
  return value.toInt().toString();
}
