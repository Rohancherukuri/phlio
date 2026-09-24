// App-wide ThemeData, built entirely from `lib/design_system` tokens.
//
// Keeping this thin — a translation from design tokens to `ThemeData` —
// means the design system stays the single source of truth; nothing here
// invents a new color or radius that isn't already named in
// `design_system/colors.dart` etc.

import 'package:flutter/material.dart';
import '../../design_system/colors.dart';
import '../../design_system/radii.dart';
import '../../design_system/typography.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: PhlioColors.background,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        surface: PhlioColors.surface,
        primary: PhlioColors.brandPurple,
        secondary: PhlioColors.brandOrange,
        error: PhlioColors.danger,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: PhlioTypography.displayLarge,
        displayMedium: PhlioTypography.displayMedium,
        headlineMedium: PhlioTypography.headline,
        titleMedium: PhlioTypography.title,
        bodyLarge: PhlioTypography.bodyLarge,
        bodyMedium: PhlioTypography.body,
        labelLarge: PhlioTypography.label,
        bodySmall: PhlioTypography.caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: PhlioColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: PhlioTypography.headline,
      ),
      dividerColor: PhlioColors.borderSubtle,
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PhlioColors.surfaceElevated,
        contentTextStyle: PhlioTypography.body.copyWith(color: PhlioColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: PhlioRadii.mdRadius),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PhlioColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(PhlioRadii.xxl)),
        ),
      ),
    );
  }
}
