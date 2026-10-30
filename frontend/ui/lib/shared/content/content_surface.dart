import 'stream_title_details.dart';
import 'dart:async';
import 'package:dio/dio.dart' show DioException;
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
import '../../design_system/widgets/phlio_icons.dart';
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
import '../../features/social/presentation/widgets/social_clips_grid.dart'
    show openClipsPlayer;
import '../../app/platform/phlio_platform.dart' show PhlioPlatform;
import '../../app/shell/platform_home_screen.dart' show switchPlatform;

final engagementProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, path) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  // Keep counts and liker avatars warm for 5 minutes after the last card
  // using them scrolls away, so stacks re-appear instantly instead of
  // refetching on every scroll. Invalidation still refreshes immediately.
  final link = ref.keepAlive();
  Timer? expiry;
  ref.onCancel(() => expiry = Timer(const Duration(minutes: 5), link.close));
  ref.onResume(() => expiry?.cancel());
  ref.onDispose(() => expiry?.cancel());
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
  final items = <dynamic>[];
  String? cursor;
  do {
    final page = (await getIt<ApiClient>().dio.get('/content/$platform',
            queryParameters: {
          'limit': 100,
          if (cursor != null) 'cursor': cursor
        }))
        .data as Map;
    items.addAll(page['items'] as List);
    cursor = page['next_cursor'] as String?;
  } while (platform == 'stream' && cursor != null && items.length < 1000);
  return items;
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
    num? metric(String key) => data == null ? null : (data[key] as num? ?? 0);

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
          icon: PhlioIcons.send,
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
                      child:
                          Text(formatEngagementCount(count), maxLines: 1)))));

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
                      ringColor: Theme.of(context).scaffoldBackgroundColor))),
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
List<Map> likerPreview(Map? data, {required bool liked, UserEntity? me}) {
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
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .7),
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
                                    contentPadding: const EdgeInsets.symmetric(
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
                ringColor:
                    ringColor ?? Theme.of(context).scaffoldBackgroundColor)));
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
                              child: PhlioIcon(
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

/// One recipient in the share grid: a person, an existing group or a room.
class _Recipient {
  const _Recipient(this.kind, this.data);
  final String kind; // 'dm' | 'group' | 'room'
  final Map data;
  String get id => data['id'].toString();
  String get key => '$kind:$id';
  String get label =>
      (data['display_name'] ?? data['name'] ?? data['username'] ?? '')
          .toString();
}

/// Share sheet: search · people/groups/rooms grid (tap avatars to select)
/// · then "Write a message…", **Send separately** and **Create group chat**
/// (2+ people). With nothing selected, the external row shows instead.
class _ShareSheetState extends ConsumerState<_ShareSheet> {
  late Future<Map> destinations;
  String query = '';
  bool busy = false;
  final selected = <String, _Recipient>{};
  final message = TextEditingController();
  String? error;

  static const _violet = PhlioColors.brandViolet;

  @override
  void initState() {
    super.initState();
    destinations = _load();
  }

  Future<Map> _load() => getIt<ApiClient>()
      .dio
      .get('/sharing/destinations')
      .then((r) => r.data as Map);

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  List<_Recipient> get _people =>
      selected.values.where((r) => r.kind == 'dm').toList();
  bool get _canGroup =>
      _people.length >= 2 && _people.length == selected.length;

  void _toggle(_Recipient r) => setState(() {
        if (selected.remove(r.key) == null && selected.length < 20) {
          selected[r.key] = r;
        }
      });

  Future<Map> _post(String destination,
          {String? target,
          List<String> members = const [],
          String? name}) async =>
      (await getIt<ApiClient>()
              .dio
              .post('/content/${widget.path}/share', data: {
        'destination': destination,
        'target': target,
        'members': members,
        if (name != null) 'name': name,
        if (message.text.trim().isNotEmpty) 'message': message.text.trim(),
      }))
          .data as Map;

  void _refresh() {
    ref.invalidate(groupsProvider);
    ref.invalidate(engagementProvider(widget.path));
    ref.invalidate(contentLibraryProvider);
  }

  Future<void> _sendSeparately() async {
    setState(() {
      busy = true;
      error = null;
    });
    var failed = 0;
    String? reason;
    for (final r in selected.values) {
      try {
        await _post(r.kind, target: r.id);
      } on DioException catch (e) {
        failed++;
        final data = e.response?.data;
        if (data is Map && data['detail'] is String) {
          reason = data['detail'] as String;
        } else if (data is Map && data['error'] is Map) {
          reason = (data['error'] as Map)['message'] as String?;
        }
      } catch (_) {
        failed++;
      }
    }
    _refresh();
    if (!mounted) return;
    setState(() => busy = false);
    if (failed == selected.length) {
      setState(() => error =
          reason ?? 'Could not send. Check your connection and try again.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final only = selected.length == 1 ? selected.values.first : null;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
        content: Text(failed == 0
            ? 'Sent to ${only != null ? only.label : '${selected.length} chats'}'
            : 'Sent, but $failed could not be delivered.'),
        action: only != null && only.kind == 'dm' && failed == 0
            ? SnackBarAction(
                label: 'View',
                onPressed: () => router.push(
                    '/dm/${Uri.encodeComponent((only.data['username'] ?? only.id).toString())}'))
            : null));
  }

  Future<void> _createGroup() async {
    setState(() {
      busy = true;
      error = null;
    });
    final people = _people;
    final name = people.map((p) => p.label.split(' ').first).join(', ');
    try {
      final result = await _post('new_group',
          members: [for (final p in people) p.id],
          name: name.length > 80 ? '${name.substring(0, 77)}…' : name);
      _refresh();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(MaterialPageRoute(
          builder: (_) =>
              GroupChatScreen(groupId: result['target'] as String)));
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not create the group. Try again.';
        });
      }
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

  Widget _avatar(_Recipient r) {
    if (r.kind == 'dm') {
      return PhlioAvatar(
          name: r.label, imageUrl: r.data['avatar_url'] as String?, size: 76);
    }
    final faces =
        ((r.data['avatars'] as List?) ?? const []).whereType<Map>().toList();
    if (r.kind == 'group' && faces.length >= 2) {
      // Two overlapping faces, like a group chat.
      return SizedBox(
        width: 80,
        height: 76,
        child: Stack(children: [
          Positioned(
              left: 0,
              top: 0,
              child: PhlioAvatar(
                  name: faces[0]['display_name'] as String? ?? '',
                  imageUrl: faces[0]['avatar_url'] as String?,
                  size: 54)),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2.5),
              decoration:
                  const BoxDecoration(color: _sheetBg, shape: BoxShape.circle),
              child: PhlioAvatar(
                  name: faces[1]['display_name'] as String? ?? '',
                  imageUrl: faces[1]['avatar_url'] as String?,
                  size: 54),
            ),
          ),
        ]),
      );
    }
    return CircleAvatar(
        radius: 38,
        backgroundColor: PhlioColors.surfaceElevated,
        child: Icon(r.kind == 'room' ? Icons.tag_rounded : Icons.group_rounded,
            size: 32, color: PhlioColors.textSecondary));
  }

  static const _sheetBg = Color(0xFF111925);

  @override
  Widget build(BuildContext context) {
    final hasSelection = selected.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                    onChanged: (v) => setState(() => query = v.toLowerCase()),
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Search',
                        filled: true,
                        fillColor: PhlioColors.surfaceElevated,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none))),
              ),
              const SizedBox(width: 12),
              Material(
                color: PhlioColors.surfaceElevated,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Tap two or more people, then Create group chat.'))),
                  child: const SizedBox(
                      width: 50,
                      height: 50,
                      child: Icon(Icons.group_add_outlined,
                          color: PhlioColors.textPrimary)),
                ),
              ),
            ]),
          ),
          if (error != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(error!,
                    style: const TextStyle(color: PhlioColors.danger))),
          Expanded(
            child: FutureBuilder<Map>(
              future: destinations,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: TextButton(
                          onPressed: () =>
                              setState(() => destinations = _load()),
                          child: const Text('Could not load people. Retry')));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                final all = [
                  for (final g in (data['groups'] as List? ?? const []))
                    _Recipient('group', g as Map),
                  for (final p in (data['people'] as List? ?? const []))
                    _Recipient('dm', p as Map),
                  for (final r in (data['rooms'] as List? ?? const []))
                    _Recipient('room', r as Map),
                ]
                    .where((r) => '${r.label} ${r.data['username'] ?? ''}'
                        .toLowerCase()
                        .contains(query))
                    .toList();
                if (all.isEmpty) {
                  return const Center(child: Text('No matching people.'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: all.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 8,
                      mainAxisExtent:
                          92 + MediaQuery.textScalerOf(context).scale(58)),
                  itemBuilder: (_, index) {
                    final r = all[index];
                    final on = selected.containsKey(r.key);
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: busy ? null : () => _toggle(r),
                      child: Column(children: [
                        SizedBox(
                          width: 84,
                          height: 80,
                          child: Stack(alignment: Alignment.center, children: [
                            AnimatedScale(
                                scale: on ? .94 : 1,
                                duration: const Duration(milliseconds: 150),
                                child: IgnorePointer(child: _avatar(r))),
                            if (on)
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                      color: _violet,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: _sheetBg, width: 2.5)),
                                  child: const Icon(Icons.check_rounded,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Text(r.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14)),
                        // Who this is to you, so a follower is easy to spot.
                        if (r.kind == 'dm' && r.data['relation'] != null)
                          Text(
                              r.data['recent'] == true
                                  ? 'Recent chat'
                                  : r.data['relation'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: r.data['relation'] == 'Suggested'
                                      ? PhlioColors.textMuted
                                      : PhlioColors.brandPeach)),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1, color: PhlioColors.borderSubtle),
          SafeArea(
            top: false,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: hasSelection
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                          controller: message,
                          enabled: !busy,
                          maxLength: 1000,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              hintText: 'Write a message…',
                              counterText: '',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 14)),
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: _violet,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: busy ? null : _sendSeparately,
                            child: Text(
                                selected.length == 1
                                    ? 'Send'
                                    : 'Send separately',
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: PhlioColors.textPrimary,
                                side: BorderSide(
                                    color: _canGroup
                                        ? PhlioColors.textPrimary
                                        : PhlioColors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: busy || !_canGroup ? null : _createGroup,
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _SelectedFaces(people: _people),
                                  const SizedBox(width: 10),
                                  const Text('Create group chat',
                                      style: TextStyle(fontSize: 17)),
                                ]),
                          ),
                        ),
                      ]),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Row(children: [
                        for (final item in [
                          (
                            'story',
                            'Add to story',
                            Icons.add_circle_outline_rounded
                          ),
                          ('whatsapp', 'WhatsApp', Icons.chat_outlined),
                          ('copy', 'Copy link', Icons.link_rounded),
                          ('share', 'More', Icons.ios_share_rounded),
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
                      ]),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Up to three overlapping faces of the selected people (Create group chat).
class _SelectedFaces extends StatelessWidget {
  const _SelectedFaces({required this.people});
  final List<_Recipient> people;
  @override
  Widget build(BuildContext context) {
    final faces = people.take(3).toList();
    if (faces.isEmpty) return const SizedBox.shrink();
    const size = 26.0;
    return SizedBox(
      width: size + (faces.length - 1) * 16,
      height: size,
      child: Stack(children: [
        for (var i = faces.length - 1; i >= 0; i--)
          Positioned(
            left: i * 16.0,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(
                  color: Color(0xFF111925), shape: BoxShape.circle),
              child: PhlioAvatar(
                  name: faces[i].label,
                  imageUrl: faces[i].data['avatar_url'] as String?,
                  size: size - 3),
            ),
          ),
      ]),
    );
  }
}

// -- Shared content in DMs -------------------------------------------------------

final _sharedLink =
    RegExp(r'phlio://(?:content/|app/shared/)([a-z]+)/([^\s]+)');

/// `platform/ref` of the first Phlio content link in [text], if any.
String? sharedContentPath(String text) {
  final match = _sharedLink.firstMatch(text);
  if (match == null) return null;
  try {
    return '${match[1]}/${Uri.decodeComponent(match[2]!)}';
  } on ArgumentError {
    return null;
  }
}

/// The message text without the share boilerplate ("Shared: …" + link).
String sharedContentCaption(String text) => text
    .split('\n')
    .where(
        (line) => !_sharedLink.hasMatch(line) && !line.startsWith('Shared: '))
    .join('\n')
    .trim();

/// Content preview for share cards — no "viewed" side effect.
final sharedPreviewProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, path) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  return (await getIt<ApiClient>().dio.get('/content/$path')).data as Map;
});

