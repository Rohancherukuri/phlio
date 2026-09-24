// Framework-agnostic domain entity for a comment on a post.

import 'package:equatable/equatable.dart';

class CommentEntity extends Equatable {
  const CommentEntity({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String authorId;
  final String text;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, postId, authorId, text, createdAt];
}
