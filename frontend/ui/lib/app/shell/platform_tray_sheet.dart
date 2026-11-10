// The App Tray — Phlio's platform switcher.
//
// A floating grid of platform symbols above the nav bar, every Phlio
// platform shown with its home-screen symbol and the current one
// highlighted.
//
// Motion (after the reference app-switcher):
//   * open: the page behind dims and softens, and the card grows up out of
//     the nav bar from the tray button, with a gentle spring; the rows
//     arrive bottom-to-top, each tile rising into place.
//   * pick: the other tiles fade away, the chosen one gives a small pop,
//     then the now-empty card sinks back into the tray button while the new
//     platform's home fades in behind it.
//   * dismiss (tap outside / back): the same collapse, with nothing picked.
// Respects "reduce motion": everything snaps.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/colors.dart';
import '../../design_system/radii.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../platform/phlio_platform.dart';

/// True while the tray is open (the nav's tray chevron flips).
final platformTrayOpenProvider = StateProvider<bool>((ref) => false);

/// Opens the animated tray above the nav bar. [onSelected] runs the moment a
/// platform is picked, while the card is still collapsing, so the new home
/// fades in under it instead of after it.
Future<void> showPlatformSwitcher(
  BuildContext context, {
  required ValueChanged<PhlioPlatform> onSelected,
}) {
  return Navigator.of(context, rootNavigator: true)
      .push<void>(_PlatformSwitcherRoute(onSelected));
}

class _PlatformSwitcherRoute extends PopupRoute<void> {
  _PlatformSwitcherRoute(this.onSelected);
  final ValueChanged<PhlioPlatform> onSelected;

  // The switcher draws and animates its own backdrop.
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => false;
  @override
  String? get barrierLabel => 'Close platform tray';
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      _PlatformSwitcher(onSelected: onSelected);
}

class _PlatformSwitcher extends ConsumerStatefulWidget {
  const _PlatformSwitcher({required this.onSelected});
  final ValueChanged<PhlioPlatform> onSelected;

  @override
  ConsumerState<_PlatformSwitcher> createState() => _PlatformSwitcherState();
}

