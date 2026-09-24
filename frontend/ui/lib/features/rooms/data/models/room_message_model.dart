import '../../domain/entities/room_message_entity.dart';

class RoomMessageModel {
  const RoomMessageModel({
    required this.id,
    required this.roomId,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  factory RoomMessageModel.fromJson(Map<String, dynamic> json) {
    return RoomMessageModel(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      authorId: json['author_id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String roomId;
  final String authorId;
  final String text;
  final DateTime createdAt;

  RoomMessageEntity toEntity() =>
      RoomMessageEntity(id: id, roomId: roomId, authorId: authorId, text: text, createdAt: createdAt);
}
