import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../data/workspace.dart';
import '../platform/soft_keyboard.dart';
import 'app_widgets.dart';
import 'sheet.dart';
import '../theme/app_theme.dart';
import '../theme/glass_spec.dart';
import '../theme/design_tokens.dart';

Future<void> message(BuildContext context, String title, String body) =>
    showMessageSheet(context, title, body, icon: CupertinoIcons.info_circle);

Future<bool> confirm(BuildContext context, String title, String body) =>
    showConfirmSheet(context, title, body, destructive: true);

/// Option list rendered in the shared bottom panel.
Future<T?> choose<T>(
  BuildContext context,
  String title,
  Map<T, String> options, {
  String? subtitle,
  IconData? titleIcon,
  Map<T, String>? details,
  Map<T, IconData>? icons,
  Set<T>? disabled,
  Set<T>? selected,
  IconData? fallbackIcon,
}) => showOptionSheet<T>(
  context,
  title: title,
  subtitle: subtitle,
  titleIcon: titleIcon ?? fallbackIcon,
  options: [
    for (final entry in options.entries)
      SheetOption<T>(
        value: entry.key,
        title: entry.value,
        detail: details?[entry.key] ?? '',
        icon: icons?[entry.key] ?? fallbackIcon,
        enabled: !(disabled?.contains(entry.key) ?? false),
        selected: selected?.contains(entry.key) ?? false,
      ),
  ],
);

Future<String?> input(
  BuildContext context,
  String title, {
  String value = '',
  bool secret = false,
  bool copyable = false,
  String? hint,
  String? label,
  int maxLines = 1,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: value);
  final result = await showAppSheet<String>(
    context,
    (sheetContext) => _InputPanel(
      title: title,
      label: label,
      hint: hint,
      controller: controller,
      secret: secret,
      copyable: copyable,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onCancel: () => Navigator.of(sheetContext).pop(),
      onSave: () => Navigator.of(sheetContext).pop(controller.text.trim()),
    ),
  );
  // A dialog may still animate out after its future resolves.
  await Future<void>.delayed(const Duration(milliseconds: 320));
  controller.dispose();
  return result;
}

class _InputPanel extends StatefulWidget {
  const _InputPanel({
    required this.title,
    required this.controller,
    required this.secret,
    required this.copyable,
    required this.maxLines,
    required this.onCancel,
    required this.onSave,
    this.label,
    this.hint,
    this.keyboardType,
  });
  final String title;
  final String? label;
  final String? hint;
  final TextEditingController controller;
  final bool secret;
  final bool copyable;
  final int maxLines;
  final TextInputType? keyboardType;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  @override
  State<_InputPanel> createState() => _InputPanelState();
}

class _InputPanelState extends State<_InputPanel> {
  late bool obscured = widget.secret;
  bool copied = false;
  bool ready = false;
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Android can suppress the IME when it thinks a hardware keyboard is
    // attached. Re-assert the keyboard whenever this field gains focus, and
    // again from onTap, so a focused panel is always typeable.
    focusNode.addListener(_syncSoftKeyboard);
    // Mount the text field only after the sheet has settled. Its `autofocus`
    // then opens the IME exactly once, instead of racing the entrance
    // animation (the keyboard inset arriving mid-slide was what made the sheet
    // jump). A same-size placeholder keeps the layout from shifting meanwhile.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncSoftKeyboard());
    });
  }

  void _syncSoftKeyboard() {
    if (focusNode.hasFocus) showSoftKeyboard();
  }

  @override
  void dispose() {
    focusNode.removeListener(_syncSoftKeyboard);
    focusNode.dispose();
    super.dispose();
  }

  /// Same footprint as the text field, shown while the sheet animates in.
  Widget _fieldPlaceholder(BuildContext context) => Container(
    height: 45,
    decoration: BoxDecoration(
      color: AppColors.raised.resolveFrom(context),
      borderRadius: BorderRadius.circular(Radii.field),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return SheetPanel(
      title: widget.title,
      subtitle: widget.copyable ? '内容仅保存在本机安全存储，不会进入业务数据或日志' : null,
      scroll: true,
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                widget.label!,
                style: AppType.groupLabel.copyWith(color: secondary),
              ),
            ),
          ],
          if (!ready)
            _fieldPlaceholder(context)
          else
            CupertinoTextField(
              controller: widget.controller,
              focusNode: focusNode,
              autofocus: true,
              obscureText: obscured,
              enableSuggestions: !widget.secret,
              autocorrect: !widget.secret,
              minLines: widget.maxLines > 1 ? widget.maxLines : 1,
              maxLines: widget.maxLines,
              keyboardType: widget.keyboardType,
              onTap: () => showSoftKeyboard(),
              placeholder: widget.hint ?? '请输入',
              textInputAction: widget.maxLines > 1
                  ? TextInputAction.newline
                  : TextInputAction.done,
              style: AppType.rowTitle,
              padding: const EdgeInsets.fromLTRB(
                Gap.sm + 2,
                Gap.sm + 2,
                6,
                Gap.sm + 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.raised.resolveFrom(context),
                borderRadius: BorderRadius.circular(Radii.field),
              ),
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.secret)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                      onPressed: () => setState(() => obscured = !obscured),
                      child: Icon(
                        obscured
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: Sizes.icon,
                      ),
                    ),
                  if (widget.copyable)
                    CupertinoButton(
                      padding: const EdgeInsets.only(
                        right: Gap.xs,
                        left: Gap.xxs,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: widget.controller.text),
                        );
                        if (mounted) setState(() => copied = true);
                      },
                      child: Icon(
                        copied
                            ? CupertinoIcons.checkmark
                            : CupertinoIcons.doc_on_doc,
                        size: Sizes.icon,
                      ),
                    ),
                ],
              ),
            ),
          if (widget.copyable)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs, left: 2),
              child: Text(
                copied ? '已复制到剪贴板' : '可使用右侧按钮显示或复制内容',
                style: AppType.caption.copyWith(color: secondary),
              ),
            ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: widget.onCancel,
              child: SizedBox(
                height: 52,
                child: Center(child: Text('取消', style: AppType.button)),
              ),
            ),
          ),
          Container(width: .5, height: 34, color: separatorOf(context)),
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: widget.onSave,
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    '保存',
                    style: AppType.button.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      await message(
        context,
        '操作未完成',
        e is FormatException ? e.message.toString() : '请检查文件、系统权限或网络后重试。',
      );
    }
  }
}

