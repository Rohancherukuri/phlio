import '../../../authentication/presentation/controllers/auth_controller.dart';
// Social feed state management (Riverpod).
//
// `FeedState` carries pagination info alongside the loaded posts so the
// screen can render a "load more" spinner without a second provider.
// Likes are applied optimistically (`PostEntity.toggleLikedOptimistically`)
// and rolled back if the request fails, so tapping the heart feels instant.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/comment_entity.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/social_repository.dart';
import '../../domain/usecases/add_comment_usecase.dart';
import '../../domain/usecases/create_post_usecase.dart';
import '../../domain/usecases/get_feed_usecase.dart';
import '../../domain/usecases/toggle_like_usecase.dart';

class FeedState {
  const FeedState(
      {required this.posts,
      required this.nextCursor,
      required this.hasMore,
      this.isLoadingMore = false});

  final List<PostEntity> posts;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;

  FeedState copyWith(
      {List<PostEntity>? posts,
      String? nextCursor,
      bool? hasMore,
      bool? isLoadingMore}) {
    return FeedState(
      posts: posts ?? this.posts,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

final socialRepositoryProvider =
    Provider<SocialRepository>((ref) => getIt<SocialRepository>());

final feedControllerProvider =
    AsyncNotifierProvider<FeedController, FeedState>(FeedController.new);

/// Posts published since the feed was loaded, waiting behind the
/// "New posts" pill (0 hides it).
final newPostsCountProvider = StateProvider<int>((ref) => 0);

/// How often the open feed checks for posts published by others.
const _newPostsInterval = Duration(seconds: 40);

/// Comments for one post, fetched when the comments sheet opens. Invalidated
/// after every successful add so the list refetches with the new comment.
final commentsProvider = FutureProvider.autoDispose
    .family<List<CommentEntity>, String>((ref, postId) async {
  final repository = ref.watch(socialRepositoryProvider);
  final result = await repository.getComments(postId);
  return result.when(
      success: (page) => page.items, failure: (failure) => throw failure);
});

class FeedController extends AsyncNotifier<FeedState> {
  late GetFeedUseCase _getFeedUseCase;
  late CreatePostUseCase _createPostUseCase;
  late ToggleLikeUseCase _toggleLikeUseCase;
  late AddCommentUseCase _addCommentUseCase;

  @override
  Future<FeedState> build() async {
    ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
    final repository = ref.read(socialRepositoryProvider);
    _getFeedUseCase = GetFeedUseCase(repository);
    _createPostUseCase = CreatePostUseCase(repository);
    _toggleLikeUseCase = ToggleLikeUseCase(repository);
    _addCommentUseCase = AddCommentUseCase(repository);

    // A saved copy may have been shown at launch (slow server): reload as
    // soon as the fresh feed arrives instead of keeping old posts on screen.
    final cache = getIt<ApiClient>().cache;
    final updates = cache.updates.where((path) => path == '/social/feed').listen((_) => _reloadQuietly());
    // Others keep posting while the feed is open: check now and then and
    // offer them behind a "New posts" pill (no jump while reading).
    final timer = Timer.periodic(_newPostsInterval, (_) => _checkForNewPosts());
    ref.onDispose(() {
      updates.cancel();
      timer.cancel();
    });

    return _loadFirstPage();
  }

  FeedState? _pending;

  Future<void> _reloadQuietly() async {
    final result = await AsyncValue.guard(_loadFirstPage);
    if (result.hasValue) state = result;
  }

  Future<void> _checkForNewPosts() async {
    final current = state.valueOrNull;
    if (current == null || state.isLoading) return;
    final result = await _getFeedUseCase();
    result.when(
      success: (page) {
        final known = {for (final p in current.posts) p.id};
        final fresh = page.items.takeWhile((p) => !known.contains(p.id)).length;
        if (fresh > 0) {
          _pending = FeedState(posts: page.items, nextCursor: page.nextCursor, hasMore: page.hasMore);
          ref.read(newPostsCountProvider.notifier).state = fresh;
        }
      },
      failure: (_) {},
    );
  }

  /// Shows the posts behind the "New posts" pill.
  Future<void> showNewPosts() async {
    final pending = _pending;
    _pending = null;
    ref.read(newPostsCountProvider.notifier).state = 0;
    if (pending != null) {
      state = AsyncData(pending);
    } else {
      await refresh();
    }
  }

  Future<FeedState> _loadFirstPage() async {
    final result = await _getFeedUseCase();
    return result.when(
      success: (page) => FeedState(
          posts: page.items,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore),
      failure: (failure) =>
          throw failure, // surfaces as AsyncError; screen shows PhlioErrorView
    );
  }

  Future<void> refresh() async {
    _pending = null;
    ref.read(newPostsCountProvider.notifier).state = 0;
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

  Future<Result<void>> createPost(String text, {String? musicId}) async {
    final result = await _createPostUseCase(text: text, musicId: musicId);
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
    final result = await _addCommentUseCase(
        postId: postId, text: text, stickerId: stickerId);
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
