// A single chat bubble — mirrors the reference "4. PHLIO AGENT" screen:
// user messages right-aligned in a gradient bubble, agent replies
// left-aligned with the fox avatar and a dark bubble, optionally followed
// by an `AgentPlanCard`.

import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../domain/entities/agent_message_entity.dart';
import 'agent_plan_card.dart';

class AgentMessageBubble extends StatelessWidget {
  const AgentMessageBubble({required this.message, super.key});

  final AgentMessageEntity message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const PhlioFox(size: 32),
            const SizedBox(width: PhlioSpacing.sm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.md),
                  decoration: BoxDecoration(
                    gradient: isUser ? PhlioColors.brandGradient : null,
                    color: isUser ? null : PhlioColors.surfaceElevated,
                    borderRadius: PhlioRadii.lgRadius,
                  ),
                  child: Text(
                    message.text,
                    style: PhlioTypography.bodyLarge.copyWith(
                      color: isUser ? PhlioColors.textOnBrand : PhlioColors.textPrimary,
                    ),
                  ),
                ),
                if (message.plan != null)
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.78,
                    child: AgentPlanCard(plan: message.plan!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
