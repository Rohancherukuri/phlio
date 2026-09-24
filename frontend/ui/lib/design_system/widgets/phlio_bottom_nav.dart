// Phlio design system — bottom navigation.
//
// Matches the reference screens' five-item bar: Home, Explore, a raised
// gradient "create" button in the center, Activity, and Profile. The
// center button is deliberately not part of the `NavigationBar`/`BottomNavigationBar`
// item set — it triggers a distinct "create" action sheet rather than
// navigating to a fifth tab, exactly as in the reference UI.

import 'package:flutter/material.dart';
import '../colors.dart';
import '../typography.dart';

class PhlioBottomNavItem {
  const PhlioBottomNavItem({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const List<PhlioBottomNavItem> phlioBottomNavItems = [
  PhlioBottomNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
  PhlioBottomNavItem(icon: Icons.search_outlined, activeIcon: Icons.search_rounded, label: 'Explore'),
  PhlioBottomNavItem(
    icon: Icons.notifications_outlined,
    activeIcon: Icons.notifications_rounded,
    label: 'Activity',
  ),
  PhlioBottomNavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile'),
];

class PhlioBottomNav extends StatelessWidget {
  const PhlioBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
    this.onCreateTap,
  });

  /// Index into [phlioBottomNavItems] (0-3). The center create button is
  /// handled separately via [onCreateTap] and never "selected".
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onCreateTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: PhlioColors.surface,
        border: Border(top: BorderSide(color: PhlioColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _navItem(0),
              _navItem(1),
              _createButton(),
              _navItem(2),
              _navItem(3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index) {
    final item = phlioBottomNavItems[index];
    final selected = index == currentIndex;
    final color = selected ? PhlioColors.brandPurple : PhlioColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A small scale pop on the icon when it becomes selected, plus
            // an animated underline dot — both implicit (`TweenAnimationBuilder`
            // / `AnimatedContainer`), so switching tabs never needs its own
            // AnimationController.
            TweenAnimationBuilder<double>(
              key: ValueKey('nav-icon-$index-$selected'),
              tween: Tween(begin: selected ? 0.8 : 1.0, end: 1.0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: Icon(selected ? item.activeIcon : item.icon, color: color, size: 24),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: PhlioTypography.caption.copyWith(color: color),
              child: Text(item.label),
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: selected ? 14 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: PhlioColors.brandPurple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _createButton() {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onCreateTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              gradient: PhlioColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, color: PhlioColors.textOnBrand, size: 26),
          ),
        ),
      ),
    );
  }
}
