import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../data/workspace.dart';
import 'app_widgets.dart';
import '../theme/app_theme.dart';

Future<void> message(BuildContext context, String title, String body) =>
    showCupertinoModalPopup<void>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: Text(title),
        message: Text(body),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c),
          child: const Text('好'),
        ),
      ),
    );
Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showCupertinoModalPopup<bool>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: Text(title),
        message: Text(body),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('取消'),
        ),
      ),
    ) ??
    false;
Future<T?> choose<T>(
  BuildContext context,
  String title,
  Map<T, String> options,
) => showCupertinoModalPopup<T>(
  context: context,
  builder: (c) => CupertinoActionSheet(
    title: Text(title),
    actions: [
      SizedBox(
        height: (options.length * 52.0).clamp(0, 360),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (_, i) {
            final e = options.entries.elementAt(i);
            return CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(c, e.key),
              child: Text(e.value),
            );
          },
        ),
      ),
    ],
    cancelButton: CupertinoActionSheetAction(
      onPressed: () => Navigator.pop(c),
      child: const Text('取消'),
    ),
  ),
);
Future<String?> input(
  BuildContext context,
  String title, {
  String value = '',
  bool secret = false,
  bool copyable = false,
}) async {
  final controller = TextEditingController(text: value);
  final result = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '取消',
    barrierColor: const Color(0x52000000),
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
    pageBuilder: (c, animation, secondaryAnimation) => Align(
      alignment: Alignment.bottomCenter,
      child: _InputSheet(
        title: title,
        controller: controller,
        secret: secret,
        copyable: copyable,
      ),
    ),
  );
  // A dialog may still animate out after its future resolves.
  await Future<void>.delayed(const Duration(milliseconds: 180));
  controller.dispose();
  return result;
}

class _InputSheet extends StatefulWidget {
  const _InputSheet({
    required this.title,
    required this.controller,
    required this.secret,
    required this.copyable,
  });
  final String title;
  final TextEditingController controller;
  final bool secret;
  final bool copyable;
  @override
  State<_InputSheet> createState() => _InputSheetState();
}

class _InputSheetState extends State<_InputSheet> {
  late bool obscured = widget.secret;
  bool copied = false;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final surface = AppColors.surface.resolveFrom(context);
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 24,
                offset: Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CupertinoColors.separator.resolveFrom(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.only(left: 12),
                      onPressed: () =>
                          Navigator.pop(context, widget.controller.text.trim()),
                      child: const Text('保存'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: widget.controller,
                  autofocus: true,
                  obscureText: obscured,
                  enableSuggestions: !widget.secret,
                  autocorrect: !widget.secret,
                  placeholder: widget.title,
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.secret)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: () => setState(() => obscured = !obscured),
                          child: Icon(
                            obscured
                                ? CupertinoIcons.eye
                                : CupertinoIcons.eye_slash,
                            size: 20,
                          ),
                        ),
                      if (widget.copyable)
                        CupertinoButton(
                          padding: const EdgeInsets.only(right: 10, left: 4),
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
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                ),
                if (widget.copyable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      copied ? '已复制到剪贴板' : '可使用右侧按钮显示或复制内容',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
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

class Screen extends StatelessWidget {
  const Screen({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.sidebarCount = 0,
  });
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final int sidebarCount;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final background = AppColors.background.resolveFrom(context);
    final back = Navigator.of(context).canPop();
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
        return ColoredBox(
          color: background,
          child: Stack(
            children: [
              ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  20,
                  top + 86,
                  20,
                  120 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: content.length,
                itemBuilder: (context, index) => content[index],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(17, top + 10, 17, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        background,
                        background.withValues(alpha: .96),
                        background.withValues(alpha: 0),
                      ],
                      stops: const [0, .5, 1],
                    ),
                  ),
                  child: Row(
                    children: [
                      if (back) ...[
                        GlassIconButton(
                          icon: CupertinoIcons.chevron_left,
                          label: '返回',
                          onPressed: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .navLargeTitleTextStyle
                              .copyWith(fontSize: back ? 23 : 30),
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow(
    this.title, {
    super.key,
    this.detail = '',
    this.onTap,
    this.trailing,
  });
  final String title, detail;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
    onPressed: onTap,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: CupertinoColors.label.resolveFrom(context),
                  fontSize: 16,
                ),
              ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    style: TextStyle(
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        trailing ??
            (onTap == null
                ? const SizedBox.shrink()
                : const Icon(CupertinoIcons.chevron_right, size: 16)),
      ],
    ),
  );
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
    padding: const EdgeInsets.only(bottom: 8),
    child: GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: SettingRow(
        store.name(entry.personId),
        detail:
            '${entry.fields['in']?.isNotEmpty == true ? entry.fields['in'] : '--:--'} → ${entry.fields['out']?.isNotEmpty == true ? entry.fields['out'] : '--:--'}\n${entry.fields['status']} · 修改人 ${entry.author}',
        onTap: onTap,
        trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
      ),
    ),
  );
}