/// Opens a shared Phlio object where it lives: switches to its platform
/// (Social, Shop, Book, Stream, News…), then plays clips in the Clips player,
/// videos in the Social video player, and opens everything else on its
/// detail page on top of that platform's home.
Future<void> openSharedContent(
    BuildContext context, WidgetRef ref, String path) async {
  final platformName = path.split('/').first;
  final contentRef = path.substring(platformName.length + 1);
  final router = GoRouter.of(context);
  final playback = ref.read(videoPlaybackProvider);
  final videoApi = ref.read(socialVideoApiProvider);
  final target =
      PhlioPlatform.values.where((p) => p.name == platformName).firstOrNull;
  if (target != null) switchPlatform(context, target);
  if (platformName == 'social') {
    var preview = ref.read(sharedPreviewProvider(path)).valueOrNull;
    try {
      preview ??=
          (await getIt<ApiClient>().dio.get('/content/$path')).data as Map;
    } catch (_) {}
    final kind = (preview?['kind'] as String?)?.toLowerCase() ?? '';
    if (kind == 'clip' && context.mounted) {
      // Like Reels in Instagram DMs: plays over the chat, back returns here.
      await openClipsPlayer(context, initialClipId: contentRef);
      return;
    }
    if (kind == 'video') {
      try {
        final videos = await videoApi.videos();
        final match = videos
            .where((v) => v.id == contentRef || v.contentId == contentRef)
            .firstOrNull;
        if (match != null) {
          router.go('/home');
          await playback.open(match);
          return;
        }
      } catch (_) {}
    }
  }
  router.go('/home');
  router.push('/shared/$path');
}

