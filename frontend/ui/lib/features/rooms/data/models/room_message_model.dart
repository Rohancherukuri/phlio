import '../../domain/entities/room_message_entity.dart';

class RoomMessageModel {
  const RoomMessageModel({
    required this.id,
    required this.roomId,
    required this.authorId,
    required this.text,
    required this.createdAt,
    this.authorName = '',
    this.attachments = const [],
    this.reactions = const [],
  });

  factory RoomMessageModel.fromJson(Map<String, dynamic> json) {
    return RoomMessageModel(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      attachments: ((json['attachments'] as List<dynamic>?) ?? const [])
          .map((a) => MessageAttachmentEntity(
                id: a['id'] as String? ?? '',
                kind: a['kind'] as String? ?? 'document',
                name: a['name'] as String? ?? 'file',
                size: (a['size'] as num?)?.toInt() ?? 0,
                mime: a['mime'] as String? ?? '',
                url: a['url'] as String? ?? '',
                value: a['value'] as String? ?? '',
              ))
          .toList(),
      reactions: ((json['reactions'] as List<dynamic>?) ?? const [])
          .map((r) => MessageReactionEntity(
                kind: r['kind'] as String? ?? 'emoji',
                value: r['value'] as String? ?? '',
                userId: r['user_id'] as String? ?? '',
              ))
          .toList(),
    );
  }

  final String id;
  final String roomId;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;
  final List<MessageAttachmentEntity> attachments;
  final List<MessageReactionEntity> reactions;

  RoomMessageEntity toEntity() => RoomMessageEntity(
        id: id,
        roomId: roomId,
        authorId: authorId,
        authorName: authorName,
        text: text,
        createdAt: createdAt,
        attachments: attachments,
        reactions: reactions,
      );
}
