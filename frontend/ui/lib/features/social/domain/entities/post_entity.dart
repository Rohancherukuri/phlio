// Framework-agnostic domain entity for a social post.
// Mirrors `backend/app/domains/social/entities.py::Post`.

import 'package:equatable/equatable.dart';

enum MediaKind { image, video }

class MediaAttachmentEntity extends Equatable {
  const MediaAttachmentEntity({required this.url, required this.kind});

  final String url;
  final MediaKind kind;

  @override
  List<Object?> get props => [url, kind];
}

class PostEntity extends Equatable {
  const PostEntity({
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

  final String id;
  final String authorId;
  final String text;
  final List<MediaAttachmentEntity> media;
  final List<String> tags;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final bool likedByMe;

  /// Returns a copy with the like fields flipped — used for optimistic UI
  /// updates in `presentation/controllers/feed_controller.dart` so a tap
  /// feels instant instead of waiting on a round trip.
  PostEntity toggleLikedOptimistically() {
    return PostEntity(
      id: id,
      authorId: authorId,
      text: text,
      media: media,
      tags: tags,
      likeCount: likedByMe ? likeCount - 1 : likeCount + 1,
      commentCount: commentCount,
      createdAt: createdAt,
      likedByMe: !likedByMe,
    );
  }

  @override
  List<Object?> get props => [id, authorId, text, likeCount, commentCount, likedByMe];
}
