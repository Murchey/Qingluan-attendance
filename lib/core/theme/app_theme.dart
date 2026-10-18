import 'package:flutter/cupertino.dart';

/// Neutral surfaces with blue reserved for primary actions and selection.
abstract final class AppColors {
  /// The legacy name remains for existing callers.
  static const navy = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF2864E8),
    darkColor: Color(0xFF709CFF),
  );

  /// Semantic alias.
  static const accent = navy;

  static const background = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF5F6F8),
    darkColor: Color(0xFF101010),
  );
  static const surface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1C1C1E),
  );
  static const sheet = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF202022),
  );
  static const raised = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF0F1F4),
    darkColor: Color(0xFF29292C),
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
