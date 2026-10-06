// Direct-message state (Riverpod).
//
// DMs are user-to-user conversations (blueprint section 5 — Messages/DMs
// belong to Social). The backend has no DM domain yet, so this build stage
// keeps conversations **in-memory, client-side**: they live for the session
// and reset on restart, exactly like the demo contract of the rest of the
// app. The provider API is shaped so a backend DM repository can replace
// the in-memory store without touching the UI.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/room_message_entity.dart';

@immutable
class DmMessage {
  const DmMessage({
    required this.id,
    required this.text,
    required this.isMine,
    required this.createdAt,
    this.audioPath,
    this.durationLabel,
    this.attachments = const [],
    this.reactions = const [],
  });

  final String id;
  final String text;
  final bool isMine;
  final DateTime createdAt;

  /// Voice notes carry the locally recorded file so they can be played
  /// back; null for text messages.
  final String? audioPath;
  final String? durationLabel;

  /// Files, documents, stickers and GIFs riding on this message. Picked
  /// files keep their local path so previews render without a backend.
  final List<MessageAttachmentEntity> attachments;
  final List<MessageReactionEntity> reactions;

  DmMessage withReactions(List<MessageReactionEntity> reactions) => DmMessage(
        id: id,
        text: text,
        isMine: isMine,
        createdAt: createdAt,
        audioPath: audioPath,
        durationLabel: durationLabel,
        attachments: attachments,
        reactions: reactions,
      );
}

/// In-memory DM store: `Map<username, messages>` for the session.
final dmStoreProvider =
    NotifierProvider<DmStoreController, Map<String, List<DmMessage>>>(
  DmStoreController.new,
);

class DmStoreController extends Notifier<Map<String, List<DmMessage>>> {
  var _nextId = 0;

  @override
  Map<String, List<DmMessage>> build() => {};

  List<DmMessage> messagesFor(String username) => state[username] ?? const [];

  void send(String username, String text) {
    if (text.trim().isEmpty) return;
    _append(
        username,
        DmMessage(
          id: 'dm_${_nextId++}',
          text: text.trim(),
          isMine: true,
          createdAt: DateTime.now(),
        ));
  }

  /// Sends staged attachments (picked files keep their local paths; Foxy
  /// pack items carry the pack value id) plus an optional caption.
  void sendFiles(
      String username, String text, List<MessageAttachmentEntity> attachments) {
    if (text.trim().isEmpty && attachments.isEmpty) return;
    _append(
        username,
        DmMessage(
          id: 'dm_${_nextId++}',
          text: text.trim(),
          isMine: true,
          createdAt: DateTime.now(),
          attachments: attachments,
        ));
  }

  /// Sends a recorded voice note (duration label + local file path).
  void sendVoice(String username, String durationLabel, String audioPath) {
    _append(
        username,
        DmMessage(
          id: 'dm_${_nextId++}',
          text: 'Voice message',
          isMine: true,
          createdAt: DateTime.now(),
          audioPath: audioPath,
          durationLabel: durationLabel,
        ));
  }

  /// Toggles the caller's reaction on one of their own DMs (in-memory —
  /// the real toggle lives server-side once the DM domain lands).
  void toggleReaction(
      String username, String messageId, String kind, String value) {
    final messages = state[username];
    if (messages == null) return;
    state = {
      ...state,
      username: [
        for (final message in messages)
          if (message.id == messageId)
            message.withReactions(_toggled(message.reactions, kind, value))
          else
            message,
      ],
    };
  }

  List<MessageReactionEntity> _toggled(
      List<MessageReactionEntity> reactions, String kind, String value) {
    final remaining = [
      for (final r in reactions)
        if (!(r.kind == kind && r.value == value)) r,
    ];
    if (remaining.length == reactions.length) {
      remaining
          .add(MessageReactionEntity(kind: kind, value: value, userId: 'me'));
    }
    return remaining;
  }

  void _append(String username, DmMessage message) {
    state = {
      ...state,
      username: [...state[username] ?? [], message],
    };
  }
}

/// Convenience view for one conversation.
final dmMessagesProvider =
    Provider.family<List<DmMessage>, String>((ref, username) {
  return ref.watch(dmStoreProvider)[username] ?? const [];
});
