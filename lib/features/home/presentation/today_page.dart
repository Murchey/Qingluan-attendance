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
    final people = store.activePeople;
    final today = store.liveEntries.where((e) => e.day == day).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final registered = today.map((e) => e.personId).toSet();
    final count = people.where((p) => registered.contains(p.id)).length;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final showTodayCard = store.settings['homeCard'] == 'today';
    return Screen(
      title: '今日概览',
      actions: [
        GlassIconButton(
          icon: CupertinoIcons.bell,
          label: '通知',
          onPressed: () async {
            final selected = await choose(
              context,
              store.pendingDays.isEmpty
                  ? '暂无待同步变更'
                  : '${store.pendingDays.length} 项本地变更待同步',
              {'sync': '查看同步状态', 'settings': '打开设置'},
            );
            if (!context.mounted) return;
            if (selected == 'sync') onSync();
            if (selected == 'settings') onSettings();
          },
        ),
      ],
      children: [
        Text(day, style: TextStyle(color: secondary, fontSize: 14)),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                showTodayCard ? '今日已登记' : '当前同步状态',
                style: TextStyle(color: secondary, fontSize: 14),
              ),
              const SizedBox(height: 12),
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
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  if (showTodayCard)
                    Text(
                      ' / ${people.length} 人',
                      style: TextStyle(fontSize: 18, color: secondary),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (showTodayCard)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: CupertinoColors.separator
                                  .resolveFrom(context)
                                  .withValues(alpha: .15),
                            ),
                          ),
                          SizedBox(
                            width:
                                constraints.maxWidth *
                                (people.isEmpty ? 0 : count / people.length),
                            height: 5,
                            child: ColoredBox(
                              color: CupertinoTheme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                !showTodayCard
                    ? (store.pendingDays.isEmpty
                          ? '本地数据没有待上传变更'
                          : '进入同步中心查看待上传项目')
                    : people.isEmpty
                    ? '添加人员后开始今天的登记'
                    : count == people.length
                    ? '今日登记已完成'
                    : '还有 ${people.length - count} 人待登记',
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        CupertinoButton.filled(
          onPressed: () => quickRecord(context),
          child: const Text('今日登记'),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                onPressed: () => openEditor(context, store, day),
                child: const Text('批量登记'),
              ),
            ),
            Expanded(
              child: CupertinoButton(
                onPressed: () => backfill(context),
                child: const Text('补录历史'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionTitle(
          '今日记录',
          action: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onRecords,
            child: const Text('查看全部'),
          ),
        ),
        const SizedBox(height: 10),
        if (today.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.doc_text,
            title: '今天还没有登记',
            message: '从上方开始记录今天的考勤。',
          ),
        if (people.isEmpty)
          CupertinoButton(onPressed: onSettings, child: const Text('添加人员')),
        ...today
            .take(3)
            .map(
              (e) => EntryTile(
                store: store,
                entry: e,
                onTap: () => openEditor(context, store, e.day, entry: e),
              ),
            ),
      ],
    );
  }
}
