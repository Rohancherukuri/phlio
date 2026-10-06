// The App Tray sheet — Phlio's platform switcher.
//
// Mirrors the reference tray pattern (a floating grid of platform symbols
// above the nav bar): every Phlio platform is shown with its home-screen
// symbol, the current one highlighted. Selecting a platform switches the
// shell to it; Stream/News are visible but marked "soon" (selectable, they
// render an honest coming-soon surface rather than being hidden).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/colors.dart';
import '../../design_system/radii.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../platform/phlio_platform.dart';

class PlatformTraySheet extends ConsumerWidget {
  const PlatformTraySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPlatform = ref.watch(currentPlatformProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.md, PhlioSpacing.lg, PhlioSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Phlio platforms', style: PhlioTypography.headline),
                const Spacer(),
                Text('People. Places. Possibilities.', style: PhlioTypography.caption),
              ],
            ),
            const SizedBox(height: PhlioSpacing.lg),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: PhlioSpacing.lg,
              crossAxisSpacing: PhlioSpacing.sm,
              childAspectRatio: 0.82,
              children: [
                for (final platform in PhlioPlatform.values)
                  _PlatformTile(
                    platform: platform,
                    isCurrent: platform == currentPlatform,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformTile extends ConsumerWidget {
  const _PlatformTile({required this.platform, required this.isCurrent});

  final PhlioPlatform platform;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: PhlioRadii.lgRadius,
      onTap: () {
        ref.read(currentPlatformProvider.notifier).state = platform;
        Navigator.of(context).pop();
        // The Home tab is the platform's front door — land there.
        context.go('/home');
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey('tray-${platform.name}-$isCurrent'),
                tween: Tween(begin: isCurrent ? 0.85 : 1.0, end: 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: platform.color.withValues(
                      alpha: isCurrent ? 0.28 : 0.16,
                    ),
                    shape: BoxShape.circle,
                    border: isCurrent
                        ? Border.all(color: platform.color, width: 1.5)
                        : null,
                  ),
                  child: Icon(
                    isCurrent ? platform.activeIcon : platform.icon,
                    color: platform.color,
                    size: 24,
                  ),
                ),
              ),
              if (!platform.isAvailable)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: PhlioColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: PhlioColors.border),
                    ),
                    child: Text(
                      'soon',
                      style: PhlioTypography.caption.copyWith(fontSize: 9),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: PhlioSpacing.xs),
          Text(
            platform.label,
            style: PhlioTypography.caption.copyWith(
              color: isCurrent ? PhlioColors.textPrimary : PhlioColors.textSecondary,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
