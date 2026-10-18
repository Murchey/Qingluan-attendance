import 'package:flutter/cupertino.dart';

import '../data/workspace.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'sheet.dart';

/// Single-select person sheet with a search field. Used wherever a flow needs
/// to pick exactly one person (leave, and any future form): a long roster is
/// unusable without filtering, and the sheet keeps the choice one tap away.
Future<String?> showPersonPickerSheet(
  BuildContext context, {
  required List<Person> people,
  String title = '选择人员',
  String subtitle = '',
  String? selectedId,
  Set<String> disabledIds = const {},
  String searchHint = '搜索姓名或工号',
}) {
  return showAppSheet<String>(
    context,
    (sheetContext) {
      var query = '';
      List<Person> filtered() {
        final text = query.trim().toLowerCase();
        if (text.isEmpty) return people;
        return people
            .where(
              (p) =>
                  p.name.toLowerCase().contains(text) ||
                  p.employeeId.toLowerCase().contains(text),
            )
            .toList();
      }

      return StatefulBuilder(
        builder: (context, setSheet) {
          final rows = filtered();
          final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
          return SheetPanel(
            title: title,
            subtitle: subtitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
                  child: CupertinoSearchTextField(
                    placeholder: searchHint,
                    onChanged: (value) => setSheet(() => query = value),
                    onSubmitted: (value) => setSheet(() => query = value),
                  ),
                ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.lg,
                    ),
                    child: Text(
                      query.trim().isEmpty ? '还没有人员' : '没有匹配的人员',
                      style: AppType.footnoteStyle.copyWith(color: secondary),
                    ),
                  )
                else
                  for (final person in rows)
                    _PersonRow(
                      person: person,
                      selected: person.id == selectedId,
                      disabled: disabledIds.contains(person.id),
                      onTap: () => Navigator.of(sheetContext).pop(person.id),
                    ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });
  final Person person;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoDynamicColor.resolve(AppColors.navy, context);
    final detail = [
      if (person.employeeId.isNotEmpty) person.employeeId,
      if (person.gender.isNotEmpty) person.gender,
      if (!person.active) '已停用',
      if (disabled) '请假中',
    ].join(' · ');
    return Opacity(
      opacity: disabled ? .45 : 1,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 56),
        pressedOpacity: .6,
        onPressed: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      person.name,
                      style: AppType.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: AppType.caption.copyWith(color: secondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(CupertinoIcons.checkmark_alt, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
