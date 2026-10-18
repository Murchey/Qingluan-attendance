import 'dart:ui';
import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import '../theme/glass_spec.dart';

/// User/perf switch for frosted surfaces. When this is off the floating bar is
/// drawn as a plain opaque slab, so no backdrop is sampled at all.
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});
  final bool enabled;
  @override
  bool updateShouldNotify(GlassScope oldWidget) => enabled != oldWidget.enabled;
}

bool glassEnabledOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ?? true;

bool reduceEffectsOf(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

Color glassOutlineOf(BuildContext context) =>
    CupertinoTheme.brightnessOf(context) == Brightness.dark
    ? GlassSpec.outlineDark
    : GlassSpec.outlineLight;

/// Single hairline colour for group dividers and card outlines.
Color separatorOf(BuildContext context) {
  final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
  return dark
      ? const Color(0xFFFFFFFF).withValues(alpha: .08)
      : const Color(0xFF000000).withValues(alpha: .08);
}

/// Flat page background: the frosted bar samples real content as it scrolls
/// underneath, so the surface reads as glass instead of painted depth.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppColors.background.resolveFrom(context));
}

/// Legacy name kept for the shell.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});
  @override
  Widget build(BuildContext context) => const AppBackdrop();
}

/// Scrolling content stays opaque; only floating controls ([navigation]) sample
/// the backdrop. Turning the glass switch off makes those opaque too.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.md),
    this.color,
    this.navigation = false,
    this.radius,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final bool navigation;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final frosted =
        navigation && glassEnabledOf(context) && !reduceEffectsOf(context);
    final r = BorderRadius.circular(
      radius ?? (navigation ? GlassSpec.navHeight / 2 : Radii.card),
    );
    final surface = color ?? AppColors.surface.resolveFrom(context);
    final outline = glassOutlineOf(context);

    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        // Frosted: translucent surface over the blurred content. Opaque mode:
        // plain surface, no blur cost at all.
        color: frosted
            ? surface.withValues(
                alpha: dark
                    ? GlassSpec.navDarkOpacity
                    : GlassSpec.navLightOpacity,
              )
            : surface,
        borderRadius: r,
        border: Border.all(
          color: navigation
              ? outline.withValues(alpha: GlassSpec.navBorderOpacity)
              : separatorOf(context),
          width: navigation ? GlassSpec.navBorderWidth : .6,
        ),
      ),
      child: child,
    );
    if (frosted) {
      body = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassSpec.navBlurSigma,
          sigmaY: GlassSpec.navBlurSigma,
        ),
        child: body,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(
              alpha: dark
                  ? (navigation ? GlassSpec.navShadowDarkOpacity : 0)
                  : (navigation ? GlassSpec.navShadowLightOpacity : .05),
            ),
            blurRadius: navigation ? GlassSpec.navShadowBlur : 14,
            offset: navigation ? GlassSpec.navShadowOffset : const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: r, child: body),
    );
  }
}

/// Selected pill inside the navigation capsule: its own fill, accent-tinted
/// outline and shadow, so the selected state sits *on* the glass.
class GlassIndicator extends StatelessWidget {
  const GlassIndicator({super.key, required this.radius});
  final double radius;
  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final accent = CupertinoTheme.of(context).primaryColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.raised.resolveFrom(context).withValues(
          alpha: dark
              ? GlassSpec.indicatorDarkOpacity
              : GlassSpec.indicatorLightOpacity,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: accent.withValues(
            alpha: dark
                ? GlassSpec.indicatorBorderDarkOpacity
                : GlassSpec.indicatorBorderLightOpacity,
          ),
          width: GlassSpec.indicatorBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(
              alpha: dark
                  ? GlassSpec.indicatorShadowDarkOpacity
                  : GlassSpec.indicatorShadowLightOpacity,
            ),
            blurRadius: GlassSpec.indicatorShadowBlur,
            offset: GlassSpec.indicatorShadowOffset,
          ),
        ],
      ),
    );
  }
}