class _PlatformSwitcherState extends ConsumerState<_PlatformSwitcher>
    with TickerProviderStateMixin {
  // 0 = tucked into the nav, 1 = fully open.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 360),
  );
  // The pick beat: other tiles fade, the chosen one pops.
  late final AnimationController _pick = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final _grow = CurvedAnimation(
    parent: _open,
    curve: const Cubic(0.22, 1.18, 0.36, 1), // soft spring overshoot
    reverseCurve: Curves.easeInCubic,
  );
  late final _fade = CurvedAnimation(
    parent: _open,
    curve: const Interval(0, 0.45, curve: Curves.easeOut),
    reverseCurve: const Interval(0.35, 1, curve: Curves.easeIn),
  );
  late final _backdrop = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  PhlioPlatform? _picked;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(platformTrayOpenProvider.notifier).state = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _open.value = 1;
      } else {
        _open.forward();
      }
    });
  }

  @override
  void dispose() {
    _grow.dispose();
    _fade.dispose();
    _backdrop.dispose();
    _open.dispose();
    _pick.dispose();
    super.dispose();
  }

  Future<void> _close([PhlioPlatform? platform]) async {
    if (_closing) return;
    _closing = true;
    final reduced = MediaQuery.disableAnimationsOf(context);
    ref.read(platformTrayOpenProvider.notifier).state = false;
    if (platform != null) {
      HapticFeedback.selectionClick();
      setState(() => _picked = platform);
      if (!reduced) await _pick.forward();
      widget.onSelected(platform);
    }
    if (!reduced && mounted) await _open.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The nav bar is 64 px tall above the bottom inset; the card floats just
    // above it, and grows from / collapses into the tray button (the
    // right-most slot, centred at 90% of the width).
    final navTop = media.padding.bottom + 64;
    const margin = 12.0;
    final cardWidth = math.min(420.0, media.size.width - margin * 2);
    final trayX = media.size.width * 0.9;
    final cardLeft = media.size.width - margin - cardWidth;
    final originX = ((trayX - cardLeft) / cardWidth) * 2 - 1;

    final grow = _grow, fade = _fade, backdrop = _backdrop;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Stack(
        children: [
          // Backdrop: the page behind dims and softens. Leaves the nav bar
          // itself clear so the tray button stays visible as the anchor.
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: navTop,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: AnimatedBuilder(
                animation: backdrop,
                builder: (context, _) {
                  final t = backdrop.value.clamp(0.0, 1.0);
                  return ClipRect(
                    child: BackdropFilter(
                      filter:
                          ui.ImageFilter.blur(sigmaX: 7 * t, sigmaY: 7 * t),
                      child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.42 * t)),
                    ),
                  );
                },
              ),
            ),
          ),
          // Tapping the nav bar area (including the tray button) closes too.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: navTop,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          Positioned(
            left: cardLeft,
            width: cardWidth,
            bottom: navTop + 8,
            child: AnimatedBuilder(
              animation: Listenable.merge([_open, _pick]),
              builder: (context, child) {
                final g = grow.value;
                // Height reveal from the bottom edge (capped at 1); the
                // overshoot goes into a slight scale so it reads as a spring.
                final reveal = g.clamp(0.0, 1.0);
                final scale = 0.86 + 0.14 * g;
                return Opacity(
                  opacity: fade.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment(originX, 1),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: math.max(0.08, reveal),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: Material(
                color: PhlioColors.surface,
                elevation: 12,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: PlatformTraySheet(
                  open: _open,
                  pick: _pick,
                  picked: _picked,
                  onSelected: _close,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlatformTraySheet extends ConsumerWidget {
  const PlatformTraySheet({
    super.key,
    this.onSelected,
    this.open,
    this.pick,
    this.picked,
  });
  final ValueChanged<PhlioPlatform>? onSelected;

  /// Drives the staggered entrance (rows bottom-to-top). Null = static.
  final Animation<double>? open;

  /// Drives the pick beat: everything but [picked] fades out.
  final Animation<double>? pick;
  final PhlioPlatform? picked;

  static const _columns = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPlatform = ref.watch(currentPlatformProvider);
    final platforms = PhlioPlatform.values;
    final rows = (platforms.length / _columns).ceil();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PhlioSpacing.lg,
        PhlioSpacing.md,
        PhlioSpacing.lg,
        PhlioSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Staggered(
            open: open,
            pick: pick,
            // The header arrives last, after the top row.
            start: 0.12 * rows + 0.04,
            child: Row(
              children: [
                Text('Phlio platforms', style: PhlioTypography.headline),
              ],
            ),
          ),
          const SizedBox(height: PhlioSpacing.lg),
          GridView.count(
            crossAxisCount: _columns,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: PhlioSpacing.lg,
            crossAxisSpacing: PhlioSpacing.sm,
            childAspectRatio: 0.82,
            children: [
              for (final (i, platform) in platforms.indexed)
                _Staggered(
                  open: open,
                  pick: pick,
                  // Bottom row first, then upward; a small left-to-right
                  // ripple within each row.
                  start: 0.12 * (rows - 1 - i ~/ _columns) +
                      0.035 * (i % _columns),
                  fadesOnPick: platform != picked,
                  popsOnPick: platform == picked,
                  child: _PlatformTile(
                    platform: platform,
                    isCurrent: picked == null
                        ? platform == currentPlatform
                        : platform == picked,
                    onSelected: onSelected,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One tile's entrance and pick motion.
class _Staggered extends StatelessWidget {
  const _Staggered({
    required this.child,
    required this.start,
    this.open,
    this.pick,
    this.fadesOnPick = true,
    this.popsOnPick = false,
  });
  final Widget child;
  final Animation<double>? open;
  final Animation<double>? pick;
  final double start;
  final bool fadesOnPick;
  final bool popsOnPick;

  @override
  Widget build(BuildContext context) {
    final open = this.open;
    final pick = this.pick;
    if (open == null) return child;
    final begin = (0.14 + start).clamp(0.0, 0.58);
    return AnimatedBuilder(
      animation: Listenable.merge([open, if (pick != null) pick]),
      builder: (context, child) {
        final t = open.value;
        // Opening: staggered by row. Closing: every tile drops away quickly,
        // before the card itself collapses.
        final e = open.status == AnimationStatus.reverse
            ? Curves.easeIn.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0))
            : Curves.easeOutCubic
                .transform(((t - begin) / 0.42).clamp(0.0, 1.0));
        final p = pick?.value ?? 0;
        var opacity = e;
        var scale = 0.82 + 0.18 * e;
        if (fadesOnPick) {
          opacity *= 1 - Curves.easeOut.transform(p);
          scale *= 1 - 0.12 * p;
        }
        if (popsOnPick) {
          scale *= 1 + 0.12 * math.sin(math.pi * p);
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - e)),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _PlatformTile extends ConsumerWidget {
  const _PlatformTile(
      {required this.platform, required this.isCurrent, this.onSelected});
  final ValueChanged<PhlioPlatform>? onSelected;

  final PhlioPlatform platform;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: PhlioRadii.lgRadius,
      onTap: () {
        if (onSelected != null) {
          onSelected!(platform);
          return;
        }
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: platform.color.withValues(
                    alpha: isCurrent ? 0.28 : 0.16,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isCurrent ? platform.color : Colors.transparent,
                      width: 1.5),
                ),
                child: Icon(
                  isCurrent ? platform.activeIcon : platform.icon,
                  color: platform.color,
                  size: 24,
                ),
              ),
              if (!platform.isAvailable)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
              color: isCurrent
                  ? PhlioColors.textPrimary
                  : PhlioColors.textSecondary,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
