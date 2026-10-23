import 'package:phlio/shared/content/content_surface.dart';
// Renders an `AgentPlanEntity` — mirrors the reference "4. PHLIO AGENT"
// screen's plan card: a list of recommended items, an estimated total, and
// a gradient "Book This Plan" CTA.
//
// The CTA opens Phlio Book — the plan is a preview of bookable listings
// (the backend's planner only ever assembles plans from real Book data),
// and the actual booking confirmation happens inside the Book flow where
// date/time/participants are chosen explicitly. The agent never books
// anything without that step (see `backend/app/domains/agent/service.py`'s
// guardrail docstring).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/platform/phlio_platform.dart';
import '../../../../app/shell/platform_home_screen.dart' show switchPlatform;
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
            ContentSurface(
                platform: switch (item.kind) {
                  PlanItemKind.room => 'rooms',
                  PlanItemKind.product => 'shop',
                  PlanItemKind.post => 'social',
                  PlanItemKind.book => 'book'
                },
                contentId: item.refId,
                child: _PlanItemRow(item: item)),
            if (item != plan.items.last)
              const Divider(
                  height: PhlioSpacing.xl, color: PhlioColors.borderSubtle),
          ],
          const SizedBox(height: PhlioSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: PhlioSpacing.md, vertical: PhlioSpacing.sm),
            decoration: BoxDecoration(
                color: PhlioColors.surfaceInput,
                borderRadius: PhlioRadii.mdRadius),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated total', style: PhlioTypography.label),
                Text(
                  plan.displayEstimatedRange,
                  style: PhlioTypography.bodyStrong
                      .copyWith(color: PhlioColors.brandOrange),
                ),
              ],
            ),
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioPrimaryButton(
            label: 'Book This Plan',
            size: PhlioButtonSize.medium,
            onPressed: () {
              switchPlatform(context, PhlioPlatform.book);
              context.go('/home');
            },
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
        PlanItemKind.book => Icons.confirmation_number_rounded,
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
          decoration: BoxDecoration(
              color: PhlioColors.surfaceInput,
              borderRadius: PhlioRadii.mdRadius),
          child: Icon(_icon, size: 18, color: PhlioColors.brandOrange),
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
          Text(item.displayPrice!,
              style: PhlioTypography.bodyStrong
                  .copyWith(color: PhlioColors.brandOrange)),
        ],
      ],
    );
  }
}
