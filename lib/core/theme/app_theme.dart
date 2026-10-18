import 'package:flutter/cupertino.dart';

/// Neutral-first palette. The accent is the documented navy (藏青), reserved for
/// primary actions and selected states; icons and secondary controls stay on
/// label greys so the interface reads like an admin tool.
abstract final class AppColors {
  /// 藏青 accent from the design brief; a lighter navy on dark surfaces so the
  /// fill still reads as navy instead of a saturated stock blue.
  static const navy = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF172A46),
    darkColor: Color(0xFFA8C2E0),
  );

  /// Semantic alias.
  static const accent = navy;

  static const background = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF4F5F7),
    darkColor: Color(0xFF101010),
  );
  static const surface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1B1B1E),
  );
  static const sheet = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF18181A),
  );
  static const raised = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF0F1F4),
    darkColor: Color(0xFF232327),
  );

  static const success = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF2F8F68),
    darkColor: Color(0xFF4CC38A),
  );
  static const warning = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFB7791F),
    darkColor: Color(0xFFE5A33B),
  );
  static const danger = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFC94A4A),
    darkColor: Color(0xFFFF6B6B),
  );

  /// Leave marks on the calendar are red by request.
  static const leave = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFD93A3F),
    darkColor: Color(0xFFFF6169),
  );

  static const muted = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF8A8F98),
    darkColor: Color(0xFF8A8F98),
  );
}

abstract final class AppTheme {
  /// Use Cupertino semantic surfaces so system brightness, elevation and
  /// increased contrast resolve consistently on every page and modal.
  static const system = CupertinoThemeData(
    primaryColor: AppColors.navy,
    // On dark surfaces the navy accent becomes a light steel blue, so filled
    // controls need dark text to stay legible.
    primaryContrastingColor: CupertinoDynamicColor.withBrightness(
      color: CupertinoColors.white,
      darkColor: Color(0xFF101010),
    ),
    scaffoldBackgroundColor: AppColors.background,
    barBackgroundColor: AppColors.background,
  );
  static CupertinoThemeData get light =>
      system.copyWith(brightness: Brightness.light);
  static CupertinoThemeData get dark =>
      system.copyWith(brightness: Brightness.dark);
}
