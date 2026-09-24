// Renders an `AgentPlanEntity` — mirrors the reference "4. PHLIO AGENT"
// screen's plan card: a list of recommended items, an estimated total, and
// a gradient "Book This Plan" CTA.
//
// The CTA is intentionally inert in this build stage (shows a "coming
// soon" message) rather than silently doing nothing or, worse, pretending
// to book something — payments/booking are a later build stage, and the
// agent must never imply it took an action it didn't (see
// `backend/app/domains/agent/service.py`'s guardrail docstring).

import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../domain/entities/agent_plan_entity.dart';

class AgentPlanCard extends StatelessWidget {
  const AgentPlanCard({required this.plan, super.key});

  final AgentPlanEntity plan;

  @override
  Widget build(BuildContext context) {
    if (plan.items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: PhlioSpacing.sm),
      padding: const EdgeInsets.all(PhlioSpacing.lg),
      decoration: BoxDecoration(
        color: PhlioColors.surfaceElevated,
        borderRadius: PhlioRadii.xlRadius,
        border: Border.all(color: PhlioColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in plan.items) ...[
            _PlanItemRow(item: item),
            if (item != plan.items.last) const Divider(height: PhlioSpacing.xl, color: PhlioColors.borderSubtle),
          ],
          const SizedBox(height: PhlioSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.md, vertical: PhlioSpacing.sm),
            decoration: BoxDecoration(color: PhlioColors.surfaceInput, borderRadius: PhlioRadii.mdRadius),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated total', style: PhlioTypography.label),
                Text(
                  plan.displayEstimatedRange,
                  style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.brandOrange),
                ),
              ],
            ),
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioPrimaryButton(
            label: 'Book This Plan',
            size: PhlioButtonSize.medium,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Booking is on the roadmap — this plan is a preview for now.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanItemRow extends StatelessWidget {
  const _PlanItemRow({required this.item});

  final PlanItemEntity item;

  IconData get _icon => switch (item.kind) {
        PlanItemKind.room => Icons.groups_rounded,
        PlanItemKind.product => Icons.storefront_rounded,
        PlanItemKind.post => Icons.dynamic_feed_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: PhlioColors.surfaceInput, borderRadius: PhlioRadii.mdRadius),
          child: Icon(_icon, size: 18, color: PhlioColors.brandPurple),
        ),
        const SizedBox(width: PhlioSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: PhlioTypography.bodyStrong),
              Text(
                item.subtitle,
                style: PhlioTypography.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (item.displayPrice != null) ...[
          const SizedBox(width: PhlioSpacing.sm),
          Text(item.displayPrice!, style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.brandOrange)),
        ],
      ],
    );
  }
}
