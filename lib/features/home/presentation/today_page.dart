import 'package:flutter/cupertino.dart';

import '../../../core/data/workspace.dart';
import '../../../core/sync/sync_service.dart';
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

/// Home becomes the day's roster: one tap books a person at the current time,
/// three keys cover the common batch cases, and the editor is demoted to a
/// long-press path for exceptions.
class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.onSync,
    required this.onSettings,
    required this.onRecords,
  });
  final Workspace store;
  final VoidCallback onSync, onSettings, onRecords;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Workspace get store => widget.store;

  /// Snapshot for the last batch action so it can be undone in one tap.
  Map<String, Map<String, String>?>? undoSnapshot;
  String? undoLabel;
  bool busy = false;

  String get day => businessDay();

  Future<void> backfill(BuildContext context) async {
    final today = DateTime.parse(day);
    final marked = store.leaveDaysIn(
      dayKey(DateTime(today.year, today.month - 9, 1)),
      dayKey(today),
    );
    final chosen = await showCalendarSheet(
      context,
      title: '选择补录日期',
      subtitle: '红色为已有请假日期，请假当天不可登记',
      initialDay: day,
      maxDay: day,
      marked: marked,
    );
    if (chosen == null || !context.mounted) return;
    await openEditor(context, store, chosen);
  }

  Future<void> openStats(BuildContext context) => Navigator.of(
    context,
  ).push(CupertinoPageRoute<void>(builder: (_) => StatsPage(store: store)));

  Future<void> openLeaves() => Navigator.of(
    context,
  ).push(CupertinoPageRoute<void>(builder: (_) => LeavePage(store: store)));

  Future<void> publishNotice(BuildContext context) async {
    final markdown = await openNoticeComposer(context, store);
    if (markdown == null || !context.mounted) return;
    await showAppSheet<void>(
      context,
      (sheetContext) => SheetPanel(
        title: '已加入待上传队列',
        subtitle: '生成 note.md 与 index.json 更新；同步成功后其他设备会在打开时收到',
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

  Future<bool> _needIdentity() async {
    if (store.identity.trim().isNotEmpty) return true;
    await message(context, '先填本地显示名', '登记会记下署名。设置 → 本地身份 → 显示名，填完就能一键登记。');
    return false;
  }

  /// One tap: check in, or check out when the row already has a check-in.
  Future<void> _tapPerson(Person person) async {
    if (busy) return;
    if (!await _needIdentity()) return;
    if (!mounted) return;
    final current = store.record(person.id, day);
    setState(() => busy = true);
    try {
      if (current == null) {
        await store.tapCheckIn(person.id, day);
      } else if ((current.fields['out'] ?? '').isEmpty) {
        await store.tapCheckOut(person.id, day);
      } else {
        await openEditor(
          context,
          store,
          day,
          entry: current,
          initialPersonId: person.id,
        );
      }
    } on Object catch (e) {
      if (mounted) await message(context, '未能登记', '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _mark(Person person, String status) async {
    if (!await _needIdentity()) return;
    if (!mounted) return;
    final before = store.record(person.id, day);
    setState(() {
      undoSnapshot = {
        person.id: before == null ? null : Map.of(before.fields),
      };
      undoLabel = '${person.name} · $status';
    });
    try {
      // 缺勤 means no attendance happened: drop the times instead of keeping a
      // check-in that contradicts the status.
      await store.saveEntries([person.id], day, {
        if (status != '缺勤') ...?before?.fields,
        'status': status,
      });
    } on Object catch (e) {
      if (mounted) await message(context, '未能保存', '$e');
    }
  }

  /// Books everyone without a record as a normal day at the shift start.
  Future<void> _allNormal() async {
    if (!await _needIdentity()) return;
    if (!mounted) return;
    final pending = _unregistered();
    if (pending.isEmpty) {
      await message(context, '没有待登记的人', '今天的名单已经全部登记完成。');
      return;
    }
    final confirmIt = await confirm(
      context,
      '把 ${pending.length} 人登记为正常？',
      '签到时间统一记为 ${store.shift.start}（班次上班时间），之后可以逐个调整。',
    );
    if (!confirmIt) return;
    setState(() {
      undoSnapshot = {
        for (final p in pending) p.id: null,
      };
      undoLabel = '全员正常 · ${pending.length} 人';
    });
    try {
      await store.saveEntries(pending.map((p) => p.id).toList(), day, {
        'in': store.shift.start,
        'status': '正常',
      });
    } on Object catch (e) {
      if (mounted) await message(context, '未能批量登记', '$e');
    }
  }

  /// Closes the day: everyone still unregistered becomes 缺勤.
  Future<void> _closeDay() async {
    if (!await _needIdentity()) return;
    if (!mounted) return;
    final pending = _unregistered();
    if (pending.isEmpty) {
      await message(context, '今天已收尾', '所有人都已有记录，不需要再标记缺勤。');
      return;
    }
    final confirmIt = await confirm(
      context,
      '把 ${pending.length} 人标记为缺勤？',
      '结束今天后，未登记的人按缺勤计入统计。仍可逐个修改。',
    );
    if (!confirmIt) return;
    setState(() {
      undoSnapshot = {
        for (final p in pending) p.id: null,
      };
      undoLabel = '结束今天 · ${pending.length} 人缺勤';
    });
    try {
      await store.saveEntries(pending.map((p) => p.id).toList(), day, {
        'status': '缺勤',
      });
    } on Object catch (e) {
      if (mounted) await message(context, '未能收尾', '$e');
    }
  }

  Future<void> _undo() async {
    final snapshot = undoSnapshot;
    if (snapshot == null) return;
    setState(() {
      undoSnapshot = null;
      undoLabel = null;
    });
    try {
      await store.restoreEntries(day, snapshot);
    } on Object catch (e) {
      if (mounted) await message(context, '撤销失败', '$e');
    }
  }

  List<Person> _unregistered() {
    final leaves = store.leavesOn(day).map((l) => l.personId).toSet();
    return store.activePeople
        .where((p) => !leaves.contains(p.id) && store.record(p.id, day) == null)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(day);
    final people = store.activePeople;
    final leaves = {for (final l in store.leavesOn(day)) l.personId: l};
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final registered = people
        .where((p) => store.record(p.id, day) != null && !leaves.containsKey(p.id))
        .length;
    final expected = people.where((p) => !leaves.containsKey(p.id)).length;

    return Screen(
      title: '今日名单',
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
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                '${date.month}月${date.day}日  ${weekdays[date.weekday - 1]}',
                style: AppType.footnoteStyle.copyWith(color: secondary),
              ),
              const Spacer(),
              Text(
                '已登记 $registered/$expected · 请假 ${leaves.length} · 待登记 ${expected - registered}',
                style: AppType.caption.copyWith(color: secondary),
              ),
            ],
          ),
        ),
        if (people.isEmpty)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('还没有人员', style: AppType.sectionTitle),
                const SizedBox(height: 6),
                Text(
                  '先导入名单，之后这里就是每天的登记台：点一下记签到，再点一下记签退。',
                  style: AppType.caption.copyWith(color: secondary),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  onPressed: widget.onSettings,
                  child: const Text('去添加人员'),
                ),
              ],
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _keyButton(
                  label: '全员正常',
                  icon: CupertinoIcons.checkmark_circle_fill,
                  primary: true,
                  onTap: busy ? null : _allNormal,
                ),
              ),
              const SizedBox(width: Gap.xxs),
              Expanded(
                child: _keyButton(
                  label: '结束今天',
                  icon: CupertinoIcons.flag,
                  onTap: busy ? null : _closeDay,
                ),
              ),
              const SizedBox(width: Gap.xxs),
              Expanded(
                child: _keyButton(
                  label: '请假',
                  icon: CupertinoIcons.calendar_badge_minus,
                  onTap: openLeaves,
                ),
              ),
            ],
          ),
          if (undoSnapshot != null) ...[
            const SizedBox(height: Gap.xs),
            _UndoBar(label: undoLabel ?? '', onUndo: _undo),
          ],
          const SizedBox(height: Gap.md),
          for (final person in _orderedPeople(people, leaves))
            _RosterRow(
              store: store,
              day: day,
              person: person,
              leave: leaves[person.id],
              onTap: () => _tapPerson(person),
              onLongPress: () async {
                final current = store.record(person.id, day);
                await openEditor(
                  context,
                  store,
                  day,
                  entry: current,
                  initialPersonId: person.id,
                );
              },
              onAbsent: () => _mark(person, '缺勤'),
              onLeaveTap: openLeaves,
            ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              _textAction(
                context,
                '补录历史',
                () => backfill(context),
              ),
              const SizedBox(width: Gap.sm),
              _textAction(context, '数据统计', () => openStats(context)),
              const SizedBox(width: Gap.sm),
              _textAction(context, '管理员通知', () => publishNotice(context)),
            ],
          ),
          const SizedBox(height: Gap.md),
          _syncStrip(context),
        ],
      ],
    );
  }

  /// Unregistered people first, then by the order they were added.
  List<Person> _orderedPeople(List<Person> people, Map<String, Leave> leaves) {
    final list = List<Person>.of(people);
    int rank(Person p) {
      if (leaves.containsKey(p.id)) return 2;
      if (store.record(p.id, day) != null) return 1;
      return 0;
    }

    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : people.indexOf(a).compareTo(people.indexOf(b));
    });
    return list;
  }

  Widget _keyButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool primary = false,
  }) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        color: primary
            ? AppColors.navy
            : AppColors.raised.resolveFrom(context),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: primary
                ? CupertinoColors.white
                : CupertinoColors.label.resolveFrom(context),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppType.cell.copyWith(
              color: primary
                  ? CupertinoColors.white
                  : CupertinoColors.label.resolveFrom(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _textAction(BuildContext context, String label, VoidCallback onTap) =>
      CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 32),
        onPressed: onTap,
        child: Text(
          label,
          style: AppType.caption.copyWith(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      );

  Widget _syncStrip(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final failed = store.sync?.phase == SyncPhase.failed;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 8),
      onPressed: widget.onSync,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            failed
                ? CupertinoIcons.exclamationmark_circle
                : CupertinoIcons.cloud,
            size: 14,
            color: failed ? AppColors.danger.resolveFrom(context) : secondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              store.sync == null
                  ? '数据保存在本机 · 查看同步状态'
                  : '${store.sync!.label}'
                        '${store.pendingDays.isEmpty ? '' : '（${store.pendingDays.length} 项）'}'
                        ' · 查看同步状态',
              style: AppType.caption.copyWith(
                color: failed
                    ? AppColors.danger.resolveFrom(context)
                    : secondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.chevron_right, size: 10, color: secondary),
        ],
      ),
    );
  }
}

