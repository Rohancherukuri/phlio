import 'post_composer.dart';
import '../../../../shared/realtime/spaces.dart';
import '../../../../core/result/result.dart';

import '../../../../shared/content/social_comments_sheet.dart';
// The Posts tab body: a compose prompt up top, then an infinite-scrolling
// list of post cards. Extracted from the old `SocialFeedScreen` so it can
// live inside the Social home's Posts tab (and anywhere else a feed is
// needed) without dragging a Scaffold along.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/colors.dart';
import '../../../../shared/events/festival_banner.dart';
import '../../../../design_system/spacing.dart';

import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../controllers/feed_controller.dart';
import '../../domain/entities/post_entity.dart';
import '../widgets/post_card.dart';
import 'moments_pull_gate.dart';
import '../../../phlio_agent/presentation/screens/move/move_deck.dart';
import '../../../phlio_agent/presentation/screens/move/move_social.dart' show isActivityMedia;

/// Opens the "New post" composer sheet and submits the result to the feed.
/// Public so the Social home header's + button can open it too.
Future<void> showPostComposer(BuildContext context, WidgetRef ref) =>
    Navigator.of(context, rootNavigator: true).push<void>(MaterialPageRoute(
        builder: (_) => const PostComposer(), fullscreenDialog: true));

class SocialFeedView extends ConsumerStatefulWidget {
  const SocialFeedView({super.key});

  @override
  ConsumerState<SocialFeedView> createState() => _SocialFeedViewState();
}

class _SocialFeedViewState extends ConsumerState<SocialFeedView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(feedControllerProvider.notifier).loadMore();
    }
  }

  int _autoLoads = 0; // capped, so a failing page can't be retried forever

  /// Posts for the list. Without the activity posts a page can come out
  /// nearly empty, so keep loading until there's enough to scroll.
  List<PostEntity> _listed(FeedState state, bool deckShowing) {
    final posts = deckShowing
        ? state.posts.where((p) => !p.media.any((m) => isActivityMedia(m.url))).toList()
        : state.posts;
    if (posts.length < 6 && state.hasMore && !state.isLoadingMore && _autoLoads < 6) {
      _autoLoads++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(feedControllerProvider.notifier).loadMore();
      });
    }
    return posts;
  }

  void _openComments(String postId) {
    showSocialComments(context, postId);
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedControllerProvider);
    final newPosts = ref.watch(newPostsCountProvider);
    // Activity posts move into the card stack only while the stack has
    // something to show (if /activities/feed fails, they stay in the list).
    final deckShowing = (ref.watch(moveFeedProvider).valueOrNull ?? const []).isNotEmpty;

    final feed = feedAsync.when(
      loading: () => const PhlioLoadingIndicator(),
      error: (error, _) => PhlioErrorView(
        failure: error is Failure ? error : const Failure.unknown(),
        onRetry: () => ref.read(feedControllerProvider.notifier).refresh(),
      ),
      data: (state) => RefreshIndicator(
        notificationPredicate: socialRefreshPredicate,
        onRefresh: () {
          ref.invalidate(moveFeedProvider);
          _autoLoads = 0;
          return ref.read(feedControllerProvider.notifier).refresh();
        },
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            PhlioSpacing.lg,
            PhlioSpacing.xs,
            PhlioSpacing.lg,
            PhlioSpacing.lg,
          ),
          children: [
            // Live Spaces float above the feed (X-style pill).
            // Diwali, Christmas, Eid... (nothing when no event is on).
            const FestivalBanner(platform: 'social'),
            const SpacesBar(seeAll: true),
            // Phlio Move activities as a card stack (tap to flip through);
            // they're left out of the post list below.
            const MoveActivityDeck(),
            for (final post in _listed(state, deckShowing)) ...[
              PostCard(
                post: post,
                authorName: post
                    .authorId, // resolved to a friendly name once a profile cache exists
                onToggleLike: () => ref
                    .read(feedControllerProvider.notifier)
                    .toggleLike(post.id),
                onOpenComments: () => _openComments(post.id),
              ),
              const SizedBox(height: PhlioSpacing.lg),
            ],
            if (state.isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: PhlioSpacing.lg),
                child: PhlioLoadingIndicator(),
              ),
          ],
        ),
      ),
    );
    return Stack(children: [
      feed,
      if (newPosts > 0)
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () async {
                  await ref.read(feedControllerProvider.notifier).showNewPosts();
                  if (_scrollController.hasClients) {
                    await _scrollController.animateTo(0,
                        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
                  }
                },
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: PhlioColors.brandGradient,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_upward_rounded, size: 16, color: PhlioColors.textOnBrand),
                    const SizedBox(width: 6),
                    Text(newPosts == 1 ? '1 new post' : '$newPosts new posts',
                        style: const TextStyle(color: PhlioColors.textOnBrand, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
