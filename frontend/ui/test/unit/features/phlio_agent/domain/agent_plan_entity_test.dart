// Tests for `AgentPlanEntity.displayEstimatedRange` and
// `PlanItemEntity.displayPrice` — the formatting the Agent screen's plan
// card (`agent_plan_card.dart`) relies on to show "Estimated total".

import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/phlio_agent/domain/entities/agent_plan_entity.dart';

void main() {
  group('AgentPlanEntity.displayEstimatedRange', () {
    test('shows a min–max range when they differ', () {
      const plan = AgentPlanEntity(
        id: 'plan_test',
        summary: 'A test plan.',
        items: [],
        estimatedTotalMinMinorUnits: 300000, // ₹3,000
        estimatedTotalMaxMinorUnits: 350000, // ₹3,500
        currency: 'INR',
      );
      expect(plan.displayEstimatedRange, '₹3000 – ₹3500');
    });

    test('collapses to a single value when min equals max', () {
      const plan = AgentPlanEntity(
        id: 'plan_test',
        summary: 'A test plan.',
        items: [],
        estimatedTotalMinMinorUnits: 200000,
        estimatedTotalMaxMinorUnits: 200000,
        currency: 'INR',
      );
      expect(plan.displayEstimatedRange, '₹2000');
    });

    test('uses the currency code as a prefix for non-INR currencies', () {
      const plan = AgentPlanEntity(
        id: 'plan_test',
        summary: 'A test plan.',
        items: [],
        estimatedTotalMinMinorUnits: 1000,
        estimatedTotalMaxMinorUnits: 2000,
        currency: 'USD',
      );
      expect(plan.displayEstimatedRange, 'USD 10 – USD 20');
    });
  });

  group('PlanItemEntity.displayPrice', () {
    test('returns null when the item has no price (e.g. a room or post)', () {
      const item = PlanItemEntity(
        kind: PlanItemKind.room,
        refId: 'rm_test',
        title: 'Join Tech & AI',
        subtitle: '482 members',
      );
      expect(item.displayPrice, isNull);
    });

    test('formats a priced item (e.g. a product) with its currency symbol', () {
      const item = PlanItemEntity(
        kind: PlanItemKind.product,
        refId: 'prd_test',
        title: 'Folded Leaf Lantern',
        subtitle: 'From Phlio Shop',
        priceMinorUnits: 189900,
        currency: 'INR',
      );
      expect(item.displayPrice, '₹1899');
    });
  });
}
