// Phlio design system — bottom navigation.
//
// Matches the reference screens' five-slot bar: Home, Explore, a raised
// gradient "create" button in the center, Profile, and the App Tray (the
// 3x3 grid that opens the platform switcher). The create and tray slots
// are deliberately not part of the selected-item set — create triggers an
// action sheet, tray triggers the platform switcher sheet, and neither is
// ever "selected".

import 'package:flutter/material.dart';
import '../colors.dart';
import '../typography.dart';

class PhlioBottomNavItem {
  const PhlioBottomNavItem(
      {required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Home, Explore, Profile — the three *selectable* tabs. The center create
/// button and the trailing app-tray slot are handled via callbacks in
/// [PhlioBottomNav] and never render as selected.
const List<PhlioBottomNavItem> phlioBottomNavItems = [
  PhlioBottomNavItem(
      icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
  PhlioBottomNavItem(
      icon: Icons.search_rounded,
      activeIcon: Icons.manage_search_rounded,
      label: 'Explore'),
  PhlioBottomNavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile'),
];

class PhlioBottomNav extends StatelessWidget {
  const PhlioBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
    this.onCreateTap,
    this.onTrayTap,
    this.createIcon = Icons.add_rounded,
    this.profileAvatar,
    this.createLabel = 'Create',
    this.createCount = 0,
    this.trayIcon = Icons.apps_rounded,
    this.trayLabel = 'Tray',
    this.trayColor = PhlioColors.textMuted,
  });

  /// Index into [phlioBottomNavItems] (0-2). The center create button and
  /// trailing tray slot are handled separately and never "selected".
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onCreateTap;
  final VoidCallback? onTrayTap;

  /// The center button's glyph — Phlio Pay swaps the plus for a QR scanner.
  final IconData createIcon;
  final String createLabel;
  final int createCount;
  final IconData trayIcon;
  final String trayLabel;
  final Color trayColor;

  /// Optional avatar widget rendered in place of the Profile icon (the
  /// user's picture once they upload one).
  final Widget? profileAvatar;

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
              _trayButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index) {
    final item = phlioBottomNavItems[index];
    final selected = index == currentIndex;
    final color = selected ? PhlioColors.brandOrange : PhlioColors.textMuted;
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
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: SizedBox(
                height: _iconSlot,
                child: Center(
                  child: (index == 2 && profileAvatar != null)
                      ? _ringedAvatar(profileAvatar!, selected)
                      : Icon(selected ? item.activeIcon : item.icon,
                          color: color, size: 24),
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: PhlioTypography.caption.copyWith(color: color),
              child: Text(item.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: selected ? 14 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: PhlioColors.brandOrange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Every slot's icon sits in the same 28px box so labels line up
  /// regardless of whether the slot shows a glyph or the profile avatar.
  static const double _iconSlot = 28;

  /// The user's avatar — the same 26px footprint as a glyph, with a ring
  /// that turns brand orange when Profile is selected.
  Widget _ringedAvatar(Widget avatar, bool selected) {
    return Container(
      width: 26,
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: selected ? PhlioColors.brandOrange : PhlioColors.border,
            width: 1.5),
      ),
      child: ClipOval(child: avatar),
    );
  }

  Widget _createButton() {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onCreateTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: PhlioColors.sunsetGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: PhlioColors.brandViolet.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Tooltip(
                message: createLabel,
                child: Semantics(
                    label: createLabel,
                    button: true,
                    child: Center(
                        child: Badge(
                            isLabelVisible: createCount > 0,
                            label: Text('$createCount'),
                            child: Icon(createIcon,
                                color: PhlioColors.textOnBrand, size: 24))))),
          ),
        ),
      ),
    );
  }

  /// The App Tray slot — Phlio's platform switcher (the reference screens'
  /// 3x3 grid button). Never renders as selected.
  Widget _trayButton(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: 'Switch platform',
        child: InkWell(
          onTap: onTrayTap,
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: SizedBox(
              key: ValueKey('tray-slot-$trayLabel'),
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      height: _iconSlot,
                      child: Center(
                          child: Icon(trayIcon, color: trayColor, size: 24))),
                  const SizedBox(height: 2),
                  Text(trayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          PhlioTypography.caption.copyWith(color: trayColor)),
                  // Mirrors the nav items' 2px gap + 3px indicator so the
                  // tray label shares their baseline.
                  const SizedBox(height: 5),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
