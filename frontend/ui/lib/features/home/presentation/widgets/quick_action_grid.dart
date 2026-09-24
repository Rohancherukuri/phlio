// Quick action grid — the home screen's tappable rendering of Phlio's
// eight top-level domains (Pay, Social, Rooms, Book, Shop, Stream, News,
// Agent — Phlio_Final_Product_Blueprint.md section 3). Unavailable domains
// (see `backend/app/domains/home/service.py`) render dimmed with a
// "coming soon" tap response instead of being silently hidden — being
// upfront about the roadmap beats a grid that mysteriously has gaps.

import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../domain/entities/quick_action_entity.dart';

const Map<QuickActionKind, IconData> _quickActionIcons = {
  QuickActionKind.pay: Icons.account_balance_wallet_outlined,
  QuickActionKind.social: Icons.groups_outlined,
  QuickActionKind.rooms: Icons.forum_outlined,
  QuickActionKind.book: Icons.confirmation_number_outlined,
  QuickActionKind.shop: Icons.storefront_outlined,
  QuickActionKind.stream: Icons.play_circle_outline_rounded,
  QuickActionKind.news: Icons.article_outlined,
  QuickActionKind.agent: Icons.auto_awesome_outlined,
};

const Map<QuickActionKind, Color> _quickActionColors = {
  QuickActionKind.pay: PhlioColors.domainPay,
  QuickActionKind.social: PhlioColors.domainSocial,
  QuickActionKind.rooms: PhlioColors.domainRooms,
  QuickActionKind.book: PhlioColors.domainBook,
  QuickActionKind.shop: PhlioColors.domainShop,
  QuickActionKind.stream: PhlioColors.domainStream,
  QuickActionKind.news: PhlioColors.domainNews,
  QuickActionKind.agent: PhlioColors.domainAgent,
};

class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({required this.actions, required this.onTap, super.key});

  final List<QuickActionEntity> actions;
  final ValueChanged<QuickActionEntity> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: PhlioSpacing.lg,
        crossAxisSpacing: PhlioSpacing.sm,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        // A gentle staggered entrance — each icon fades/slides in a beat
        // after the previous one, driven purely by its grid index so no
        // animation controller/state needs managing for a one-shot effect.
        final action = actions[index];
        final color = _quickActionColors[action.kind] ?? PhlioColors.domainAgent;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 260 + (index * 40)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(offset: Offset(0, (1 - value) * 10), child: child),
          ),
          child: InkWell(
            borderRadius: PhlioRadii.lgRadius,
            onTap: () => onTap(action),
            child: Opacity(
              opacity: action.isAvailable ? 1 : 0.45,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle),
                    child: Icon(_quickActionIcons[action.kind] ?? Icons.circle, color: color, size: 22),
                  ),
                  const SizedBox(height: PhlioSpacing.xs),
                  Text(action.label, style: PhlioTypography.caption),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
