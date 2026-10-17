import 'package:flutter/cupertino.dart';
import '../data/workspace.dart';
import 'app_widgets.dart';

Future<void> message(BuildContext context, String title, String body) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c),
            child: const Text('好'),
          ),
        ],
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
    actions: options.entries
        .map(
          (e) => CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c, e.key),
            child: Text(e.value),
          ),
        )
        .toList(),
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
}) async {
  final controller = TextEditingController(text: value);
  final result = await showCupertinoDialog<String>(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          controller: controller,
          autofocus: true,
          obscureText: secret,
          enableSuggestions: !secret,
          autocorrect: !secret,
          placeholder: title,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(c),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // A dialog may still animate out after its future resolves.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
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
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: CupertinoTheme.of(
                  context,
                ).textTheme.navLargeTitleTextStyle,
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: 18),
        if (sidebarCount > 0)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                );
              }
              return Row(
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
              );
            },
          )
        else
          ...children,
      ],
    ),
  );
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
