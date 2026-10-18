import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'app_widgets.dart';

/// Scrollable bottom panel used across the app instead of the stock action
/// sheet: grabber, pinned title, scrollable body and an optional pinned footer.
///
/// The panel owns the keyboard: it requests focus for its own scope (a
/// `showGeneralDialog` route does not), animates above the keyboard inset and
/// dismisses the keyboard when the panel background is tapped.
Future<T?> showAppSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  double maxHeightFactor = .88,
  bool barrierDismissible = true,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierLabel: '关闭',
  barrierColor: const Color(0x99000000),
  transitionDuration: const Duration(milliseconds: 260),
  // A dialog route only takes focus (and therefore raises the IME) when it
  // explicitly asks for it. Without this the text fields inside the panel get
  // no primary focus and the soft keyboard never appears.
  requestFocus: true,
  pageBuilder: (context, animation, secondaryAnimation) =>
      const SizedBox.shrink(),
  transitionBuilder: (context, animation, secondaryAnimation, child) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .06),
          end: Offset.zero,
        ).animate(curve),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _SheetFrame(
            maxHeightFactor: maxHeightFactor,
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  },
);

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, required this.maxHeightFactor});
  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * maxHeightFactor,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.sheet.resolveFrom(context),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Radii.sheet),
            ),
            border: Border(
              top: BorderSide(
                color: const Color(
                  0xFFFFFFFF,
                ).withValues(alpha: dark ? .12 : 0),
                width: .8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF000000,
                ).withValues(alpha: dark ? .6 : .16),
                blurRadius: 36,
                spreadRadius: -4,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: Gap.xs),
                Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CupertinoColors.separator
                        .resolveFrom(context)
                        .withValues(alpha: dark ? .5 : .4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Body layout for a panel: optional pinned header, scrollable content and an
/// optional pinned footer (e.g. the cancel row).
class SheetPanel extends StatelessWidget {
  const SheetPanel({
    super.key,
    this.title,
    this.subtitle,
    this.titleIcon,
    this.headerTrailing,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
    this.scroll = true,
    required this.child,
  });
  final String? title;
  final String? subtitle;
  final IconData? titleIcon;
  final Widget? headerTrailing;
  final Widget child;
  final Widget? footer;
  final EdgeInsets padding;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final body = Padding(padding: padding, child: child);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.sm, Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titleIcon != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(titleIcon, size: Sizes.icon, color: secondary),
                  ),
                  const SizedBox(width: Gap.xs),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sheetTitle,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.rowDetail.copyWith(color: secondary),
                          ),
                        ),
                    ],
                  ),
                ),
                ?headerTrailing,
              ],
            ),
          ),
        if (title != null)
          Container(height: .5, color: separatorOf(context)),
        Flexible(
          child: GestureDetector(
            // Tapping the panel background dismisses the keyboard without
            // closing the sheet; buttons inside still win the tap.
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: scroll
                ? SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: body,
                  )
                : body,
          ),
        ),
        if (footer != null) ...[
          Container(height: .5, color: separatorOf(context)),
          footer!,
        ],
      ],
    );
  }
}

class SheetOption<T> {
  const SheetOption({
    required this.value,
    required this.title,
    this.detail = '',
    this.icon,
    this.enabled = true,
    this.selected = false,
    this.trailing,
    this.showChevron = false,
  });
  final T value;
  final String title;
  final String detail;
  final IconData? icon;
  final bool enabled;
  final bool selected;
  final Widget? trailing;
  final bool showChevron;
}

/// Selectable list in the bottom panel. Returns the chosen value or null.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  IconData? titleIcon,
  required List<SheetOption<T>> options,
  String? cancelLabel = '取消',
  Widget? footer,
  double maxHeightFactor = .88,
}) => showAppSheet<T>(
  context,
  (sheetContext) => SheetPanel(
    title: title,
    subtitle: subtitle,
    titleIcon: titleIcon,
    padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.sm),
    footer: cancelLabel == null
        ? null
        : _CancelRow(
            text: cancelLabel,
            onTap: () => Navigator.of(sheetContext).pop(),
          ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++)
          _OptionRow<T>(
            option: options[i],
            divider: i > 0,
            onTap: () => Navigator.of(sheetContext).pop(options[i].value),
          ),
        ?footer,
      ],
    ),
  ),
  maxHeightFactor: maxHeightFactor,
);

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.divider,
    required this.onTap,
  });
  final SheetOption<T> option;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = option.enabled
        ? CupertinoColors.label.resolveFrom(context)
        : CupertinoColors.tertiaryLabel.resolveFrom(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (divider)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Container(height: .5, color: separatorOf(context)),
          ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          pressedOpacity: .55,
          onPressed: option.enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: option.icon == null
                      ? const SizedBox.shrink()
                      : Icon(option.icon, size: Sizes.icon, color: secondary),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sheetOption.copyWith(
                          color: label,
                          fontWeight: option.selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      if (option.detail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            option.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.rowDetail.copyWith(color: secondary),
                          ),
                        ),
                    ],
                  ),
                ),
                if (option.trailing != null) option.trailing!,
                if (option.selected)
                  Padding(
                    padding: const EdgeInsets.only(left: Gap.xs),
                    child: Icon(
                      CupertinoIcons.checkmark_alt,
                      size: 20,
                      color: CupertinoTheme.of(context).primaryColor,
                    ),
                  ),
                if (!option.selected && option.showChevron)
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: Sizes.chevron,
                    color: secondary,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CancelRow extends StatelessWidget {
  const _CancelRow({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    pressedOpacity: .5,
    onPressed: onTap,
    child: SizedBox(
      height: 52,
      child: Center(child: Text(text, style: AppType.button)),
    ),
  );
}

/// Non-selectable message in a panel.
Future<void> showMessageSheet(
  BuildContext context,
  String title,
  String body, {
  String action = '好',
  IconData? icon,
}) => showAppSheet<void>(
  context,
  (sheetContext) => SheetPanel(
    title: title,
    titleIcon: icon,
    footer: _CancelRow(
      text: action,
      onTap: () => Navigator.of(sheetContext).pop(),
    ),
    child: Text(
      body,
      style: AppType.message.copyWith(
        height: 1.5,
        color: CupertinoColors.label.resolveFrom(context),
      ),
    ),
  ),
);

Future<bool> showConfirmSheet(
  BuildContext context,
  String title,
  String body, {
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showAppSheet<bool>(
    context,
    (sheetContext) => SheetPanel(
      title: title,
      footer: Row(
        children: [
          Expanded(
            child: _CancelRow(
              text: cancelLabel,
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ),
          Container(width: .5, height: 34, color: separatorOf(context)),
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    confirmLabel,
                    style: AppType.button.copyWith(
                      color: destructive
                          ? CupertinoColors.destructiveRed
                          : CupertinoTheme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      child: Text(
        body,
        style: AppType.message.copyWith(
          height: 1.5,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
    ),
  );
  return result ?? false;
}
