import 'package:equatable/equatable.dart';

/// What a file sent to Foxy is, as far as the chat cares.
enum AgentAttachmentKind { image, video, audio, document, text }

AgentAttachmentKind agentAttachmentKindOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => AgentAttachmentKind.image,
    'mp4' || 'mov' || 'webm' || 'm4v' => AgentAttachmentKind.video,
    'mp3' || 'm4a' || 'wav' || 'ogg' || 'aac' => AgentAttachmentKind.audio,
    'txt' || 'md' || 'csv' || 'json' => AgentAttachmentKind.text,
    _ => AgentAttachmentKind.document,
  };
}

/// File extensions Foxy accepts (mirrors backend `domains/agent/attachments.py`).
const agentImageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'];
const agentVideoExtensions = ['mp4', 'mov', 'webm', 'm4v'];
const agentAudioExtensions = ['mp3', 'm4a', 'wav', 'ogg', 'aac'];
const agentDocumentExtensions = ['pdf', 'docx', 'xlsx', 'pptx'];
const agentTextExtensions = ['txt', 'md', 'csv', 'json'];

/// A photo, clip, audio file or document uploaded to `/agent/files`.
class AgentAttachmentEntity extends Equatable {
  const AgentAttachmentEntity({
    required this.id,
    required this.kind,
    required this.name,
    required this.mime,
    required this.size,
    required this.url,
    this.pages,
    this.words,
    this.excerpt = '',
    this.localPath,
  });

  final String id;
  final AgentAttachmentKind kind;
  final String name;
  final String mime;
  final int size;

  /// Authenticated API path (`/api/v1/agent/files/<id>`).
  final String url;
  final int? pages;
  final int? words;
  final String excerpt;

  /// The file on this device, when it was picked here (for previews).
  final String? localPath;

  String get extension =>
      name.contains('.') ? name.split('.').last.toUpperCase() : kind.name.toUpperCase();

  @override
  List<Object?> get props => [id, name, size, localPath];
}

String formatAgentFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