/// Page scaffold: layered backdrop, floating title bar and scrollable body.
/// Pushed pages share the same backdrop so the glass controls always have
/// something to sample.
class Screen extends StatelessWidget {
  const Screen({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.sidebarCount = 0,
    this.onRefresh,
  });
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final int sidebarCount;

  /// Enables iOS-style pull-to-refresh on the page. The spinner sits just below
  /// the gradient header so the pull gesture stays visible.
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    // Only pages pushed on top of the shell show a back control. Counting every
    // route (Navigator.canPop) made the button appear on tab pages as soon as a
    // modal sheet or message was open above them.
    final back = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = sidebarCount > 0 && constraints.maxWidth >= 760;
        final content = wide
            ? <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 280,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children.take(sidebarCount).toList(),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children.skip(sidebarCount).toList(),
                      ),
                    ),
                  ],
                ),
              ]
            : children;
        final headerHeight = ScreenHeader.heightFor(back);
        return Stack(
          children: [
            const Positioned.fill(child: AppBackdrop()),
            Positioned.fill(
              child: onRefresh == null
                  ? ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        top + headerHeight + 6,
                        20,
                        GlassSpec.contentBottomInset +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: content.length,
                      itemBuilder: (context, index) => content[index],
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.only(top: top + headerHeight + 6),
                          sliver: CupertinoSliverRefreshControl(
                            onRefresh: onRefresh,
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            GlassSpec.contentBottomInset +
                                MediaQuery.paddingOf(context).bottom,
                          ),
                          sliver: SliverList.builder(
                            itemCount: content.length,
                            itemBuilder: (context, index) => content[index],
                          ),
                        ),
                      ],
                    ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ScreenHeader(
                title: title,
                compact: back,
                actions: actions,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Gradient header ported from AiChatApp's settings header: a blurred band
/// tinted with the page colour and masked by a vertical alpha gradient, so
/// scrolled content dissolves under the title instead of being cut off by a
/// hard edge or bleeding a hard coloured block behind the text.
///
/// The whole band absorbs taps; only the action buttons stay interactive, so
/// content scrolling underneath can never be hit through the title.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    required this.compact,
    this.actions = const [],
  });
  final String title;
  final bool compact;
  final List<Widget> actions;

  static double heightFor(bool compact) => compact ? 64 : 78;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final tint = AppColors.background.resolveFrom(context);
    final glass = glassEnabledOf(context) && !reduceEffectsOf(context);
    final veil = ColoredBox(color: tint.withValues(alpha: .97));
    return SizedBox(
      height: top + heightFor(compact),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Color(0xFFFFFFFF),
                      Color(0xFFFFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: const [0, .66, 1],
                  ).createShader(rect),
                  child: glass
                      ? BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                          child: veil,
                        )
                      : veil,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const SizedBox.expand(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Gap.md + 2,
              top + (compact ? 0 : Gap.xs),
              Gap.md + 2,
              compact ? 0 : Gap.xs + 2,
            ),
            child: Row(
              children: [
                if (compact) ...[
                  GlassIconButton(
                    icon: CupertinoIcons.chevron_left,
                    label: '返回',
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: Gap.xs),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: compact
                        ? AppType.navTitle
                        : AppType.pageTitle.copyWith(
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard list row: optional leading badge, title, supporting detail, value
/// or chevron. Uses the type scale so every list in the app shares one rhythm.
class SettingRow extends StatelessWidget {
  const SettingRow(
    this.title, {
    super.key,
    this.detail = '',
    this.onTap,
    this.trailing,
    this.leading,
  });
  final String title, detail;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoButton(
      padding: EdgeInsets.symmetric(
        vertical: detail.isEmpty ? Gap.sm + 2 : Gap.xs + 2,
        horizontal: Gap.md,
      ),
      pressedOpacity: .55,
      onPressed: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.row - 3),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Gap.sm)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.rowTitle.copyWith(
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowDetail.copyWith(color: secondary),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: Gap.xs),
                child: trailing,
              )
            else if (onTap != null)
              Icon(
                CupertinoIcons.chevron_right,
                size: Sizes.chevron,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
          ],
        ),
      ),
    );
  }
}

class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.store,
    required this.entry,
    this.onTap,
  });
  final Workspace store;
  final Entry entry;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.xs),
    child: GlassCard(
      padding: EdgeInsets.zero,
      child: SettingRow(
        store.name(entry.personId),
        detail:
            '${entry.fields['in']?.isNotEmpty == true ? entry.fields['in'] : '--:--'} → '
            '${entry.fields['out']?.isNotEmpty == true ? entry.fields['out'] : '--:--'}'
            '   ·   ${entry.fields['status']} · 修改人 ${entry.author}',
        onTap: onTap,
      ),
    ),
  );
}
