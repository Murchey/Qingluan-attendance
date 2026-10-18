import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/calendar_board.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/widgets/app_widgets.dart';

const leaveTypeIcons = {
  '事假': CupertinoIcons.briefcase,
  '病假': CupertinoIcons.heart,
  '年假': CupertinoIcons.sun_max,
  '调休': CupertinoIcons.arrow_2_circlepath,
  '婚假': CupertinoIcons.heart_fill,
  '产假': CupertinoIcons.person_2,
  '其他': CupertinoIcons.ellipsis_circle,
};

const leaveStatusIcons = {
  '已确认': CupertinoIcons.checkmark_circle_fill,
  '待确认': CupertinoIcons.clock,
  '已取消': CupertinoIcons.xmark_circle,
};

Color leaveStatusColor(BuildContext context, String status) => switch (status) {
  '已确认' => AppColors.leave.resolveFrom(context),
  '待确认' => AppColors.warning.resolveFrom(context),
  _ => CupertinoColors.secondaryLabel.resolveFrom(context),
};

Future<void> openLeaveEditor(
  BuildContext context,
  Workspace store, {
  Leave? leave,
  String? personId,
  String? day,
}) async {
  if (store.identity.isEmpty) {
    final name = await input(context, '请先填写本地显示名');
    if (name == null || name.isEmpty) return;
    await store.setIdentity(name);
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      builder: (_) => LeaveEditorPage(
        store: store,
        leave: leave,
        personId: personId,
        day: day,
      ),
    ),
  );
}

class LeaveEditorPage extends StatefulWidget {
  const LeaveEditorPage({
    super.key,
    required this.store,
    this.leave,
    this.personId,
    this.day,
  });
  final Workspace store;
  final Leave? leave;
  final String? personId;
  final String? day;
  @override
  State<LeaveEditorPage> createState() => _LeaveEditorPageState();
}

class _LeaveEditorPageState extends State<LeaveEditorPage> {
  late String personId;
  late String startDay;
  late String endDay;
  late String type;
  late String status;
  late final TextEditingController reason;
  bool saving = false;

  Workspace get store => widget.store;

