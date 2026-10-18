import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/calendar_board.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/ui.dart';
import '../../leave/presentation/leave_editor.dart';
import '../domain/attendance_score.dart';
import 'score_rules_page.dart';

const statFilters = ['本周', '本月', '本年', '自定义'];

/// Data statistics: leave state per member, today's leaves, range counts and a
/// calendar board with leave days marked in red.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.store});
  final Workspace store;
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String filter = '本月';
  String? customFrom, customTo;
  late DateTime anchor = DateTime.parse(businessDay());

  Workspace get store => widget.store;

  (String, String) get range {
    final today = DateTime.parse(businessDay());
    switch (filter) {
      case '本周':
        final monday = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1),
        );
        return (
          dayKey(monday),
          dayKey(DateTime(monday.year, monday.month, monday.day + 6)),
        );
      case '本年':
        return ('${today.year}-01-01', '${today.year}-12-31');
      case '自定义':
        return (
          customFrom ??
              dayKey(DateTime(today.year, today.month, today.day - 29)),
          customTo ?? dayKey(today),
        );
      default:
        return (
          dayKey(DateTime(today.year, today.month, 1)),
          dayKey(DateTime(today.year, today.month + 1, 0)),
        );
    }
  }

  Future<void> pickCustomRange() async {
    final picked = await showRangeSheet(
      context,
      from: customFrom,
      to: customTo,
      title: '自定义统计时间段',
    );
    if (picked == null || !mounted) return;
    setState(() {
      customFrom = picked.$1;
      customTo = picked.$2;
      filter = '自定义';
      anchor = DateTime.parse(picked.$1);
    });
  }

  Future<void> showDayLeaves(String day) async {
    final leaves = store.leavesOn(day);
    await showAppSheet<void>(
      context,
      (sheetContext) => SheetPanel(
        title: '$day 请假情况',
        subtitle: leaves.isEmpty ? '当天没有已确认请假' : '${leaves.length} 人请假',
        titleIcon: CupertinoIcons.calendar,
        child: leaves.isEmpty
            ? Text(
                '没有人请假。可点击右下角新增请假。',
                style: TextStyle(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              )
            : Column(
                children: [
                  for (final leave in leaves)
                    SettingRow(
                      '${store.name(leave.personId)} · ${leave.type}',
                      detail:
                          '${leave.startDay} → ${leave.endDay} · '
                          '${leave.status}',
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await openLeaveEditor(context, store, leave: leave);
                      },
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> showScoreDetail(PersonScore score, String from, String to) async {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final deductionColor = AppColors.leave.resolveFrom(context);
    await showAppSheet<void>(
      context,
      (sheetContext) => SheetPanel(
        title: '${score.name} · 考勤分',
        subtitle: '$from 至 $to · 基准分 ${scoreText(score.base)}',
        titleIcon: CupertinoIcons.chart_bar_alt_fill,
        child: Column(
          children: [
            for (final line in score.lines)
              SettingRow(
                '${line.label} ${line.count}${line.unit}',
                detail: line.points > 0
                    ? '每 1 ${line.unit}扣 ${scoreText(line.points)} 分'
                    : '不扣分',
                trailing: Text(
                  line.deduction > 0 ? '-${scoreText(line.deduction)}' : '0',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: line.deduction > 0 ? deductionColor : secondary,
                  ),
                ),
              ),
            if (score.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.md),
                child: Text('该区间没有需要扣分的场景。', style: TextStyle(color: secondary)),
              ),
            const SizedBox(height: Gap.xs),
            SettingRow(
              '扣分合计',
              detail: score.clean ? '没有扣分' : '按当前默认扣分值计算',
              trailing: Text(
                '-${scoreText(score.deduction)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: score.clean ? secondary : deductionColor,
                ),
              ),
            ),
            SettingRow(
              '考勤分',
              detail: '基准分 ${scoreText(score.base)} · 最低 0 分',
              trailing: Text(
                scoreText(score.score),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _scoreColor(context, score),
                ),
              ),
            ),
          ],
        ),
        footer: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(sheetContext).pop();
            openScoreRules(context, store);
          },
          child: SizedBox(
            height: 52,
            child: Center(child: Text('调整扣分规则', style: AppType.button)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final (from, to) = range;
      final today = businessDay();
      final todayLeaves = store.leavesOn(today);
      final monthStart = dayKey(DateTime(anchor.year, anchor.month, 1));
      final monthEnd = dayKey(DateTime(anchor.year, anchor.month + 1, 0));
      final marked = store.leaveDaysIn(monthStart, monthEnd);
      final byType = store.leaveDaysByType(from, to);
      final totalDays = byType.values.fold<int>(0, (a, b) => a + b);
      final rules = scoreRulesOf(store);
      final scores = attendanceScores(store, from, to, rules: rules);
      final average = scores.isEmpty
          ? rules.base
          : scores.fold<double>(0, (sum, item) => sum + item.score) /
                scores.length;
      final lowest = scores.isEmpty ? null : scores.first;
      return CupertinoPageScaffold(
        child: Screen(
          title: '数据统计',
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
                    '${todayLeaves.length}',
                    accent: AppColors.leave.resolveFrom(context),
                  ),
                  _divider(context),
                  _metric(
                    context,
                    '$filter请假人数',
                    '${store.leavePeopleIn(from, to)}',
                  ),
                  _divider(context),
                  _metric(
                    context,
                    '$filter请假天数',
                    '${store.leaveDaysCountIn(from, to)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$from 至 $to',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedControl<String>(
              values: statFilters,
              labels: statFilters,
              value: filter,
              onChanged: (value) {
                if (value == '自定义') {
                  pickCustomRange();
                } else {
                  setState(() => filter = value);
                }
              },
            ),
            const SizedBox(height: 16),
            GlassCard(
              child: CalendarBoard(
                key: ValueKey(monthStart),
                initialMonth: anchor,
                marked: marked,
                markedLegend: '红色为请假日期',
                onMonthChanged: (month) => setState(() => anchor = month),
                onDayTap: showDayLeaves,
              ),
            ),
            const SizedBox(height: 20),
            SectionTitle(
              '今日请假成员',
              action: Text(
                '${todayLeaves.length} 人',
                style: TextStyle(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (todayLeaves.isEmpty)
              const EmptyState(
                icon: CupertinoIcons.checkmark_seal,
                title: '今天无人请假',
                message: '已确认的请假会出现在这里，并在日历上标红。',
              ),
            for (final leave in todayLeaves)
              GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: SettingRow(
                  '${store.name(leave.personId)} · ${leave.type}',
                  detail:
                      '${leave.startDay} → ${leave.endDay} · '
                      '${leave.reason.isEmpty ? '未填写原因' : leave.reason}',
                  onTap: () => openLeaveEditor(context, store, leave: leave),
                  trailing: StatusPill(
                    label: '请假',
                    color: AppColors.leave.resolveFrom(context),
                    icon: CupertinoIcons.calendar_badge_minus,
                  ),
                ),
              ),
            if (totalDays > 0) ...[
              const SizedBox(height: 22),
              SectionTitle('$filter请假类型分布'),
              const SizedBox(height: 10),
              GlassCard(
                child: Column(
                  children: [
                    for (final entry in (byType.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value))))
                      _typeBar(
                        context,
                        entry.key,
                        entry.value,
                        totalDays,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            SectionTitle(
              '考勤分统计',
              action: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => openScoreRules(context, store),
                child: Text(
                  '扣分规则',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.navy.resolveFrom(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              child: Row(
                children: [
                  _metric(
                    context,
                    '平均考勤分',
                    scores.isEmpty ? '—' : scoreText(average),
                  ),
                  _divider(context),
                  _metric(
                    context,
                    '最低分',
                    lowest == null ? '—' : scoreText(lowest.score),
                    accent: lowest == null
                        ? null
                        : _scoreColor(context, lowest),
                  ),
                  _divider(context),
                  _metric(context, '计分人数', '${scores.length}'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$from 至 $to · 基准分 ${scoreText(rules.base)}\n'
              '仅统计区间内有考勤登记或已确认请假的成员；'
              '按请假天数与迟到、早退、缺勤次数扣分',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 10),
            if (scores.isEmpty)
              const EmptyState(
                icon: CupertinoIcons.chart_bar_alt_fill,
                title: '区间内还没有可计分记录',
                message: '登记考勤或确认请假后，会按默认扣分值计算每人的考勤分。',
              ),
            for (final score in scores)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: SettingRow(
                    score.name,
                    detail: score.summary,
                    trailing: Text(
                      scoreText(score.score),
                      key: ValueKey('score-${score.personId}'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: _scoreColor(context, score),
                      ),
                    ),
                    onTap: () => showScoreDetail(score, from, to),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            PrimaryButton(
              onPressed: () => openLeaveEditor(context, store),
              child: const Text('新增请假记录'),
            ),
            const SizedBox(height: 8),
            Text(
              '请假以红色标记在日历上。已确认的请假当天不可登记考勤，'
              '可在请假记录中修改状态或时间。',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      );
    },
  );

  Color _scoreColor(BuildContext context, PersonScore score) {
    if (score.clean) return AppColors.success.resolveFrom(context);
    if (score.score >= score.base * .9) {
      return AppColors.warning.resolveFrom(context);
    }
    return AppColors.leave.resolveFrom(context);
  }

  Widget _divider(BuildContext context) => Container(
    width: .6,
    height: 38,
    color: CupertinoColors.separator.resolveFrom(context),
  );

  Widget _metric(
    BuildContext context,
    String title,
    String value, {
    Color? accent,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: accent ?? CupertinoColors.label.resolveFrom(context),
            ),
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

  Widget _typeBar(BuildContext context, String type, int days, int total) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final ratio = total == 0 ? 0.0 : days / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(type, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: CupertinoColors.separator
                            .resolveFrom(context)
                            .withValues(alpha: .25),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio.clamp(.04, 1),
                      child: ColoredBox(
                        color: AppColors.leave.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: Text(
              '$days 天',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
