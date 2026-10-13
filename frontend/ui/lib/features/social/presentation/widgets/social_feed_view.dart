import '../../../../shared/content/social_comments_sheet.dart';
// The Posts tab body: a compose prompt up top, then an infinite-scrolling
// list of post cards. Extracted from the old `SocialFeedScreen` so it can
// live inside the Social home's Posts tab (and anywhere else a feed is
// needed) without dragging a Scaffold along.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../controllers/feed_controller.dart';
import '../widgets/post_card.dart';

/// Opens the "New post" composer sheet and submits the result to the feed.
/// Public so the Social home header's + button can open it too.
Future<void> showPostComposer(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final text = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: PhlioSpacing.xl,
        right: PhlioSpacing.xl,
        top: PhlioSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + PhlioSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New post', style: PhlioTypography.headline),
          const SizedBox(height: PhlioSpacing.lg),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            style: PhlioTypography.bodyLarge,
            decoration: const InputDecoration(
              hintText: "What's on your mind?",
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: PhlioSpacing.lg),
          PhlioPrimaryButton(
            label: 'Post',
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
      ),
    ),
  );

  if (text == null || text.isEmpty) return;
  final result =
      await ref.read(feedControllerProvider.notifier).createPost(text);
  if (result.isFailure && context.mounted) {
    showErrorSnackBar(
        context,
        result.when(
          success: (_) => const Failure.unknown(),
          failure: (failure) => failure,
        ));
  }
}

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
