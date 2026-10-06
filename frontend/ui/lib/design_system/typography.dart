// Phlio design system — typography scale.
//
// Two bundled families (see assets/fonts/ + pubspec.yaml):
//  * Manrope — the UI workhorse: geometric, friendly, premium. Everything
//    from body copy to section headers.
//  * Quicksand — rounded display face reserved for the wordmark, big
//    numerals and splash/login headlines where the brand should feel soft.

import 'package:flutter/material.dart';
import 'colors.dart';

abstract final class PhlioTypography {
  static const String uiFamily = 'Manrope';
  static const String displayFamily = 'Quicksand';

  /// Big splash / onboarding statements.
  static const TextStyle displayLarge = TextStyle(
    fontFamily: displayFamily,
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: PhlioColors.textPrimary,
  );

  /// Screen-level headlines ("Good morning, Arjun", "Phlio Rooms").
  static const TextStyle displayMedium = TextStyle(
    fontFamily: displayFamily,
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: uiFamily,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: uiFamily,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: uiFamily,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: PhlioColors.textSecondary,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w600,
    color: PhlioColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: uiFamily,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: PhlioColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: PhlioColors.textMuted,
  );

  /// The letter-spaced all-caps tagline: "PEOPLE. PLACES. POSSIBILITIES."
  static const TextStyle tagline = TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: 3.2,
    color: PhlioColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: uiFamily,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );
}
