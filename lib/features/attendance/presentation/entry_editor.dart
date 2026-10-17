import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/widgets/ui.dart';

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
    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (c) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(c),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消'),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('确定'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: value,
                  onDateTimeChanged: (v) => value = v,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true) {
      setState(
        () => fields[key] =
            '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Screen(
      title: widget.day,
      children: [
        const Text('选择人员（可多选）'),
        if (widget.store.activePeople.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('请先在设置 → 人员名单中新增或导入人员。'),
          ),
        ...widget.store.activePeople.map(
          (p) => SettingRow(
            p.name,
            onTap: () => setState(
              () => selected.contains(p.id)
                  ? selected.remove(p.id)
                  : selected.add(p.id),
            ),
            trailing: Icon(
              selected.contains(p.id)
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
            ),
          ),
        ),
        SettingRow(
          '签到时间',
          detail: fields['in']!.isEmpty ? '未填写' : fields['in']!,
          onTap: () => time('in'),
        ),
        SettingRow(
          '签退时间',
          detail: fields['out']!.isEmpty ? '未填写' : fields['out']!,
          onTap: () => time('out'),
        ),
        CupertinoButton(
          onPressed: () => setState(() {
            fields['in'] = '';
            fields['out'] = '';
          }),
          child: const Text('清空签到 / 签退'),
        ),
        SettingRow(
          '状态',
          detail: fields['status']!,
          onTap: () async {
            final s = await choose(context, '考勤状态', {
              for (final s in statuses) s: s,
            });
            if (s != null) setState(() => fields['status'] = s);
          },
        ),
        CupertinoTextField(
          controller: note,
          placeholder: '备注（选填）',
          maxLines: 3,
          padding: const EdgeInsets.all(14),
        ),
        const SizedBox(height: 20),
        CupertinoButton.filled(
          onPressed: saving
              ? null
              : () async {
                  if (selected.isEmpty) {
                    await message(context, '尚未选择人员', '至少选择一人后保存。');
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
