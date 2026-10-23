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

import '../../../../design_system/spacing.dart';

import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../controllers/feed_controller.dart';
import '../widgets/post_card.dart';

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

  void _openComments(String postId) {
    showSocialComments(context, postId);
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedControllerProvider);

    return feedAsync.when(
      loading: () => const PhlioLoadingIndicator(),
      error: (error, _) => PhlioErrorView(
        failure: error is Failure ? error : const Failure.unknown(),
        onRetry: () => ref.read(feedControllerProvider.notifier).refresh(),
      ),
      data: (state) => RefreshIndicator(
        onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
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
            const SpacesBar(),
            for (final post in state.posts) ...[
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
  }
}
