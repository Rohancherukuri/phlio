// The Posts tab body: a compose prompt up top, then an infinite-scrolling
// list of post cards. Extracted from the old `SocialFeedScreen` so it can
// live inside the Social home's Posts tab (and anywhere else a feed is
// needed) without dragging a Scaffold along.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CommentsSheet(postId: postId),
    );
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

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.postId});

  final String postId;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _controller = TextEditingController();
  String? _selectedStickerId;
  bool _isSubmitting = false;
  bool _showStickerTray = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _selectedStickerId == null) || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    final result = await ref.read(feedControllerProvider.notifier).addComment(
        postId: widget.postId, text: text, stickerId: _selectedStickerId);
    if (!mounted) return;
    result.when(
      success: (_) {
        _controller.clear();
        setState(() => _selectedStickerId = null);
        FocusScope.of(context).unfocus();
      },
      failure: (failure) => showErrorSnackBar(context, failure),
    );
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.postId));
    final currentUser = ref.watch(authControllerProvider).valueOrNull;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: PhlioColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: PhlioSpacing.sm),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: PhlioColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(PhlioSpacing.lg),
                child: Row(
                  children: [
                    Text('Comments', style: PhlioTypography.headline),
                    const Spacer(),
                    const PhlioFox(
                        size: 30, pose: PhlioFoxPose.coffee, animate: false),
                  ],
                ),
              ),
              Expanded(
                child: commentsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => PhlioErrorView(
                    failure: e is Failure ? e : const Failure.unknown(),
                    onRetry: () =>
                        ref.invalidate(commentsProvider(widget.postId)),
                  ),
                  data: (comments) {
                    if (comments.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const PhlioFox(size: 88, pose: PhlioFoxPose.hello),
                            const SizedBox(height: PhlioSpacing.md),
                            Text('No comments yet',
                                style: PhlioTypography.title),
                            const SizedBox(height: PhlioSpacing.xs),
                            Text('Be the first - Foxy is watching.',
                                style: PhlioTypography.body),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: PhlioSpacing.xl),
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: PhlioSpacing.lg),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                // Commenter profile from their avatar.
                                onTap: () => context
                                    .push('/creator/${comment.authorId}'),
                                child: PhlioAvatar(
                                    name: comment.authorId, size: 32),
                              ),
                              const SizedBox(width: PhlioSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (comment.stickerId != null) ...[
                                      PhlioStickerView(
                                          stickerId: comment.stickerId!,
                                          size: 56),
                                      if (comment.text.isNotEmpty)
                                        const SizedBox(height: PhlioSpacing.xs),
                                    ],
                                    if (comment.text.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: PhlioSpacing.md,
                                          vertical: PhlioSpacing.sm,
                                        ),
                                        decoration: BoxDecoration(
                                          color: PhlioColors.surfaceElevated,
                                          borderRadius: PhlioRadii.mdRadius,
                                        ),
                                        child: Text(comment.text,
                                            style: PhlioTypography.body),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_showStickerTray)
                Container(
                  height: 108,
                  decoration: const BoxDecoration(
                    color: PhlioColors.surfaceElevated,
                    border: Border(
                        top: BorderSide(color: PhlioColors.borderSubtle)),
                  ),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(PhlioSpacing.md),
                    scrollDirection: Axis.horizontal,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 1,
                      mainAxisSpacing: PhlioSpacing.sm,
                    ),
                    itemCount: PhlioStickers.catalog.length,
                    itemBuilder: (context, index) {
                      final sticker = PhlioStickers.catalog[index];
                      final selected = _selectedStickerId == sticker.id;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedStickerId = selected ? null : sticker.id;
                        }),
                        child: Container(
                          width: 72,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? PhlioColors.brandOrange
                                    .withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: PhlioRadii.mdRadius,
                            border: Border.all(
                              color: selected
                                  ? PhlioColors.brandOrange
                                  : Colors.transparent,
                            ),
                          ),
                          child: Tooltip(
                            message: sticker.label,
                            child: PhlioStickerView(
                                stickerId: sticker.id, size: 56),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_selectedStickerId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: PhlioSpacing.xl, vertical: PhlioSpacing.xs),
                  child: Row(
                    children: [
                      PhlioStickerView(
                          stickerId: _selectedStickerId!, size: 36),
                      const SizedBox(width: PhlioSpacing.sm),
                      Text('Sticker attached', style: PhlioTypography.caption),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _selectedStickerId = null),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: PhlioColors.textMuted),
                      ),
                    ],
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PhlioSpacing.lg,
                    PhlioSpacing.sm,
                    PhlioSpacing.lg,
                    PhlioSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.emoji_emotions_outlined,
                          color: _showStickerTray
                              ? PhlioColors.brandOrange
                              : PhlioColors.textMuted,
                        ),
                        tooltip: 'Foxy stickers',
                        onPressed: () => setState(
                            () => _showStickerTray = !_showStickerTray),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: PhlioTypography.body,
                          decoration: InputDecoration(
                            hintText: currentUser != null
                                ? 'Add a comment, ${currentUser.fullName.split(' ').first}...'
                                : 'Add a comment...',
                            border: InputBorder.none,
                            filled: true,
                            fillColor: PhlioColors.surfaceInput,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: PhlioSpacing.md,
                              vertical: PhlioSpacing.sm,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded,
                                color: PhlioColors.brandOrange),
                        onPressed: _isSubmitting ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
