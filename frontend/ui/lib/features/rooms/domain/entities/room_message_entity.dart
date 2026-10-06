import 'package:equatable/equatable.dart';

/// One file or pack item riding on a room message.
///
/// `kind` drives rendering: `image` gets a visual preview, `document` a
/// branded file card, `sticker`/`gif` render the bundled Foxy asset named
/// by `value` (no bytes travel for those). `url` is origin-relative
/// (`/media/...`) for uploaded files; `localPath` is set client-side right
/// after picking so the preview renders before/without the upload.
class MessageAttachmentEntity extends Equatable {
  const MessageAttachmentEntity({
    required this.id,
    required this.kind,
    required this.name,
    this.size = 0,
    this.mime = '',
    this.url = '',
    this.value = '',
    this.localPath,
  });

  final String id;
  final String kind; // image | video | audio | document | sticker | gif
  final String name;
  final int size;
  final String mime;
  final String url;
  final String value;
  final String? localPath;

  bool get isImage => kind == 'image';
  bool get isSticker => kind == 'sticker' || kind == 'gif';

  MessageAttachmentEntity copyWith(
          {String? url, String? id, int? size, String? mime}) =>
      MessageAttachmentEntity(
        id: id ?? this.id,
        kind: kind,
        name: name,
        size: size ?? this.size,
        mime: mime ?? this.mime,
        url: url ?? this.url,
        value: value,
        localPath: localPath,
      );

  @override
  List<Object?> get props =>
      [id, kind, name, size, mime, url, value, localPath];
}

/// One reaction on a message: a unicode emoji glyph or a Foxy pack id.
class MessageReactionEntity extends Equatable {
  const MessageReactionEntity({
    required this.kind,
    required this.value,
    required this.userId,
  });

  final String kind; // emoji | sticker | gif
  final String value;
  final String userId;

  @override
  List<Object?> get props => [kind, value, userId];
}

class RoomMessageEntity extends Equatable {
  const RoomMessageEntity({
    required this.id,
    required this.roomId,
    required this.authorId,
    required this.text,
    required this.createdAt,
    this.authorName = '',
    this.attachments = const [],
    this.reactions = const [],
  });

  final String id;
  final String roomId;
  final String authorId;
  final String authorName;
  String get displayName => authorName.isNotEmpty
      ? authorName
      : authorId.replaceFirst(RegExp(r'^usr_'), '').replaceAll('_', ' ');
  final String text;
  final DateTime createdAt;
  final List<MessageAttachmentEntity> attachments;
  final List<MessageReactionEntity> reactions;

  RoomMessageEntity copyWith({List<MessageReactionEntity>? reactions}) =>
      RoomMessageEntity(
        id: id,
        roomId: roomId,
        authorId: authorId,
        authorName: authorName,
        text: text,
        createdAt: createdAt,
        attachments: attachments,
        reactions: reactions ?? this.reactions,
      );

  @override
  List<Object?> get props =>
      [id, roomId, authorId, text, createdAt, attachments, reactions];
}
