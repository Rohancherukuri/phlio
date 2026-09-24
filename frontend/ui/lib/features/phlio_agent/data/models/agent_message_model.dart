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
  });

  factory AgentMessageModel.fromJson(Map<String, dynamic> json) {
    return AgentMessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      role: (json['role'] as String) == 'agent' ? MessageRole.agent : MessageRole.user,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      plan: json['plan'] != null ? AgentPlanModel.fromJson(json['plan'] as Map<String, dynamic>) : null,
    );
  }

  final String id;
  final String conversationId;
  final MessageRole role;
  final String text;
  final AgentPlanModel? plan;
  final DateTime createdAt;

  AgentMessageEntity toEntity() => AgentMessageEntity(
        id: id,
        conversationId: conversationId,
        role: role,
        text: text,
        plan: plan?.toEntity(),
        createdAt: createdAt,
      );
}
