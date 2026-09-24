// Social feed screen — mirrors the reference "3. SOCIAL" screen's "For
// You" feed: a compose prompt up top, then an infinite-scrolling list of
// post cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../controllers/feed_controller.dart';
import '../widgets/post_card.dart';

class SocialFeedScreen extends ConsumerStatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  ConsumerState<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends ConsumerState<SocialFeedScreen> {
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
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 200) {
      ref.read(feedControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _openComposer() async {
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

    if (text == null || text.isEmpty || !mounted) return;
    final result = await ref.read(feedControllerProvider.notifier).createPost(text);
    if (!mounted) return;
    result.when(success: (_) {}, failure: (failure) => showErrorSnackBar(context, failure));
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
    final currentUser = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Social', style: PhlioTypography.displayMedium)),
      body: feedAsync.when(
        loading: () => const PhlioLoadingIndicator(),
        error: (error, _) => PhlioErrorView(
          failure: error is Failure ? error : const Failure.unknown(),
          onRetry: () => ref.read(feedControllerProvider.notifier).refresh(),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(PhlioSpacing.lg),
            children: [
              PhlioCard(
                onTap: _openComposer,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentUser != null ? "Share something, ${currentUser.fullName.split(' ').first}..." : 'Share something...',
                        style: PhlioTypography.body,
                      ),
                    ),
                    const Icon(Icons.edit_outlined, color: PhlioColors.textMuted, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: PhlioSpacing.lg),
              for (final post in state.posts) ...[
                PostCard(
                  post: post,
                  authorName: post.authorId, // resolved to a friendly name once a profile cache exists
                  onToggleLike: () => ref.read(feedControllerProvider.notifier).toggleLike(post.id),
                  onOpenComments: () => _openComments(post.id),
                ),
                const SizedBox(height: PhlioSpacing.lg),
              ],
              if (state.isLoadingMore) const Padding(
                padding: EdgeInsets.symmetric(vertical: PhlioSpacing.lg),
                child: PhlioLoadingIndicator(),
              ),
            ],
          ),
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
  bool _isSubmitting = false;

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSubmitting = true);
    final result = await ref
        .read(feedControllerProvider.notifier)
        .addComment(postId: widget.postId, text: text);
    if (!mounted) return;
    result.when(
      success: (_) {
        _controller.clear();
        FocusScope.of(context).unfocus();
      },
      failure: (failure) => showErrorSnackBar(context, failure),
    );
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(PhlioSpacing.xl),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: PhlioTypography.body,
                decoration: const InputDecoration(hintText: 'Add a comment...', border: InputBorder.none),
              ),
            ),
            IconButton(
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: PhlioColors.brandPurple),
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
