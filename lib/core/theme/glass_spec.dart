import 'package:flutter/cupertino.dart';

/// Frosted-surface metrics, ported from the AiChatApp floating tab bar so both
/// clients share the same glass recipe: a blurred band with a translucent
/// surface tint, a hairline outline, a soft drop shadow, and a separately
/// styled selected pill (its own fill, outline and shadow).
abstract final class GlassSpec {
  /// Floating navigation capsule.
  static const navHeight = 64.0;
  static const navInset = 16.0;
  static const navBottomGap = 8.0;
  static const navBlurSigma = 22.0;
  static const navDarkOpacity = .58;
  static const navLightOpacity = .70;
  static const navBorderOpacity = .42;
  static const navBorderWidth = .6;
  static const navShadowDarkOpacity = .28;
  static const navShadowLightOpacity = .12;
  static const navShadowBlur = 18.0;
  static const navShadowOffset = Offset(0, 6);

  /// Selected pill inside the capsule.
  static const indicatorRadius = 24.0;
  static const indicatorInset = 4.0;
  static const indicatorDarkOpacity = .82;
  static const indicatorLightOpacity = .86;
  static const indicatorBorderDarkOpacity = .32;
  static const indicatorBorderLightOpacity = .24;
  static const indicatorBorderWidth = .7;
  static const indicatorShadowDarkOpacity = .28;
  static const indicatorShadowLightOpacity = .10;
  static const indicatorShadowBlur = 10.0;
  static const indicatorShadowOffset = Offset(0, 2);

  /// Scroll padding so the last list item can clear the floating capsule.
  static const contentBottomInset = navHeight + navBottomGap + 26;

  /// Semantic outline used by the glass hairline.
  static const outlineDark = Color(0xFF2E2F32);
  static const outlineLight = Color(0xFFD1D1D6);
}