  @override
  void initState() {
    super.initState();
    final today = businessDay();
    final leave = widget.leave;
    personId = leave?.personId ?? widget.personId ?? '';
    startDay = leave?.startDay ?? widget.day ?? today;
    endDay = leave?.endDay ?? widget.day ?? today;
    type = leave?.type ?? '事假';
    status = leave?.status ?? '已确认';
    reason = TextEditingController(text: leave?.reason ?? '');
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  int get dayCount {
    final a = DateTime.tryParse(startDay);
    final b = DateTime.tryParse(endDay);
    if (a == null || b == null || b.isBefore(a)) return 0;
    return b.difference(a).inDays + 1;
  }

  Future<void> pickPerson() async {
    if (store.visiblePeople.isEmpty) {
      await message(context, '还没有人员', '请先在设置 → 人员名单中新增或导入人员。');
      return;
    }
    final picked = await choose<String>(
      context,
      '请假人员',
      {for (final p in store.visiblePeople) p.id: p.name},
      subtitle: '已确认请假的人员当天不可登记考勤',
      details: {
        for (final p in store.visiblePeople)
          p.id: [
            if (p.employeeId.isNotEmpty) p.employeeId,
            if (p.gender.isNotEmpty) p.gender,
            if (!p.active) '已停用',
          ].join(' · '),
      },
      fallbackIcon: CupertinoIcons.person,
      selected: personId.isEmpty ? null : {personId},
    );
    if (picked != null && mounted) setState(() => personId = picked);
  }

  Future<void> pickDate({required bool isStart}) async {
    final anchor = DateTime.parse(isStart ? startDay : endDay);
    final picked = await showCalendarSheet(
      context,
      title: isStart ? '请假开始日期' : '请假结束日期',
      subtitle: '红色为已有请假日期',
      initialDay: isStart ? startDay : endDay,
      minDay: isStart ? null : startDay,
      maxDay: isStart ? endDay : null,
      marked: store.leaveDaysIn(
        dayKey(DateTime(anchor.year, anchor.month - 3, 1)),
        dayKey(DateTime(anchor.year, anchor.month + 3, 0)),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          startDay = picked;
          if (endDay.compareTo(startDay) < 0) endDay = startDay;
        } else {
          endDay = picked;
        }
      });
    }
  }

  Future<void> save() async {
    if (personId.isEmpty) {
      await message(context, '未选择人员', '请选择请假人员后保存。');
      return;
    }
    setState(() => saving = true);
    await guarded(context, () async {
      await store.saveLeave(
        leave: widget.leave,
        personId: personId,
        startDay: startDay,
        endDay: endDay,
        type: type,
        status: status,
        reason: reason.text,
      );
      if (mounted) Navigator.of(context).pop();
    });
    if (mounted) setState(() => saving = false);
  }

  Future<void> remove() async {
    final leave = widget.leave;
    if (leave == null) return;
    if (!await confirm(
      context,
      '删除这条请假记录？',
      '删除后会保留删除标记与审计历史；当天考勤重新可用。',
    )) {
      return;
    }
    if (!mounted) return;
    await guarded(context, () async {
      await store.deleteLeave(leave);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final name = personId.isEmpty ? '未选择' : store.name(personId);
    return CupertinoPageScaffold(
      child: Screen(
        title: widget.leave == null ? '新增请假' : '编辑请假',
        children: [
          GlassCard(
            child: Column(
              children: [
                SettingRow(
                  '请假人员',
                  detail: name,
                  onTap: pickPerson,
                  trailing: Icon(
                    CupertinoIcons.person,
                    size: 16,
                    color: secondary,
                  ),
                ),
                SettingRow(
                  '开始日期',
                  detail: startDay,
                  onTap: () => pickDate(isStart: true),
                ),
                SettingRow(
                  '结束日期',
                  detail: endDay,
                  onTap: () => pickDate(isStart: false),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                  child: Row(
                    children: [
                      Text(
                        '共 $dayCount 天',
                        style: TextStyle(fontSize: 12.5, color: secondary),
                      ),
                      const Spacer(),
                      Text(
                        status == '已确认' ? '当天考勤不可登记' : '不占用考勤登记',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: leaveStatusColor(context, status),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              children: [
                SettingRow(
                  '请假类型',
                  detail: type,
                  onTap: () async {
                    final picked = await choose<String>(
                      context,
                      '请假类型',
                      {for (final t in leaveTypes) t: t},
                      icons: leaveTypeIcons,
                      selected: {type},
                    );
                    if (picked != null && mounted) setState(() => type = picked);
                  },
                  trailing: Icon(
                    leaveTypeIcons[type],
                    size: 16,
                    color: secondary,
                  ),
                ),
                SettingRow(
                  '状态',
                  detail: status,
                  onTap: () async {
                    final picked = await choose<String>(
                      context,
                      '请假状态',
                      {for (final s in leaveStatuses) s: s},
                      icons: leaveStatusIcons,
                      details: const {
                        '已确认': '该人员当天考勤登记不可用',
                        '待确认': '保留记录，不影响考勤登记',
                        '已取消': '保留记录，不影响考勤登记',
                      },
                      selected: {status},
                    );
                    if (picked != null && mounted) {
                      setState(() => status = picked);
                    }
                  },
                  trailing: StatusPill(
                    label: status,
                    color: leaveStatusColor(context, status),
                    icon: leaveStatusIcons[status]!,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CupertinoTextField(
            controller: reason,
            placeholder: '请假原因（选填）',
            minLines: 2,
            maxLines: 4,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface.resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '保存中…' : '保存请假'),
          ),
          if (widget.leave != null) ...[
            const SizedBox(height: 6),
            CupertinoButton(
              onPressed: remove,
              child: const Text(
                '删除请假记录',
                style: TextStyle(color: CupertinoColors.destructiveRed),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '修改历史',
              style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
            ),
            const SizedBox(height: 6),
            ...widget.leave!.history.reversed.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(CupertinoIcons.time, size: 14, color: secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(fontSize: 11.5, color: secondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '已确认的请假区间内，该人员当天不可登记考勤；'
            '如需恢复登记，请把状态改为已取消或调整请假时间。',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
  }
}
