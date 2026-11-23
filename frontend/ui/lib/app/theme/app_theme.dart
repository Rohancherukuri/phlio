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
        onPrimary: PhlioColors.backgroundDeep,
        onSecondary: PhlioColors.backgroundDeep,
        onSurface: PhlioColors.textPrimary,
        onSurfaceVariant: PhlioColors.textSecondary,
        surfaceContainerLowest: PhlioColors.backgroundDeep,
        surfaceContainerLow: PhlioColors.background,
        surfaceContainer: PhlioColors.surface,
        surfaceContainerHigh: PhlioColors.surfaceInput,
        surfaceContainerHighest: PhlioColors.surfaceElevated,
        outline: PhlioColors.border,
        outlineVariant: PhlioColors.border,
        secondary: PhlioColors.brandBlue,
        tertiary: PhlioColors.success,
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
      disabledColor: PhlioColors.textDisabled,
      iconTheme: const IconThemeData(color: PhlioColors.textSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PhlioColors.surfaceInput,
        hintStyle: const TextStyle(color: PhlioColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: PhlioRadii.lgRadius,
          borderSide: const BorderSide(color: PhlioColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: PhlioRadii.lgRadius,
          borderSide: const BorderSide(color: PhlioColors.border),
        ),
      ),
      // -- Popups: one look for dialogs, sheets, menus, pickers, snackbars --
      // Solid surface, a hairline border, generous radius, no tint and no
      // coloured glow. Accent colour is reserved for the primary action.
      dialogTheme: DialogThemeData(
        backgroundColor: PhlioColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PhlioRadii.xl + 4),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        titleTextStyle: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary),
        contentTextStyle: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary, height: 1.45),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: PhlioColors.surfaceInput,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: PhlioRadii.lgRadius,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        textStyle: PhlioTypography.body.copyWith(color: PhlioColors.textPrimary),
        labelTextStyle: WidgetStatePropertyAll(PhlioTypography.body.copyWith(color: PhlioColors.textPrimary)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(PhlioColors.surfaceInput),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: PhlioRadii.lgRadius,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          )),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: PhlioTypography.body.copyWith(color: PhlioColors.textPrimary),
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(PhlioColors.surfaceInput),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: PhlioRadii.lgRadius)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: PhlioRadii.smRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        textStyle: PhlioTypography.caption.copyWith(color: PhlioColors.textPrimary),
        waitDuration: const Duration(milliseconds: 400),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: PhlioColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PhlioRadii.xl + 4),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        headerBackgroundColor: PhlioColors.surface,
        headerForegroundColor: PhlioColors.textPrimary,
        headerHeadlineStyle: PhlioTypography.headline,
        dividerColor: PhlioColors.borderSubtle,
        todayForegroundColor: const WidgetStatePropertyAll(PhlioColors.brandPeach),
        todayBorder: const BorderSide(color: PhlioColors.brandPeach),
        dayForegroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? PhlioColors.textOnBrand
            : s.contains(WidgetState.disabled)
                ? PhlioColors.textDisabled
                : PhlioColors.textPrimary),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.brandPeach : null),
        yearForegroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.textOnBrand : PhlioColors.textPrimary),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.brandPeach : null),
        rangeSelectionBackgroundColor: PhlioColors.brandPeach.withValues(alpha: 0.18),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: PhlioColors.textSecondary),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: PhlioColors.brandPeach),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: PhlioColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PhlioRadii.xl + 4),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        dialBackgroundColor: PhlioColors.surfaceInput,
        dialHandColor: PhlioColors.brandPeach,
        dialTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.textOnBrand : PhlioColors.textPrimary),
        hourMinuteColor: WidgetStateColor.resolveWith((s) =>
            s.contains(WidgetState.selected) ? PhlioColors.brandPeach.withValues(alpha: 0.18) : PhlioColors.surfaceInput),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.brandPeach : PhlioColors.textPrimary),
        dayPeriodColor: PhlioColors.brandPeach.withValues(alpha: 0.18),
        dayPeriodTextColor: PhlioColors.textPrimary,
        dayPeriodBorderSide: const BorderSide(color: PhlioColors.border),
        entryModeIconColor: PhlioColors.textSecondary,
        helpTextStyle: PhlioTypography.caption,
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: PhlioColors.textSecondary),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: PhlioColors.brandPeach),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: PhlioColors.brandPeach,
          textStyle: PhlioTypography.label.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: PhlioRadii.pillRadius),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PhlioColors.textPrimary,
          foregroundColor: PhlioColors.backgroundDeep,
          textStyle: PhlioTypography.label.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: PhlioRadii.pillRadius),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PhlioColors.textPrimary,
          side: const BorderSide(color: PhlioColors.border),
          textStyle: PhlioTypography.label.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: PhlioRadii.pillRadius),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: PhlioColors.surfaceInput,
        selectedColor: PhlioColors.brandPeach.withValues(alpha: 0.18),
        side: const BorderSide(color: PhlioColors.border),
        shape: RoundedRectangleBorder(borderRadius: PhlioRadii.pillRadius),
        labelStyle: PhlioTypography.label.copyWith(color: PhlioColors.textPrimary),
        secondaryLabelStyle: PhlioTypography.label.copyWith(color: PhlioColors.textPrimary),
        checkmarkColor: PhlioColors.brandPeach,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.backgroundDeep : PhlioColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.brandPeach : PhlioColors.surfaceInput),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.transparent : PhlioColors.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.brandPeach : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(PhlioColors.backgroundDeep),
        side: const BorderSide(color: PhlioColors.textMuted, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PhlioColors.brandPeach : PhlioColors.textMuted),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: PhlioColors.textSecondary,
        textColor: PhlioColors.textPrimary,
        titleTextStyle: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary),
        subtitleTextStyle: PhlioTypography.caption,
        shape: RoundedRectangleBorder(borderRadius: PhlioRadii.mdRadius),
      ),
      dividerTheme: const DividerThemeData(color: PhlioColors.borderSubtle, thickness: 0.6, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: PhlioColors.brandPeach,
        linearTrackColor: PhlioColors.surfaceInput,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: PhlioColors.brandPeach,
        inactiveTrackColor: PhlioColors.surfaceInput,
        thumbColor: PhlioColors.textPrimary,
        overlayColor: PhlioColors.brandPeach.withValues(alpha: 0.12),
        valueIndicatorColor: PhlioColors.surfaceElevated,
        valueIndicatorTextStyle: PhlioTypography.caption.copyWith(color: PhlioColors.textPrimary),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: PhlioColors.surfaceInput,
          foregroundColor: PhlioColors.textSecondary,
          selectedBackgroundColor: PhlioColors.brandPeach.withValues(alpha: 0.18),
          selectedForegroundColor: PhlioColors.textPrimary,
          side: const BorderSide(color: PhlioColors.border),
          textStyle: PhlioTypography.label,
        ),
      ),
      cardTheme: const CardThemeData(
        color: PhlioColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: PhlioColors.brandPurple,
        selectionColor: PhlioColors.brandPurple.withValues(alpha: 0.3),
        selectionHandleColor: PhlioColors.brandPurple,
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
        contentTextStyle:
            PhlioTypography.body.copyWith(color: PhlioColors.textPrimary),
        actionTextColor: PhlioColors.brandPeach,
        closeIconColor: PhlioColors.textSecondary,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: PhlioRadii.lgRadius,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: PhlioColors.surface,
        modalBackgroundColor: PhlioColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: Colors.black.withValues(alpha: 0.6),
        dragHandleColor: PhlioColors.textMuted.withValues(alpha: 0.5),
        dragHandleSize: const Size(40, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(PhlioRadii.xxl)),
          side: BorderSide(color: Color(0x12FFFFFF)),
        ),
      ),
    );
  }
}
