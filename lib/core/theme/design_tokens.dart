import 'package:flutter/cupertino.dart';

/// iOS Dynamic Type scale (points) with the weights this app actually uses.
/// Every screen should pick from here instead of ad-hoc sizes: mixing 12/12.5/
/// 13.5/15.5 with no rhythm is what reads as "amateur" even when the colours and
/// blur are right.
abstract final class AppType {
  static const largeTitle = 30.0;
  static const title1 = 28.0;
  static const title2 = 22.0;
  static const title3 = 20.0;
  static const headline = 17.0;
  static const body = 17.0;
  static const callout = 16.0;
  static const subhead = 15.0;
  static const footnote = 13.0;
  static const caption1 = 12.0;
  static const caption2 = 11.0;

  static const pageTitle = TextStyle(
    fontSize: largeTitle,
    fontWeight: FontWeight.w600,
    letterSpacing: -.4,
    height: 1.15,
  );
  static const navTitle = TextStyle(
    fontSize: headline,
    fontWeight: FontWeight.w600,
    letterSpacing: -.2,
    height: 1.2,
  );
  static const sectionTitle = TextStyle(
    fontSize: headline,
    fontWeight: FontWeight.w600,
    letterSpacing: -.2,
  );
  static const groupLabel = TextStyle(
    fontSize: footnote,
    fontWeight: FontWeight.w600,
    letterSpacing: .1,
  );
  static const rowTitle = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w400,
    height: 1.25,
  );
  static const rowTitleEmphasized = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  static const rowDetail = TextStyle(
    fontSize: footnote,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );
  static const button = TextStyle(
    fontSize: callout,
    fontWeight: FontWeight.w600,
  );
  static const sheetTitle = TextStyle(
    fontSize: title3,
    fontWeight: FontWeight.w700,
    letterSpacing: -.3,
  );
  static const sheetOption = TextStyle(
    fontSize: headline,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
  static const metric = TextStyle(
    fontSize: largeTitle,
    fontWeight: FontWeight.w600,
    letterSpacing: -.5,
    height: 1.05,
  );
  static const caption = TextStyle(fontSize: caption1, height: 1.35);
  static const footnoteStyle = TextStyle(fontSize: footnote, height: 1.35);
  static const cell = TextStyle(fontSize: subhead, fontWeight: FontWeight.w500);
  static const calloutStyle = TextStyle(fontSize: callout, height: 1.35);
  static const message = TextStyle(fontSize: callout, height: 1.5);
}

/// 4pt spacing rhythm. Sections use md/lg, groups use lg, page gutters use lg.
abstract final class Gap {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Concentric radii: sheets > cards > controls > badges. Keeping this ladder
/// (instead of 12/14/18/20/28/30 used at random) is most of "looks intentional".
abstract final class Radii {
  static const sheet = 28.0;
  static const card = 20.0;
  static const control = 14.0;
  static const field = 12.0;
  static const badge = 9.0;
  static const pill = 999.0;
}

abstract final class Sizes {
  /// Apple's minimum comfortable target; every icon-only control uses this.
  static const touch = 44.0;
  static const row = 48.0;
  static const cta = 50.0;
  static const badge = 30.0;
  static const icon = 20.0;
  static const iconSmall = 16.0;
  static const chevron = 15.0;
}