/// Instagram-style shared-post card for DMs: author header, media (with a
/// play glyph for videos and clips) or a text excerpt, and quick actions
/// (send on, save) floating beside it.
class SharedContentCard extends ConsumerWidget {
  const SharedContentCard({required this.path, required this.mine, super.key});
  final String path;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sharedPreviewProvider(path));
    final item = state.valueOrNull;
    final author = item?['author'] as Map?;
    final image = item?['image_url'] as String?;
    final kind = (item?['kind'] as String?)?.toLowerCase() ?? '';
    final playable = kind == 'clip' ||
        kind == 'video' ||
        (item?['media_url'] as String?)?.isNotEmpty == true;
    final text = ((item?['description'] as String?)?.isNotEmpty == true
            ? item!['description']
            : item?['title'] ?? '')
        .toString();

    final card = GestureDetector(
      onTap: () => openSharedContent(context, ref, path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 264),
          color: const Color(0xFF26292F),
          child: state.hasError
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('This content is no longer available.',
                      style: TextStyle(color: PhlioColors.textMuted)))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(children: [
                        if (author != null)
                          PhlioAvatar(
                              name: author['display_name'] as String? ?? '',
                              imageUrl: author['avatar_url'] as String?,
                              size: 32)
                        else
                          CircleAvatar(
                              radius: 16,
                              backgroundColor: PhlioColors.surfaceElevated,
                              child: Icon(_platformIcon(path),
                                  size: 16, color: PhlioColors.textMuted)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              author?['username'] as String? ??
                                  'Phlio ${path.split('/').first[0].toUpperCase()}${path.split('/').first.substring(1)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                    if (item == null)
                      const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()))
                    else if (image != null && image.isNotEmpty)
                      AspectRatio(
                        aspectRatio: kind == 'clip' ? 4 / 5 : 1,
                        child: Stack(fit: StackFit.expand, children: [
                          Image.network(AppConfig.mediaUrl(image),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFF1B1E23))),
                          if (playable) ...[
                            const Center(
                                child: Icon(Icons.play_arrow_rounded,
                                    size: 64,
                                    color: Colors.white,
                                    shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 12)
                                ])),
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Icon(
                                    kind == 'clip'
                                        ? Icons.movie_filter_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 18,
                                    color: Colors.black),
                              ),
                            ),
                          ],
                        ]),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                        child: Text(text,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, height: 1.35)),
                      ),
                    if (item != null &&
                        image != null &&
                        image.isNotEmpty &&
                        text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        child: Text(text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                color: PhlioColors.textSecondary)),
                      ),
                  ],
                ),
        ),
      ),
    );

    // Forward / save live in the long-press menu (like Instagram DMs).
    return card;
  }

  static IconData _platformIcon(String path) => switch (path.split('/').first) {
        'shop' => Icons.shopping_bag_outlined,
        'book' => Icons.local_activity_outlined,
        'stream' => Icons.play_circle_outline_rounded,
        'news' => Icons.newspaper_outlined,
        _ => Icons.public_rounded,
      };
}

class ContentDetailScreen extends ConsumerWidget {
  const ContentDetailScreen({required this.path, super.key});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(
          title: Text(
              path.startsWith('stream/') ? 'Title details' : 'Shared content')),
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
                if (item['platform'] == 'stream')
                  StreamTitleDetails(item: item),
                if (item['source_url'] != null)
                  TextButton.icon(
                      onPressed: () => launchUrl(
                          Uri.parse(item['source_url'] as String),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(
                          '${item['platform'] == 'stream' ? 'Source' : 'Read at'}: ${item['publisher']}')),
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
                    icon: const PhlioSendIcon())
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
