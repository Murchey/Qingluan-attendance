import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/ui.dart';
import '../../attendance/presentation/entry_editor.dart';

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
    final id = await choose(context, '选择今日登记人员', {
      for (final p in store.activePeople)
        p.id: '${p.name}${store.record(p.id, day) == null ? '' : ' · 已有记录'}',
    });
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
    var date = today;
    final selected = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => Container(
        height: 330,
        color: CupertinoColors.systemBackground.resolveFrom(c),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('取消'),
                  ),
                  const Text('选择补录日期'),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c, date),
                    child: const Text('确定'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: today,
                  maximumDate: today,
                  onDateTimeChanged: (v) => date = v,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await openEditor(
      context,
      store,
      selected.toIso8601String().substring(0, 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = businessDay();
    final live = store.liveEntries;
    final todayCount = live.where((e) => e.day == day).length;
    final recent = List<Entry>.of(live)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final overview = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本地考勤记录', style: TextStyle(color: secondary, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  '${live.length}',
                  key: const ValueKey('local-record-count'),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('条', style: TextStyle(color: secondary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '保存在本机的有效记录，不含已删除数据',
            style: TextStyle(color: secondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 8,
              runSpacing: 12,
              children: [
                metric(context, '今日记录', '$todayCount 条', c.maxWidth),
                metric(
                  context,
                  '启用人员',
                  '${store.activePeople.length} 人',
                  c.maxWidth,
                ),
                metric(
                  context,
                  '待上传变更',
                  '${store.pendingDays.length} 项',
                  c.maxWidth,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final quick = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '快捷记录',
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth < 280 ? c.maxWidth : (c.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                shortcut(
                  context,
                  width,
                  CupertinoIcons.pencil,
                  '今日登记',
                  '选人后直接记录',
                  () => quickRecord(context),
                ),
                shortcut(
                  context,
                  width,
                  CupertinoIcons.person_2,
                  '批量登记',
                  '一次登记多位人员',
                  () => openEditor(context, store, day),
                ),
                shortcut(
                  context,
                  width,
                  CupertinoIcons.clock,
                  '补录历史',
                  '选择日期补充记录',
                  () => backfill(context),
                ),
                shortcut(
                  context,
                  width,
                  CupertinoIcons.list_bullet,
                  '查看记录',
                  '查询、编辑与导出',
                  onRecords,
                ),
              ],
            );
          },
        ),
      ],
    );
    return Screen(
      title: '今日概览',
      actions: [
        CupertinoButton(
          onPressed: onSettings,
          child: const Icon(CupertinoIcons.gear, semanticLabel: '打开设置'),
        ),
      ],
      children: [
        Text(
          '北京时间 $day · 东八区',
          style: TextStyle(color: secondary, fontSize: 13),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: onSync,
          child: Row(
            children: [
              const Icon(CupertinoIcons.cloud, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store.remoteEntries.isNotEmpty
                      ? '有云端变化待审查'
                      : store.pendingDays.isNotEmpty
                      ? '${store.pendingDays.length} 项本地变更待同步'
                      : '本地模式 · 查看同步状态',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const Icon(CupertinoIcons.chevron_right, size: 14),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 720
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: overview),
                    const SizedBox(width: 24),
                    Expanded(child: quick),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [overview, const SizedBox(height: 24), quick],
                ),
        ),
        const SizedBox(height: 24),
        SectionTitle(
          '最近记录',
          action: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onRecords,
            child: const Text('查看全部'),
          ),
        ),
        if (recent.isEmpty) ...[
          const EmptyState(
            icon: CupertinoIcons.doc_text,
            title: '还没有本地记录',
            message: '使用上方快捷入口开始登记。首次使用请先添加人员。',
          ),
          if (store.activePeople.isEmpty)
            CupertinoButton(onPressed: onSettings, child: const Text('添加人员')),
        ],
        ...recent
            .take(5)
            .map(
              (e) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8, bottom: 6),
                    child: Text(
                      e.day,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
                  EntryTile(
                    store: store,
                    entry: e,
                    onTap: () => openEditor(context, store, e.day, entry: e),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget metric(
    BuildContext context,
    String title,
    String value,
    double available,
  ) => SizedBox(
    width: available < 240 ? available : (available - 16) / 3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    ),
  );
  Widget shortcut(
    BuildContext context,
    double width,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => SizedBox(
    width: width,
    child: GlassCard(
      padding: EdgeInsets.zero,
      child: CupertinoButton(
        padding: const EdgeInsets.all(16),
        onPressed: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
