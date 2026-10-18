import 'package:flutter/cupertino.dart';

/// Frosted-surface metrics, ported from the AiChatApp floating tab bar so both
/// clients share the same glass recipe: a blurred band with a translucent
/// surface tint, a hairline outline, a soft drop shadow, and a separately
/// styled selected pill (its own fill, outline and shadow).
abstract final class GlassSpec {
  /// Floating navigation capsule.
  static const navHeight = 68.0;
  static const navInset = 20.0;
  static const navBottomGap = 10.0;
  static const navBlurSigma = 28.0;
  static const navDarkOpacity = .68;
  static const navLightOpacity = .76;
  static const navBorderOpacity = .75;
  static const navBorderWidth = .6;
  static const navShadowDarkOpacity = .28;
  static const navShadowLightOpacity = .12;
  static const navShadowBlur = 18.0;
  static const navShadowOffset = Offset(0, 6);

  /// Selected pill inside the capsule.
  static const indicatorRadius = 24.0;
  static const indicatorInset = 4.0;
  static const indicatorDarkOpacity = .94;
  static const indicatorLightOpacity = .96;
  static const indicatorBorderDarkOpacity = .12;
  static const indicatorBorderLightOpacity = .08;
  static const indicatorBorderWidth = .7;
  static const indicatorShadowDarkOpacity = .28;
  static const indicatorShadowLightOpacity = .10;
  static const indicatorShadowBlur = 10.0;
  static const indicatorShadowOffset = Offset(0, 2);

  /// Scroll padding so the last list item can clear the floating capsule.
  static const contentBottomInset = navHeight + navBottomGap + 26;

  /// Semantic outline used by the glass hairline.
  static const outlineDark = Color(0xFF656568);
  static const outlineLight = Color(0xFFFFFFFF);
}
