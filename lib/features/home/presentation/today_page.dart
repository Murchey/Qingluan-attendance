import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/calendar_board.dart';
import '../../../core/widgets/markdown.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/ui.dart';
import '../../attendance/presentation/entry_editor.dart';
import '../../leave/presentation/leave_page.dart';
import '../../notice/presentation/notice_composer.dart';
import '../../notice/presentation/notice_panel.dart';
import '../../stats/presentation/stats_page.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.onSync,
    required this.onSettings,
    required this.onRecords,
  });
  final Workspace store;
  final VoidCallback onSync, onSettings, onRecords;

  Future<void> quickRecord(BuildContext context) async {
    if (store.activePeople.isEmpty) {
      await message(context, '请先添加人员', '在设置 → 人员名单中新增或导入人员后，即可快捷记录。');
      return;
    }
    final day = businessDay();
    final leaves = {for (final l in store.leavesOn(day)) l.personId: l};
    final id = await choose<String>(
      context,
      '选择今日登记人员',
      {for (final p in store.activePeople) p.id: p.name},
      subtitle: '已确认请假的人员当天不可登记',
      fallbackIcon: CupertinoIcons.person,
      disabled: leaves.keys.toSet(),
      details: {
        for (final p in store.activePeople)
          p.id: [
            if (leaves[p.id] != null) '请假中 · ${leaves[p.id]!.type}',
            if (store.record(p.id, day) != null && leaves[p.id] == null)
              '已有记录',
            if (p.employeeId.isNotEmpty) p.employeeId,
          ].join(' · '),
      },
    );
    if (id == null || !context.mounted) return;
    await openEditor(
      context,
      store,
      day,
      entry: store.record(id, day),
      initialPersonId: id,
    );
  }

  Future<void> backfill(BuildContext context) async {
    final today = DateTime.parse(businessDay());
    final marked = store.leaveDaysIn(
      dayKey(DateTime(today.year, today.month - 9, 1)),
      dayKey(today),
    );
    final day = await showCalendarSheet(
      context,
      title: '选择补录日期',
      subtitle: '红色为已有请假日期，请假当天不可登记',
      initialDay: businessDay(),
      maxDay: businessDay(),
      marked: marked,
    );
    if (day == null || !context.mounted) return;
    await openEditor(context, store, day);
  }

  Future<void> openStats(BuildContext context) => Navigator.of(context).push(
    CupertinoPageRoute<void>(builder: (_) => StatsPage(store: store)),
  );

  Future<void> publishNotice(BuildContext context) async {
    final markdown = await openNoticeComposer(context, store);
    if (markdown == null || !context.mounted) return;
    await showAppSheet<void>(
      context,
      (sheetContext) => SheetPanel(
        title: '已加入待上传队列',
        subtitle: '生成 note.md 与 index.json 更新；签名上传接入后其他设备会在打开时收到',
        titleIcon: CupertinoIcons.bell,
        child: MarkdownView(markdown, baseSize: 13.5),
        footer: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: SizedBox(
            height: 52,
            child: Center(child: Text('好', style: AppType.button)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = businessDay();
    final people = store.activePeople;
    final today = store.liveEntries.where((e) => e.day == day).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final registered = today.map((e) => e.personId).toSet();
    final count = people.where((p) => registered.contains(p.id)).length;
    final leaves = store.leavesOn(day);
    final onLeaveIds = leaves.map((l) => l.personId).toSet();
    final expected = people.where((p) => !onLeaveIds.contains(p.id)).length;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final showTodayCard = store.settings['homeCard'] == 'today';
    final latestNotice = store.noticeTitle('admin').isEmpty
        ? store.noticeBody('admin')
        : store.noticeTitle('admin');
    return Screen(
      title: '今日概览',
      actions: [
        GlassIconButton(
          icon: CupertinoIcons.bell,
          label: '通知中心',
          onPressed: () => showNoticeCenterSheet(
            context,
            store,
            onRefresh: () => refreshNotices(context, store, quietWhenIdle: true),
          ),
        ),
      ],
      children: [
        Text(
          '$day · 今日',
          style: AppType.footnoteStyle.copyWith(color: secondary),
        ),
        const SizedBox(height: Gap.sm),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                showTodayCard ? '今日已登记' : '当前同步状态',
                style: AppType.footnoteStyle.copyWith(color: secondary),
              ),
              const SizedBox(height: Gap.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    showTodayCard
                        ? '$count'
                        : (store.pendingDays.isEmpty
                              ? '已同步'
                              : '${store.pendingDays.length}'),
                    key: const ValueKey('today-record-count'),
                    style: AppType.metric,
                  ),
                  if (showTodayCard)
                    Padding(
                      padding: const EdgeInsets.only(left: Gap.xxs),
                      child: Text(
                        ' / $expected 人',
                        style: AppType.calloutStyle.copyWith(color: secondary),
                      ),
                    ),
                ],
              ),
              if (showTodayCard) ...[
                const SizedBox(height: Gap.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: separatorOf(context).withValues(alpha: .9),
                            ),
                          ),
                          SizedBox(
                            width:
                                constraints.maxWidth *
                                (expected == 0 ? 0 : count / expected).clamp(
                                  0.0,
                                  1.0,
                                ),
                            height: 4,
                            child: ColoredBox(
                              color: CupertinoTheme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      !showTodayCard
                          ? (store.pendingDays.isEmpty
                                ? '本地数据没有待上传变更'
                                : '进入同步中心查看待上传项目')
                          : people.isEmpty
                          ? '添加人员后开始今天的登记'
                          : leaves.isEmpty
                          ? (count >= expected
                                ? '今日登记已完成'
                                : '还有 ${expected - count} 人待登记')
                          : (count >= expected
                                ? '今日登记已完成 · ${leaves.length} 人请假'
                                : '还有 ${expected - count} 人待登记 · '
                                      '${leaves.length} 人请假'),
                      style: AppType.rowDetail.copyWith(color: secondary),
                    ),
                  ),
                  if (leaves.isNotEmpty)
                    StatusPill(
                      label: '请假 ${leaves.length}',
                      color: AppColors.leave.resolveFrom(context),
                      icon: CupertinoIcons.calendar_badge_minus,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        PrimaryButton(
          onPressed: () => quickRecord(context),
          child: const Text('今日登记'),
        ),
        const SizedBox(height: Gap.xs),
        Row(
          children: [
            Expanded(
              child: _quickAction(
                context,
                icon: CupertinoIcons.person_2,
                label: '批量登记',
                onTap: () => openEditor(context, store, day),
              ),
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: _quickAction(
                context,
                icon: CupertinoIcons.calendar,
                label: '补录历史',
                onTap: () => backfill(context),
              ),
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: _quickAction(
                context,
                icon: CupertinoIcons.calendar_badge_minus,
                label: '请假记录',
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => LeavePage(store: store),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        SectionTitle(
          '今日记录',
          action: CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xxs),
            onPressed: onRecords,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '全部',
                  style: AppType.footnoteStyle.copyWith(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: Sizes.chevron - 2,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        if (today.isEmpty)
          EmptyState(
            icon: CupertinoIcons.doc_text,
            title: '今天还没有登记',
            message: leaves.isEmpty
                ? '从上方开始记录今天的考勤。'
                : '${leaves.length} 人已确认请假，其余人员可从上方登记。',
            action: people.isEmpty
                ? CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.xs,
                    ),
                    color: AppColors.raised.resolveFrom(context),
                    borderRadius: BorderRadius.circular(Radii.control),
                    onPressed: onSettings,
                    child: Text(
                      '添加人员',
                      style: AppType.button.copyWith(
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  )
                : null,
          ),
        ...today.take(3).map(
          (e) => EntryTile(
            store: store,
            entry: e,
            onTap: () => openEditor(context, store, e.day, entry: e),
          ),
        ),
        const SizedBox(height: Gap.lg),
        SectionTitle('管理'),
        const SizedBox(height: Gap.xs),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingRow(
                '数据统计',
                detail: leaves.isEmpty
                    ? '成员请假状态、今日请假成员与区间统计'
                    : '今日 ${leaves.length} 人请假 · 请假日历与区间统计',
                leading: IconBadge(
                  icon: CupertinoIcons.chart_bar_alt_fill,
                  tint: AppColors.navy.resolveFrom(context),
                ),
                onTap: () => openStats(context),
              ),
              Padding(
                padding: const EdgeInsets.only(left: Gap.md),
                child: Container(height: .5, color: separatorOf(context)),
              ),
              SettingRow(
                '管理员通知',
                detail: latestNotice.isEmpty
                    ? '向共用此软件的管理员发布考勤与调休计划'
                    : '最近：${latestNotice.replaceAll('\n', ' ')}',
                leading: IconBadge(
                  icon: CupertinoIcons.bell,
                  tint: AppColors.warning.resolveFrom(context),
                ),
                onTap: () => publishNotice(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: .6,
      onPressed: onTap,
      child: Container(
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface.resolveFrom(context),
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: separatorOf(context), width: .6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: Sizes.icon - 2, color: secondary),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppType.caption.copyWith(
                color: CupertinoColors.label.resolveFrom(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
