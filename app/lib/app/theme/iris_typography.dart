import 'package:flutter/material.dart';

import 'iris_colors.dart';

abstract final class IrisTypography {
  static const TextStyle technicalValue = TextStyle(
    color: IrisColors.primaryText,
    fontFamily: 'monospace',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextTheme textTheme = TextTheme(
    displaySmall: TextStyle(
      color: IrisColors.primaryText,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    headlineSmall: TextStyle(
      color: IrisColors.primaryText,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    titleMedium: TextStyle(
      color: IrisColors.primaryText,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    bodyLarge: TextStyle(
      color: IrisColors.secondaryText,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      color: IrisColors.secondaryText,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    labelLarge: TextStyle(
      color: IrisColors.primaryText,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    labelMedium: TextStyle(
      color: IrisColors.mutedText,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),
  );
}
