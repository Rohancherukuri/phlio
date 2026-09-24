import '../../domain/entities/post_entity.dart';

class MediaAttachmentModel {
  const MediaAttachmentModel({required this.url, required this.kind});

  factory MediaAttachmentModel.fromJson(Map<String, dynamic> json) {
    return MediaAttachmentModel(
      url: json['url'] as String,
      kind: (json['kind'] as String) == 'video' ? MediaKind.video : MediaKind.image,
    );
  }

  final String url;
  final MediaKind kind;

  MediaAttachmentEntity toEntity() => MediaAttachmentEntity(url: url, kind: kind);
}

class PostModel {
  const PostModel({
    required this.id,
    required this.authorId,
    required this.text,
    required this.media,
    required this.tags,
    required this.likeCount,
    required this.commentCount,
    required this.createdAt,
    required this.likedByMe,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    return PostModel(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      text: json['text'] as String,
      media: (json['media'] as List<dynamic>? ?? [])
          .map((m) => MediaAttachmentModel.fromJson(m as Map<String, dynamic>))
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      likeCount: json['like_count'] as int,
      commentCount: json['comment_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      likedByMe: json['liked_by_me'] as bool? ?? false,
    );
  }

  final String id;
  final String authorId;
  final String text;
  final List<MediaAttachmentModel> media;
  final List<String> tags;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final bool likedByMe;

  PostEntity toEntity() => PostEntity(
        id: id,
        authorId: authorId,
        text: text,
        media: media.map((m) => m.toEntity()).toList(),
        tags: tags,
        likeCount: likeCount,
        commentCount: commentCount,
        createdAt: createdAt,
        likedByMe: likedByMe,
      );
}
