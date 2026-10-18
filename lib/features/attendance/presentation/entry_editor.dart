import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/ui.dart';
import '../../leave/presentation/leave_editor.dart';

Future<void> openEditor(
  BuildContext context,
  Workspace store,
  String day, {
  Entry? entry,
  String? initialPersonId,
}) async {
  if (store.identity.isEmpty) {
    final name = await input(context, '请先填写本地显示名');
    if (name == null || name.isEmpty) return;
    await store.setIdentity(name);
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => EntryEditor(
        store: store,
        day: day,
        entry: entry,
        initialPersonId: initialPersonId,
      ),
    ),
  );
}

const statusIcons = {
  '正常': CupertinoIcons.checkmark_circle,
  '迟到': CupertinoIcons.clock,
  '早退': CupertinoIcons.arrow_left_square,
  '请假': CupertinoIcons.calendar_badge_minus,
  '缺勤': CupertinoIcons.xmark_circle,
};

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.store,
    required this.day,
    this.entry,
    this.initialPersonId,
  });
  final Workspace store;
  final String day;
  final Entry? entry;
  final String? initialPersonId;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final selected = <String>{};
  late Map<String, String> fields;
  late TextEditingController note;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    fields = Map.from(
      widget.entry?.fields ?? {'in': '', 'out': '', 'status': '正常', 'note': ''},
    );
    note = TextEditingController(text: fields['note']);
    if (widget.entry != null) selected.add(widget.entry!.personId);
    if (widget.entry == null && widget.initialPersonId != null) {
      selected.add(widget.initialPersonId!);
    }
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> time(String key) async {
    final date = DateTime.parse(widget.day);
    final parts = (fields[key] ?? '').split(':');
    var value = DateTime(
      date.year,
      date.month,
      date.day,
      int.tryParse(parts.first) ?? 9,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final confirmed = await showAppSheet<bool>(
      context,
      (sheetContext) => SheetPanel(
        title: key == 'in' ? '签到时间' : '签退时间',
        scroll: false,
        child: SizedBox(
          height: 200,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: true,
            initialDateTime: value,
            onDateTimeChanged: (v) => value = v,
          ),
        ),
        footer: Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const SizedBox(
                  height: 52,
                  child: Center(child: Text('取消')),
                ),
              ),
            ),
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const SizedBox(
                  height: 52,
                  child: Center(
                    child: Text(
                      '确定',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      setState(
        () => fields[key] =
            '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> pickPeople() async {
    final result = await Navigator.of(context).push<Set<String>>(
      CupertinoPageRoute<Set<String>>(
        builder: (_) => PersonPickerPage(
          store: widget.store,
          selected: selected,
          day: widget.day,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        selected
          ..clear()
          ..addAll(result);
      });
    }
  }

  List<Leave> get blockedLeaves => selected
      .map((id) => widget.store.leaveOf(id, widget.day))
      .whereType<Leave>()
      .toList();

  Future<void> editLeave(Leave leave) async {
    await openLeaveEditor(
      context,
      widget.store,
      leave: leave,
      personId: leave.personId,
      day: widget.day,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final blocked = blockedLeaves;
    return CupertinoPageScaffold(
      child: Screen(
        title: widget.day,
        children: [
          if (blocked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.calendar_badge_minus,
                          size: 18,
                          color: AppColors.leave.resolveFrom(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${blocked.map((l) => widget.store.name(l.personId)).join('、')} '
                            '当天已确认请假',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.leave.resolveFrom(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '请假当天不可登记考勤。请先调整请假状态或时间，'
                      '或直接修改这条请假记录。',
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final leave in blocked)
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            color: AppColors.leave.resolveFrom(
                              context,
                            ).withValues(alpha: .14),
                            onPressed: () => editLeave(leave),
                            child: Text(
                              '编辑 ${widget.store.name(leave.personId)} 的请假',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.leave.resolveFrom(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingRow(
                  '登记人员',
                  detail: selected.isEmpty ? '未选择' : '已选 ${selected.length} 人',
                  onTap: pickPeople,
                ),
                _divider(context),
                SettingRow(
                  '签到时间',
                  detail: fields['in']!.isEmpty ? '未填写' : fields['in']!,
                  onTap: () => time('in'),
                ),
                _divider(context),
                SettingRow(
                  '签退时间',
                  detail: fields['out']!.isEmpty ? '未填写' : fields['out']!,
                  onTap: () => time('out'),
                ),
              ],
            ),
          ),
          if (fields['in']!.isNotEmpty || fields['out']!.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.xs,
                  vertical: Gap.xxs,
                ),
                onPressed: () => setState(() {
                  fields['in'] = '';
                  fields['out'] = '';
                }),
                child: Text(
                  '清空时间',
                  style: AppType.footnoteStyle.copyWith(
                    color: CupertinoTheme.of(context).primaryColor,
                  ),
                ),
              ),
            ),
          const SizedBox(height: Gap.sm),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingRow(
                  '状态',
                  detail: '',
                  onTap: () async {
                    final s = await choose<String>(
                      context,
                      '考勤状态',
                      {for (final s in statuses) s: s},
                      icons: statusIcons,
                      selected: {fields['status']!},
                    );
                    if (s != null && mounted) {
                      setState(() => fields['status'] = s);
                    }
                  },
                  trailing: StatusPill(
                    label: fields['status']!,
                    color: _statusColor(context, fields['status']!),
                    icon: statusIcons[fields['status']] ?? CupertinoIcons.circle,
                  ),
                ),
                _divider(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.md,
                    Gap.sm,
                    Gap.md,
                    Gap.md,
                  ),
                  child: CupertinoTextField(
                    controller: note,
                    placeholder: '备注（选填）',
                    minLines: 3,
                    maxLines: 5,
                    style: AppType.rowTitle,
                    padding: const EdgeInsets.all(Gap.sm + 2),
                    decoration: BoxDecoration(
                      color: AppColors.raised.resolveFrom(context),
                      borderRadius: BorderRadius.circular(Radii.field),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),          PrimaryButton(
            onPressed: saving
                ? null
                : () async {
                    if (selected.isEmpty) {
                      await message(context, '尚未选择人员', '至少选择一人后保存。');
                      return;
                    }
                    if (blocked.isNotEmpty) {
                      await message(
                        context,
                        '有人员正在请假',
                        '${blocked.map((l) => widget.store.name(l.personId)).join('、')} '
                            '当天已确认请假，不能登记考勤。请先修改请假状态或时间。',
                      );
                      return;
                    }
                    if (selected.any(
                          (id) => widget.store.record(id, widget.day) != null,
                        ) &&
                        widget.entry == null) {
                      if (!await confirm(
                        context,
                        '覆盖已有登记？',
                        '所选人员中已有当日记录，保存将更新其考勤字段。',
                      )) {
                        return;
                      }
                    }
                    if (!context.mounted) return;
                    setState(() => saving = true);
                    await guarded(context, () async {
                      fields['note'] = note.text;
                      await widget.store.saveEntries(
                        selected.toList(),
                        widget.day,
                        fields,
                      );
                      if (context.mounted) Navigator.pop(context);
                    });
                    if (mounted) setState(() => saving = false);
                  },
            child: Text(saving ? '保存中…' : '保存 ${selected.length} 人登记'),
          ),
        ],
      ),
    );
  }
}

Widget _divider(BuildContext context) => Padding(
  padding: const EdgeInsets.only(left: Gap.md),
  child: Container(height: .5, color: separatorOf(context)),
);

Color _statusColor(BuildContext context, String status) => switch (status) {
  '正常' => AppColors.success.resolveFrom(context),
  '迟到' || '早退' => AppColors.warning.resolveFrom(context),
  '缺勤' => AppColors.danger.resolveFrom(context),
  '请假' => AppColors.leave.resolveFrom(context),
  _ => CupertinoColors.secondaryLabel.resolveFrom(context),
};

class PersonPickerPage extends StatefulWidget {
  const PersonPickerPage({
    super.key,
    required this.store,
    required this.selected,
    required this.day,
  });
  final Workspace store;
  final Set<String> selected;
  final String day;
  @override
  State<PersonPickerPage> createState() => _PersonPickerPageState();
}

class _PersonPickerPageState extends State<PersonPickerPage> {
  late final Set<String> selected = {...widget.selected};
  String query = '', gender = '';
  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final people = widget.store.activePeople
        .where(
          (p) =>
              (gender.isEmpty || p.gender == gender) &&
              p.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final genders = widget.store.activePeople
        .map((p) => p.gender)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    final selectable = people
        .where((p) => !widget.store.onLeave(p.id, widget.day))
        .toList();
    return CupertinoPageScaffold(
      child: Screen(
        title: '选择登记人员',
        children: [
          CupertinoSearchTextField(
            placeholder: '搜索姓名',
            onChanged: (v) => setState(() => query = v),
          ),
          Wrap(
            spacing: 6,
            children: [
              CupertinoButton(
                onPressed: () => setState(() => gender = ''),
                child: Text(gender.isEmpty ? '全部性别 ✓' : '全部性别'),
              ),
              ...genders.map(
                (g) => CupertinoButton(
                  onPressed: () => setState(() => gender = g),
                  child: Text(gender == g ? '$g ✓' : g),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  onPressed: () =>
                      setState(() => selected.addAll(selectable.map((p) => p.id))),
                  child: const Text('全选当前结果'),
                ),
              ),
              Expanded(
                child: CupertinoButton(
                  onPressed: () => setState(
                    () => selected.removeAll(people.map((p) => p.id)),
                  ),
                  child: const Text('清除当前结果'),
                ),
              ),
            ],
          ),
          Text(
            '已选 ${selected.length} 人 · 请假人员当天不可登记',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          ...people.map((p) {
            final leave = widget.store.leaveOf(p.id, widget.day);
            return SettingRow(
              p.name,
              detail: [
                if (leave != null) '请假中 · ${leave.type}',
                if (leave == null && p.gender.isNotEmpty) p.gender,
                if (leave == null && p.employeeId.isNotEmpty) p.employeeId,
              ].join(' · '),
              onTap: leave != null
                  ? () => message(
                      context,
                      '${p.name} 正在请假',
                      '已确认请假的人员当天不可登记考勤。'
                          '如需登记，请先在请假记录中把状态改为已取消或调整时间。',
                    )
                  : () => setState(
                      () => selected.contains(p.id)
                          ? selected.remove(p.id)
                          : selected.add(p.id),
                    ),
              trailing: Icon(
                leave != null
                    ? CupertinoIcons.calendar_badge_minus
                    : (selected.contains(p.id)
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle),
                size: 19,
                color: leave != null
                    ? AppColors.leave.resolveFrom(context)
                    : (selected.contains(p.id)
                          ? CupertinoTheme.of(context).primaryColor
                          : secondary),
              ),
            );
          }),
          PrimaryButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('完成选择'),
          ),
        ],
      ),
    );
  }
}