/// Circular header control, ported from AiChatApp's glass back button: a small
/// backdrop blur, a translucent fill and a hairline outline. No drop shadow —
/// the outline is what makes it read as a piece of glass over scrolling content.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = Sizes.touch,
    this.tint,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final glass = glassEnabledOf(context) && !reduceEffectsOf(context);
    final fill =
        tint ??
        AppColors.raised.resolveFrom(context).withValues(
          alpha: glass ? .65 : 1,
        );
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: CupertinoColors.secondaryLabel
              .resolveFrom(context)
              .withValues(alpha: dark ? .32 : .25),
          width: 1,
        ),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: .55,
        onPressed: onPressed,
        child: Icon(
          icon,
          size: Sizes.icon,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Semantics(
        button: true,
        label: label,
        child: ClipOval(
          child: glass
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: disc,
                )
              : disc,
        ),
      ),
    );
  }
}

/// Primary call to action. Filled buttons take the documented navy in both
/// schemes: on a near-black page the pale accent would read as a washed-out
/// tinted block instead of a deliberate navy control.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.borderRadius = Radii.control,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final double borderRadius;
  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    const navy = Color(0xFF172A46);
    return CupertinoButton(
      minimumSize: const Size(0, Sizes.cta),
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      pressedOpacity: .8,
      borderRadius: BorderRadius.circular(borderRadius),
      color: navy,
      disabledColor: navy.withValues(alpha: .35),
      onPressed: onPressed,
      child: DefaultTextStyle.merge(
        style: AppType.button.copyWith(
          color: dark ? const Color(0xFFEAF1F9) : CupertinoColors.white,
          decoration: TextDecoration.none,
        ),
        child: child,
      ),
    );
  }
}

/// Tinted square glyph used by grouped lists (Apple Settings wayfinding).
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.tint,
    this.size = Sizes.badge,
  });
  final IconData icon;
  final Color tint;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tint.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(Radii.badge),
    ),
    child: Icon(icon, size: size * .58, color: tint),
  );
}

/// Section label above a grouped card (Apple's grouped-list header).
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.xxs, 0, Gap.xxs, Gap.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: AppType.groupLabel.copyWith(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: AppType.caption.copyWith(
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ),
      ],
    ),
  );
}

/// Grouped card whose children are separated by inset hairlines, the way iOS
/// inset-grouped tables do it. [dividerInset] matches the title gutter so the
/// line starts after a leading badge.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.dividerInset = Gap.md,
  });
  final List<Widget> children;
  final double dividerInset;
  @override
  Widget build(BuildContext context) => GlassCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.only(left: dividerInset),
              child: Container(height: .5, color: separatorOf(context)),
            ),
          children[i],
        ],
      ],
    ),
  );
}

/// In-page section heading with an optional trailing action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: AppType.sectionTitle)),
      ?action,
    ],
  );
}

/// iOS segmented control: neutral track, raised pill for the selection. Use this
/// instead of accent-filled chips so the navy stays reserved for the single
/// primary action on a screen.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.expanded = true,
  });
  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final children = [
      for (var i = 0; i < values.length; i++)
        _segment(context, i, dark),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1F1F23) : const Color(0xFFE9E9EE),
        borderRadius: BorderRadius.circular(Radii.badge + 2),
      ),
      child: expanded
          ? Row(children: [for (final c in children) Expanded(child: c)])
          : Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _segment(BuildContext context, int i, bool dark) {
    final selected = values[i] == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!selected) onChanged(values[i]);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.surface.resolveFrom(context)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(Radii.badge),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(
                      alpha: dark ? .38 : .10,
                    ),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : const [],
        ),
        child: Text(
          labels[i],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.caption.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? CupertinoColors.label.resolveFrom(context)
                : CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
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
    padding: const EdgeInsets.symmetric(horizontal: Gap.xs + 2, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppType.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Empty state with a single, obvious next action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.xl,
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 28,
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
          ),
          const SizedBox(height: Gap.sm),
          Text(title, style: AppType.rowTitleEmphasized),
          const SizedBox(height: Gap.xxs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.rowDetail.copyWith(color: secondary),
          ),
          if (action != null) ...[const SizedBox(height: Gap.md), action!],
        ],
      ),
    );
  }
}
