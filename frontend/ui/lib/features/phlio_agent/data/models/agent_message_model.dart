import '../../domain/entities/agent_attachment_entity.dart';
import '../../domain/entities/agent_message_entity.dart';
import 'agent_plan_model.dart';

class AgentMessageModel {
  const AgentMessageModel({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.plan,
    this.attachments = const [],
  });

  factory AgentMessageModel.fromJson(Map<String, dynamic> json) {
    return AgentMessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      role: (json['role'] as String) == 'agent' ? MessageRole.agent : MessageRole.user,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      plan: json['plan'] != null ? AgentPlanModel.fromJson(json['plan'] as Map<String, dynamic>) : null,
      attachments: [
        for (final a in (json['attachments'] as List<dynamic>? ?? const []))
          agentAttachmentFromJson(a as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String conversationId;
  final MessageRole role;
  final String text;
  final AgentPlanModel? plan;
  final DateTime createdAt;
  final List<AgentAttachmentEntity> attachments;

  AgentMessageEntity toEntity() => AgentMessageEntity(
        id: id,
        conversationId: conversationId,
        role: role,
        text: text,
        plan: plan?.toEntity(),
        createdAt: createdAt,
        attachments: attachments,
      );
}

AgentAttachmentEntity agentAttachmentFromJson(Map<String, dynamic> json, {String? localPath}) {
  final kind = AgentAttachmentKind.values.firstWhere(
    (k) => k.name == json['kind'],
    orElse: () => AgentAttachmentKind.document,
  );
  return AgentAttachmentEntity(
    id: json['id'] as String,
    kind: kind,
    name: json['name'] as String? ?? 'file',
    mime: json['mime'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    url: json['url'] as String? ?? '',
    pages: (json['pages'] as num?)?.toInt(),
    words: (json['words'] as num?)?.toInt(),
    excerpt: json['excerpt'] as String? ?? '',
    localPath: localPath,
  );
}
