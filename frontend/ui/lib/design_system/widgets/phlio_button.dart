// Phlio design system — buttons.
//
// Two variants matter for this product: a gradient-filled primary action
// (the "Continue" button on auth, "Book This Plan" on the Agent screen)
// and a quieter secondary/outline action. Both share sizing and motion so
// they read as one family rather than two unrelated components — a common
// tell of "AI slop" UI is inconsistent button shapes across screens.

import 'package:flutter/material.dart';
import '../colors.dart';
import '../radii.dart';
import '../spacing.dart';
import '../typography.dart';

enum PhlioButtonSize { medium, large }

/// The primary, gradient-filled call-to-action button.
class PhlioPrimaryButton extends StatelessWidget {
  const PhlioPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.size = PhlioButtonSize.large,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final PhlioButtonSize size;
  final IconData? icon;
  final bool isLoading;

  /// Whether the button stretches to fill its parent's width — true for
  /// nearly every use in this app (form CTAs, the Agent's "Book This Plan"),
  /// false for compact inline actions like "Follow".
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height = size == PhlioButtonSize.large ? 56.0 : 46.0;
    final disabled = onPressed == null || isLoading;

    return Opacity(
      opacity: disabled && onPressed == null ? 0.5 : 1.0,
      child: SizedBox(
        width: expand ? double.infinity : null,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: PhlioColors.brandGradient,
            borderRadius: PhlioRadii.pillRadius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: PhlioRadii.pillRadius,
              onTap: isLoading ? null : onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.xl),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(PhlioColors.textOnBrand),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: PhlioTypography.button.copyWith(color: PhlioColors.textOnBrand),
                            ),
                            if (icon != null) ...[
                              const SizedBox(width: PhlioSpacing.sm),
                              Icon(icon, size: 18, color: PhlioColors.textOnBrand),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet, outlined secondary action — used alongside a
/// [PhlioPrimaryButton] (e.g. "Cancel"), or on its own for lower-emphasis
/// actions (e.g. "Skip for now").
class PhlioSecondaryButton extends StatelessWidget {
  const PhlioSecondaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.size = PhlioButtonSize.large,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final PhlioButtonSize size;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height = size == PhlioButtonSize.large ? 56.0 : 46.0;
    return SizedBox(
      width: expand ? double.infinity : null,
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: PhlioColors.border),
          shape: RoundedRectangleBorder(borderRadius: PhlioRadii.pillRadius),
        ),
        child: Text(label, style: PhlioTypography.button.copyWith(color: PhlioColors.textPrimary)),
      ),
    );
  }
}

/// A compact, icon-first "chip" button — used for social auth ("Google",
/// "Apple", "Passkey" on the login screen) and filter chips across
/// Rooms/Shop discovery.
class PhlioChipButton extends StatelessWidget {
  const PhlioChipButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PhlioColors.brandPurple.withOpacity(0.18) : PhlioColors.surfaceElevated,
      borderRadius: PhlioRadii.pillRadius,
      child: InkWell(
        borderRadius: PhlioRadii.pillRadius,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: PhlioRadii.pillRadius,
            border: Border.all(
              color: selected ? PhlioColors.brandPurple : PhlioColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? PhlioColors.brandPurple : PhlioColors.textSecondary),
                const SizedBox(width: PhlioSpacing.xs),
              ],
              Text(
                label,
                style: PhlioTypography.label.copyWith(
                  color: selected ? PhlioColors.textPrimary : PhlioColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
