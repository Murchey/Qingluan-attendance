import 'dart:ui';
import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';

class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});
  final bool enabled;
  @override
  bool updateShouldNotify(GlassScope oldWidget) => enabled != oldWidget.enabled;
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.navigation = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final bool navigation;
  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final blur =
        (context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ??
            true) &&
        !MediaQuery.of(context).disableAnimations &&
        !MediaQuery.of(context).accessibleNavigation;
    final radius = BorderRadius.circular(navigation ? 34 : 24);
    final tint =
        color ??
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: blur ? (navigation ? .52 : .68) : .96),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CupertinoColors.white.withValues(alpha: dark ? .065 : .38),
            CupertinoColors.white.withValues(alpha: dark ? .015 : .08),
            CupertinoColors.systemGrey.withValues(alpha: dark ? .035 : .06),
          ],
          stops: const [0, .45, 1],
        ),
        borderRadius: radius,
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(
              alpha: dark
                  ? .24
                  : navigation
                  ? .13
                  : .045,
            ),
            blurRadius: navigation ? 32 : 20,
            offset: Offset(0, navigation ? 10 : 5),
          ),
          if (navigation)
            BoxShadow(
              color: CupertinoColors.white.withValues(alpha: dark ? .035 : .6),
              blurRadius: 1,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          foregroundPainter: _GlassEdge(
            dark: dark,
            radius: navigation ? 34 : 24,
          ),
          child: blur
              ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: navigation ? 32 : 20,
                    sigmaY: navigation ? 32 : 20,
                  ),
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}

/// Specular rim stays outside the padded content and does not intercept taps.
class _GlassEdge extends CustomPainter {
  const _GlassEdge({required this.dark, required this.radius});
  final bool dark;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          CupertinoColors.white.withValues(alpha: dark ? .28 : .95),
          CupertinoColors.white.withValues(alpha: dark ? .035 : .2),
          CupertinoColors.systemGrey.withValues(alpha: dark ? .16 : .24),
          CupertinoColors.white.withValues(alpha: dark ? .12 : .65),
        ],
        stops: const [0, .4, .75, 1],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.5), Radius.circular(radius - .5)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlassEdge oldDelegate) =>
      dark != oldDelegate.dark || radius != oldDelegate.radius;
}

/// Apple grouped pages use neutral system surfaces in both appearances.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ColoredBox(
      color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
      ),
      ?action,
    ],
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon = CupertinoIcons.circle_filled,
  });
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Icon(icon, size: 36, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(
          title,
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}
