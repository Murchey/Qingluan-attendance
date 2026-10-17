import 'package:flutter/cupertino.dart';

abstract final class AppColors {
  static const navy = Color(0xFF172A46);
  static const background = CupertinoColors.systemGroupedBackground;
  static const success = Color(0xFF2F8F68);
  static const warning = Color(0xFFB7791F);
  static const danger = Color(0xFFC94A4A);
  static const muted = Color(0xFF6C7788);
}

abstract final class AppTheme {
  /// Use Cupertino semantic surfaces so system brightness, elevation and
  /// increased contrast resolve consistently on every page and modal.
  static const system = CupertinoThemeData(
    primaryColor: CupertinoDynamicColor.withBrightness(
      color: AppColors.navy,
      darkColor: Color(0xFFAAC5EF),
    ),
    primaryContrastingColor: CupertinoDynamicColor.withBrightness(
      color: CupertinoColors.white,
      darkColor: AppColors.navy,
    ),
    scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
  );
  static CupertinoThemeData get light =>
      system.copyWith(brightness: Brightness.light);
  static CupertinoThemeData get dark =>
      system.copyWith(brightness: Brightness.dark);
}
