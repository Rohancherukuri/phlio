// Social feed state management (Riverpod).
//
// `FeedState` carries pagination info alongside the loaded posts so the
// screen can render a "load more" spinner without a second provider.
// Likes are applied optimistically (`PostEntity.toggleLikedOptimistically`)
// and rolled back if the request fails, so tapping the heart feels instant.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/comment_entity.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/social_repository.dart';
import '../../domain/usecases/add_comment_usecase.dart';
import '../../domain/usecases/create_post_usecase.dart';
import '../../domain/usecases/get_feed_usecase.dart';
import '../../domain/usecases/toggle_like_usecase.dart';

class FeedState {
  const FeedState({required this.posts, required this.nextCursor, required this.hasMore, this.isLoadingMore = false});

  final List<PostEntity> posts;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;

  FeedState copyWith({List<PostEntity>? posts, String? nextCursor, bool? hasMore, bool? isLoadingMore}) {
    return FeedState(
      posts: posts ?? this.posts,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) => getIt<SocialRepository>());

final feedControllerProvider = AsyncNotifierProvider<FeedController, FeedState>(FeedController.new);

/// Comments for one post, fetched when the comments sheet opens. Invalidated
/// after every successful add so the list refetches with the new comment.
final commentsProvider = FutureProvider.autoDispose
    .family<List<CommentEntity>, String>((ref, postId) async {
  final repository = ref.watch(socialRepositoryProvider);
  final result = await repository.getComments(postId);
  return result.when(success: (page) => page.items, failure: (failure) => throw failure);
});

class FeedController extends AsyncNotifier<FeedState> {
  late final GetFeedUseCase _getFeedUseCase;
  late final CreatePostUseCase _createPostUseCase;
  late final ToggleLikeUseCase _toggleLikeUseCase;
  late final AddCommentUseCase _addCommentUseCase;

  @override
  Future<FeedState> build() async {
    final repository = ref.read(socialRepositoryProvider);
    _getFeedUseCase = GetFeedUseCase(repository);
    _createPostUseCase = CreatePostUseCase(repository);
    _toggleLikeUseCase = ToggleLikeUseCase(repository);
    _addCommentUseCase = AddCommentUseCase(repository);

    return _loadFirstPage();
  }

  Future<FeedState> _loadFirstPage() async {
    final result = await _getFeedUseCase();
    return result.when(
      success: (page) => FeedState(posts: page.items, nextCursor: page.nextCursor, hasMore: page.hasMore),
      failure: (failure) => throw failure, // surfaces as AsyncError; screen shows PhlioErrorView
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading<FeedState>().copyWithPrevious(state);
    state = await AsyncValue.guard(_loadFirstPage);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    final result = await _getFeedUseCase(cursor: current.nextCursor);
    result.when(
      success: (page) {
        state = AsyncData(
          current.copyWith(
            posts: [...current.posts, ...page.items],
            nextCursor: page.nextCursor,
            hasMore: page.hasMore,
            isLoadingMore: false,
          ),
        );
      },
      failure: (_) => state = AsyncData(current.copyWith(isLoadingMore: false)),
    );
  }

  Future<Result<void>> createPost(String text) async {
    final result = await _createPostUseCase(text: text);
    return result.when(
      success: (post) {
        final current = state.valueOrNull;
        if (current != null) {
          state = AsyncData(current.copyWith(posts: [post, ...current.posts]));
        }
        return const Result.success(null);
      },
      failure: (failure) => Result.failure(failure),
    );
  }

  Future<void> toggleLike(String postId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // Optimistic update first.
    final optimisticPosts = [
      for (final post in current.posts)
        if (post.id == postId) post.toggleLikedOptimistically() else post,
    ];
    state = AsyncData(current.copyWith(posts: optimisticPosts));

    final result = await _toggleLikeUseCase(postId);
    result.when(
      success: (serverPost) {
        final reconciled = [
          for (final post in optimisticPosts)
            if (post.id == postId) serverPost else post,
        ];
        state = AsyncData(current.copyWith(posts: reconciled));
      },
      failure: (_) {
        // Roll back — the request failed, so keep the pre-tap state.
        state = AsyncData(current);
      },
    );
  }

  Future<Result<void>> addComment({
    required String postId,
    required String text,
    String? stickerId,
  }) async {
    final result = await _addCommentUseCase(postId: postId, text: text, stickerId: stickerId);
    return result.when(
      success: (_) {
        ref.invalidate(commentsProvider(postId));
        final current = state.valueOrNull;
        if (current != null) {
          final updated = [
            for (final post in current.posts)
              if (post.id == postId)
                PostEntity(
                  id: post.id,
                  authorId: post.authorId,
                  text: post.text,
                  media: post.media,
                  tags: post.tags,
                  likeCount: post.likeCount,
                  commentCount: post.commentCount + 1,
                  createdAt: post.createdAt,
                  likedByMe: post.likedByMe,
                )
              else
                post,
          ];
          state = AsyncData(current.copyWith(posts: updated));
        }
        return const Result.success(null);
      },
      failure: (failure) => Result.failure(failure),
    );
  }
}
