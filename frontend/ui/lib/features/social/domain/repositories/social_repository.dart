// Repository contract for the social feature.

import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/comment_entity.dart';
import '../entities/post_entity.dart';

abstract interface class SocialRepository {
  Future<Result<PaginatedResponse<PostEntity>>> getFeed({String? cursor});

  Future<Result<PostEntity>> createPost({required String text, required List<String> tags});

  Future<Result<PostEntity>> toggleLike(String postId);

  Future<Result<CommentEntity>> addComment({required String postId, required String text});

  Future<Result<PaginatedResponse<CommentEntity>>> getComments(String postId, {String? cursor});
}