class _UndoBar extends StatelessWidget {
  const _UndoBar({required this.label, required this.onUndo});
  final String label;
  final VoidCallback onUndo;
  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(AppColors.navy, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '已登记 · $label',
              style: AppType.footnoteStyle.copyWith(color: accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
            minimumSize: const Size(0, 40),
            onPressed: onUndo,
            child: Text(
              '撤销',
              style: AppType.footnoteStyle.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.store,
    required this.day,
    required this.person,
    required this.leave,
    required this.onTap,
    required this.onLongPress,
    required this.onAbsent,
    required this.onLeaveTap,
  });
  final Workspace store;
  final String day;
  final Person person;
  final Leave? leave;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAbsent;
  final VoidCallback onLeaveTap;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final entry = store.record(person.id, day);
    final isOnLeave = leave != null;
    final pill = _pill(context, entry);
    final row = Container(
      margin: const EdgeInsets.only(bottom: Gap.xxs),
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.resolveFrom(context),
        borderRadius: BorderRadius.circular(Radii.control),
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
                    color: isOnLeave ? secondary : null,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _subtitle(entry, isOnLeave),
                  style: AppType.caption.copyWith(color: secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.xs),
          pill,
        ],
      ),
    );

    if (isOnLeave) {
      // A person on confirmed leave cannot be booked: keep the row inert.
      return Opacity(opacity: .55, child: row);
    }
    return Dismissible(
      key: ValueKey('roster-${person.id}'),
      direction: DismissDirection.horizontal,
      background: _swipeHint(context, '请假', Alignment.centerLeft),
      secondaryBackground: _swipeHint(context, '缺勤', Alignment.centerRight),
      confirmDismiss: (direction) async {
        // Leading swipe marks leave, trailing swipe marks absent: the
        // destructive action lives on the trailing edge, like iOS.
        if (direction == DismissDirection.startToEnd) {
          onLeaveTap();
        } else {
          onAbsent();
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: row,
      ),
    );
  }

  /// Second line: the employee id plus what the next tap will do.
  String _subtitle(Entry? entry, bool onLeave) {
    if (onLeave) return '请假中 · ${leave!.type}';
    final id = person.employeeId;
    final out = entry?.fields['out'] ?? '';
    final hint = entry == null
        ? '点一下记签到'
        : out.isEmpty
        ? '再点一下记签退'
        : '点一下可修改';
    return id.isEmpty ? hint : '$id · $hint';
  }
  Widget _swipeHint(BuildContext context, String label, Alignment align) =>
      Container(
        margin: const EdgeInsets.only(bottom: Gap.xxs),
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        alignment: align,
        decoration: BoxDecoration(
          color: AppColors.raised.resolveFrom(context),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Text(
          label,
          style: AppType.caption.copyWith(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _pill(BuildContext context, Entry? entry) {
    if (entry == null) {
      return _badge(
        context,
        '未登记',
        CupertinoColors.secondaryLabel.resolveFrom(context),
      );
    }
    final status = entry.fields['status'] ?? '正常';
    final time = entry.fields['in'] ?? '';
    final out = entry.fields['out'] ?? '';
    final text = out.isEmpty ? '$status $time' : '$status $time–$out';
    final color = switch (status) {
      '正常' => AppColors.success.resolveFrom(context),
      '迟到' || '早退' => AppColors.warning.resolveFrom(context),
      '缺勤' => AppColors.danger.resolveFrom(context),
      '请假' => AppColors.leave.resolveFrom(context),
      _ => CupertinoColors.secondaryLabel.resolveFrom(context),
    };
    return _badge(context, time.isEmpty ? status : text, color);
  }

  Widget _badge(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Text(
      text,
      style: AppType.caption.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}
