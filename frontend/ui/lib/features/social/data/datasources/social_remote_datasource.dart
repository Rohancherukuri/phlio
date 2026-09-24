// Talks to `/api/v1/social/*`.

import '../../../../core/network/api_client.dart';
import '../models/comment_model.dart';
import '../models/post_model.dart';

class SocialRemoteDataSource {
  const SocialRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> getFeed({String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/social/feed',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<PostModel> createPost({required String text, required List<String> tags}) async {
    final response = await _apiClient.dio.post('/social/posts', data: {'text': text, 'tags': tags});
    return PostModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PostModel> toggleLike(String postId) async {
    final response = await _apiClient.dio.post('/social/posts/$postId/like');
    return PostModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CommentModel> addComment({required String postId, required String text}) async {
    final response = await _apiClient.dio.post('/social/posts/$postId/comments', data: {'text': text});
    return CommentModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getComments(String postId, {String? cursor}) async {
    final response = await _apiClient.dio.get(
      '/social/posts/$postId/comments',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    );
    return response.data as Map<String, dynamic>;
  }
}
