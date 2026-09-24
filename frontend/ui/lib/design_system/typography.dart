// Phlio design system — typography scale.
//
// No custom font is bundled in this initial build (see assets/images/README.md
// for how to add one — Poppins/Manrope for display text and Inter for body
// text are good fits for the reference UI's rounded, friendly-but-modern
// feel). Every style below sets `fontFamily: null` explicitly rather than
// leaving it unset, so switching to a bundled font later is a one-line
// change in [PhlioTypography._fontFamily] instead of hunting through every
// call site.

import 'package:flutter/material.dart';
import 'colors.dart';

abstract final class PhlioTypography {
  static const String? _fontFamily = null; // TODO(design): set once a brand font is bundled.

  static const TextStyle displayLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 32,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: PhlioColors.textSecondary,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w600,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: PhlioColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: PhlioColors.textMuted,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
}
