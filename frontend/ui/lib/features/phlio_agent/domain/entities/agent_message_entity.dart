import 'package:equatable/equatable.dart';
import 'agent_plan_entity.dart';

enum MessageRole { user, agent }

class AgentMessageEntity extends Equatable {
  const AgentMessageEntity({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.plan,
  });

  final String id;
  final String conversationId;
  final MessageRole role;
  final String text;
  final AgentPlanEntity? plan;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, conversationId, role, text, plan];
}
