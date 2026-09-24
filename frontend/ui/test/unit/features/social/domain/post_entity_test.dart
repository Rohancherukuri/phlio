// Tests for `PostEntity.toggleLikedOptimistically` — the optimistic-UI
// helper `FeedController` depends on (see
// `features/social/presentation/controllers/feed_controller.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/social/domain/entities/post_entity.dart';

PostEntity _buildPost({int likeCount = 5, bool likedByMe = false}) {
  return PostEntity(
    id: 'pst_test',
    authorId: 'usr_test',
    text: 'A post used only in tests.',
    media: const [],
    tags: const ['test'],
    likeCount: likeCount,
    commentCount: 0,
    createdAt: DateTime(2026, 1, 1),
    likedByMe: likedByMe,
  );
}

void main() {
  group('toggleLikedOptimistically', () {
    test('flips likedByMe from false to true and increments the count', () {
      final post = _buildPost(likeCount: 5, likedByMe: false);
      final toggled = post.toggleLikedOptimistically();
      expect(toggled.likedByMe, isTrue);
      expect(toggled.likeCount, 6);
    });

    test('flips likedByMe from true to false and decrements the count', () {
      final post = _buildPost(likeCount: 5, likedByMe: true);
      final toggled = post.toggleLikedOptimistically();
      expect(toggled.likedByMe, isFalse);
      expect(toggled.likeCount, 4);
    });

    test('is reversible — toggling twice returns to the original state', () {
      final original = _buildPost(likeCount: 8, likedByMe: false);
      final toggledTwice = original.toggleLikedOptimistically().toggleLikedOptimistically();
      expect(toggledTwice.likedByMe, original.likedByMe);
      expect(toggledTwice.likeCount, original.likeCount);
    });

    test('preserves every other field unchanged', () {
      final post = _buildPost();
      final toggled = post.toggleLikedOptimistically();
      expect(toggled.id, post.id);
      expect(toggled.text, post.text);
      expect(toggled.tags, post.tags);
      expect(toggled.commentCount, post.commentCount);
    });
  });

  group('Equatable props', () {
    test('two posts with the same key fields are equal', () {
      final a = _buildPost(likeCount: 3, likedByMe: true);
      final b = _buildPost(likeCount: 3, likedByMe: true);
      expect(a, equals(b));
    });

    test('posts with different like counts are not equal', () {
      final a = _buildPost(likeCount: 3);
      final b = _buildPost(likeCount: 4);
      expect(a, isNot(equals(b)));
    });
  });
}
