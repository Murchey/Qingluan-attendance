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
            if (store.record(p.id, day) != null && leaves[p.id] == null) '已有记录',
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

  Future<void> openStats(BuildContext context) => Navigator.of(
    context,
  ).push(CupertinoPageRoute<void>(builder: (_) => StatsPage(store: store)));

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
    final date = DateTime.parse(day);
    final people = store.activePeople;
    final today = store.liveEntries.where((e) => e.day == day).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final registered = today.map((e) => e.personId).toSet();
    final leaves = store.leavesOn(day);
    final onLeave = leaves.map((l) => l.personId).toSet();
    final expected = people.where((p) => !onLeave.contains(p.id)).length;
    final count = people
        .where((p) => registered.contains(p.id) && !onLeave.contains(p.id))
        .length;
    final remaining = (expected - count).clamp(0, expected);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final accent = AppColors.accent.resolveFrom(context);
    final showSync = store.settings['homeCard'] == 'sync';
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return Screen(
      title: '今日概览',
      actions: [
        GlassIconButton(
          icon: CupertinoIcons.bell,
          label: '通知中心',
          onPressed: () => showNoticeCenterSheet(
            context,
            store,
            onRefresh: () =>
                refreshNotices(context, store, quietWhenIdle: true),
          ),
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Text(
                '${date.month}月${date.day}日  ${weekdays[date.weekday - 1]}',
                style: AppType.footnoteStyle.copyWith(color: secondary),
              ),
              const Spacer(),
              Icon(CupertinoIcons.lock_shield, size: 13, color: secondary),
              const SizedBox(width: 4),
              Text('本地工作区', style: AppType.caption.copyWith(color: secondary)),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showSync ? '待上传变更' : '今日已登记',
                          style: AppType.footnoteStyle.copyWith(
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: 6,
                          children: [
                            Text(
                              showSync
                                  ? '${store.pendingDays.length}'
                                  : '$count',
                              key: const ValueKey('today-record-count'),
                              style: TextStyle(
                                fontSize: 44,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1.5,
                                color: label,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                showSync ? '项' : '/ $expected 人',
                                style: AppType.rowDetail.copyWith(
                                  color: secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 66,
                    height: 66,
                    child: CustomPaint(
                      painter: _ProgressRing(
                        progress: expected == 0 ? 0 : count / expected,
                        color: accent,
                        track: AppColors.raised.resolveFrom(context),
                      ),
                      child: Center(
                        child: Icon(
                          expected > 0 && count >= expected
                              ? CupertinoIcons.checkmark_alt
                              : CupertinoIcons.calendar,
                          size: 25,
                          color: secondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _metric(context, '在册成员', '${people.length}'),
                  _metricDivider(context),
                  _metric(
                    context,
                    '今日请假',
                    '${onLeave.length}',
                    color: onLeave.isEmpty
                        ? null
                        : AppColors.leave.resolveFrom(context),
                  ),
                  _metricDivider(context),
                  _metric(context, '待登记', '$remaining'),
                ],
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                onPressed: () => quickRecord(context),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.add,
                      size: 18,
                      color: CupertinoColors.white,
                    ),
                    SizedBox(width: 8),
                    Text('今日登记'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
            const SizedBox(width: 10),
            Expanded(
              child: _quickAction(
                context,
                icon: CupertinoIcons.calendar,
                label: '补录历史',
                onTap: () => backfill(context),
              ),
            ),
            const SizedBox(width: 10),
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
        const SizedBox(height: 26),
        SectionTitle(
          '今日记录',
          action: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 32),
            onPressed: onRecords,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('全部记录', style: AppType.caption.copyWith(color: secondary)),
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_right, size: 11, color: secondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (today.isEmpty)
          GlassCard(
            child: Row(
              children: [
                IconBadge(
                  icon: CupertinoIcons.doc_text,
                  tint: secondary,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('今天还没有登记', style: AppType.cell),
                      const SizedBox(height: 4),
                      Text(
                        people.isEmpty ? '先添加人员，开始管理考勤' : '登记后，最新考勤会显示在这里',
                        style: AppType.caption.copyWith(color: secondary),
                      ),
                    ],
                  ),
                ),
                if (people.isEmpty)
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 8),
                    onPressed: onSettings,
                    child: Text(
                      '添加人员',
                      style: AppType.caption.copyWith(color: accent),
                    ),
                  ),
              ],
            ),
          ),
        ...today
            .take(3)
            .map(
              (e) => EntryTile(
                store: store,
                entry: e,
                onTap: () => openEditor(context, store, e.day, entry: e),
              ),
            ),
        const SizedBox(height: 26),
        const SectionTitle('管理工具'),
        const SizedBox(height: 12),
        SettingsGroup(
          children: [
            SettingRow(
              '数据统计',
              detail: '请假日历、成员状态与考勤分析',
              leading: IconBadge(
                icon: CupertinoIcons.chart_bar,
                tint: secondary,
                size: 36,
              ),
              onTap: () => openStats(context),
            ),
            SettingRow(
              '管理员通知',
              detail: '发布考勤情况与调休计划',
              leading: IconBadge(
                icon: CupertinoIcons.bubble_left,
                tint: secondary,
                size: 36,
              ),
              onTap: () => publishNotice(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 8),
          onPressed: onSync,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.cloud, size: 14, color: secondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  store.pendingDays.isNotEmpty
                      ? '${store.pendingDays.length} 项变更待上传 · 查看同步状态'
                      : '数据保存在本机 · 查看同步状态',
                  style: AppType.caption.copyWith(color: secondary),
                ),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_right, size: 10, color: secondary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(
    BuildContext context,
    String title,
    String value, {
    Color? color,
  }) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            height: 1.1,
            color: color ?? CupertinoColors.label.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: AppType.caption.copyWith(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    ),
  );

  Widget _metricDivider(BuildContext context) =>
      Container(width: .5, height: 28, color: separatorOf(context));

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => CupertinoButton(
    padding: EdgeInsets.zero,
    pressedOpacity: .65,
    onPressed: onTap,
    child: GlassCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 4),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Icon(
              icon,
              size: 23,
              color: CupertinoColors.label.resolveFrom(context),
            ),
            const SizedBox(height: 9),
            Text(
              label,
              style: AppType.caption.copyWith(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProgressRing extends CustomPainter {
  const _ProgressRing({
    required this.progress,
    required this.color,
    required this.track,
  });
  final double progress;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 6.283185307, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -1.570796327,
        6.283185307 * progress.clamp(0, 1),
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRing oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}
