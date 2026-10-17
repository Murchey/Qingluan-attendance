import 'dart:ui';
import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';

class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});
  final bool enabled;
  @override
  bool updateShouldNotify(GlassScope oldWidget) => enabled != oldWidget.enabled;
}

/// Only floating controls sample the backdrop; scrolling cards are opaque.
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
        navigation &&
        (context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ??
            true) &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    final radius = BorderRadius.circular(navigation ? 34 : 18);
    final tint = color ?? AppColors.surface.resolveFrom(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: blur ? .88 : 1),
        borderRadius: radius,
        border: Border.all(
          color: CupertinoColors.separator
              .resolveFrom(context)
              .withValues(alpha: dark ? .18 : .10),
          width: .5,
        ),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: navigation
            ? [
                BoxShadow(
                  color: CupertinoColors.black.withValues(
                    alpha: dark ? .20 : .08,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: blur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: content,
              )
            : content,
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 42,
        height: 42,
        child: GlassCard(
          navigation: true,
          padding: EdgeInsets.zero,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    ),
  );
}

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ColoredBox(color: AppColors.background.resolveFrom(context)),
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
