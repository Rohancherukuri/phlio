import '../../domain/entities/comment_entity.dart';

class CommentModel {
  const CommentModel({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      authorId: json['author_id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String postId;
  final String authorId;
  final String text;
  final DateTime createdAt;

  CommentEntity toEntity() =>
      CommentEntity(id: id, postId: postId, authorId: authorId, text: text, createdAt: createdAt);
}
