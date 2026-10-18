import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/calendar_board.dart';
import '../../../core/widgets/ui.dart';
import 'leave_editor.dart';

class LeavePage extends StatefulWidget {
  const LeavePage({super.key, required this.store});
  final Workspace store;
  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  String status = '';
  Workspace get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final today = businessDay();
    final anchor = DateTime.parse(today);
    final monthFrom = dayKey(DateTime(anchor.year, anchor.month, 1));
    final monthTo = dayKey(DateTime(anchor.year, anchor.month + 1, 0));
    final rows = store.liveLeaves
        .where((l) => status.isEmpty || l.status == status)
        .toList()
      ..sort((a, b) => b.startDay.compareTo(a.startDay));

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => CupertinoPageScaffold(
        child: Screen(
          title: '请假记录',
          actions: [
            GlassIconButton(
              icon: CupertinoIcons.add,
              label: '新增请假',
              onPressed: () => openLeaveEditor(context, store),
            ),
          ],
          children: [
            GlassCard(
              child: Row(
                children: [
                  _metric(
                    context,
                    '今日请假',
                    '${store.leavesOn(today).length}',
                  ),
                  Container(
                    width: .6,
                    height: 38,
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  _metric(
                    context,
                    '本月请假人数',
                    '${store.leavePeopleIn(monthFrom, monthTo)}',
                  ),
                  Container(
                    width: .6,
                    height: 38,
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  _metric(
                    context,
                    '本月请假天数',
                    '${store.leaveDaysCountIn(monthFrom, monthTo)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SegmentedControl<String>(
              values: const ['', '已确认', '待确认', '已取消'],
              labels: const ['全部', '已确认', '待确认', '已取消'],
              value: status,
              onChanged: (value) => setState(() => status = value),
            ),            const SizedBox(height: 16),
            if (rows.isEmpty)
              const EmptyState(
                icon: CupertinoIcons.calendar_badge_minus,
                title: '还没有请假记录',
                message: '为请假的同事登记区间后，当天考勤会默认不可登记。',
              ),
            for (final leave in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: SettingRow(
                    '${store.name(leave.personId)} · ${leave.type}',
                    detail:
                        '${leave.startDay} → ${leave.endDay} · ${leave.dayCount} 天'
                        '${leave.reason.isEmpty ? '' : '\n${leave.reason}'}',
                    onTap: () => openLeaveEditor(context, store, leave: leave),
                    trailing: StatusPill(
                      label: leave.status,
                      color: leaveStatusColor(context, leave.status),
                      icon: leaveStatusIcons[leave.status] ?? CupertinoIcons.circle,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              '已确认请假的人员当天考勤不可登记；只能修改请假状态、时间或取消。'
              '待确认与已取消不占用考勤登记。',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String title, String value) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    ),
  );
}
