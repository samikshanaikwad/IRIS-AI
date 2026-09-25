import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'iris_colors.dart';
import 'iris_radius.dart';
import 'iris_typography.dart';

abstract final class IrisTheme {
  static ThemeData get dark {
    const ColorScheme colorScheme = ColorScheme.dark(
      primary: IrisColors.primaryBlue,
      onPrimary: Colors.white,
      secondary: IrisColors.primaryBlueLight,
      onSecondary: IrisColors.background,
      error: IrisColors.danger,
      onError: Colors.white,
      surface: IrisColors.card,
      onSurface: IrisColors.primaryText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: IrisColors.background,
      canvasColor: IrisColors.background,
      textTheme: IrisTypography.textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: IrisColors.background,
        foregroundColor: IrisColors.primaryText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: IrisColors.elevatedBackground,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: IrisColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: IrisColors.subtleBorder),
          borderRadius: BorderRadius.circular(IrisRadius.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          backgroundColor: const WidgetStatePropertyAll(IrisColors.primaryBlue),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: const WidgetStatePropertyAll(
            IrisColors.primaryBluePressed,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IrisRadius.button),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          foregroundColor: const WidgetStatePropertyAll(IrisColors.primaryText),
          side: const WidgetStatePropertyAll(
            BorderSide(color: IrisColors.primaryBorder),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IrisRadius.button),
            ),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: IrisColors.elevatedBackground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: IrisColors.primaryBlue.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? IrisColors.primaryBlueLight
                : IrisColors.mutedText,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? IrisColors.primaryText
                : IrisColors.mutedText,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: IrisColors.subtleBorder,
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: IrisColors.elevatedCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(IrisRadius.bottomSheet),
          ),
        ),
      ),
    );
  }
}
