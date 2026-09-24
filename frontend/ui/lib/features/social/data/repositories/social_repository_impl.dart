import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../../domain/entities/comment_entity.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/social_repository.dart';
import '../datasources/social_remote_datasource.dart';
import '../models/comment_model.dart';
import '../models/post_model.dart';

class SocialRepositoryImpl implements SocialRepository {
  const SocialRepositoryImpl(this._remoteDataSource);

  final SocialRemoteDataSource _remoteDataSource;

  @override
  Future<Result<PaginatedResponse<PostEntity>>> getFeed({String? cursor}) async {
    try {
      final json = await _remoteDataSource.getFeed(cursor: cursor);
      final page = PaginatedResponse<PostEntity>.fromJson(
        json,
        (item) => PostModel.fromJson(item).toEntity(),
      );
      return Result.success(page);
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<PostEntity>> createPost({required String text, required List<String> tags}) async {
    try {
      final post = await _remoteDataSource.createPost(text: text, tags: tags);
      return Result.success(post.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<PostEntity>> toggleLike(String postId) async {
    try {
      final post = await _remoteDataSource.toggleLike(postId);
      return Result.success(post.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<CommentEntity>> addComment({required String postId, required String text}) async {
    try {
      final comment = await _remoteDataSource.addComment(postId: postId, text: text);
      return Result.success(comment.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<PaginatedResponse<CommentEntity>>> getComments(String postId, {String? cursor}) async {
    try {
      final json = await _remoteDataSource.getComments(postId, cursor: cursor);
      final page = PaginatedResponse<CommentEntity>.fromJson(
        json,
        (item) => CommentModel.fromJson(item).toEntity(),
      );
      return Result.success(page);
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
