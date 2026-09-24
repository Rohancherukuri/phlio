import 'package:equatable/equatable.dart';

class RoomMessageEntity extends Equatable {
  const RoomMessageEntity({
    required this.id,
    required this.roomId,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String roomId;
  final String authorId;
  final String text;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, roomId, authorId, text, createdAt];
}
