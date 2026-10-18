import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/data/spreadsheet_io.dart';
import '../../../core/widgets/calendar_board.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../attendance/presentation/entry_editor.dart';
import '../../sync/presentation/sync_page.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, required this.store});
  final Workspace store;
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String query = '', person = '', status = '', author = '';
  String datePreset = '全部';
  String? syncNote;

  /// Pull-to-refresh: push pending edits, then pull the cloud copy when the
  /// local side has nothing unsaved.
  Future<void> refresh() async {
    final sync = widget.store.sync;
    if (sync == null) {
      if (mounted) setState(() => syncNote = '同步服务未启动');
      return;
    }
    final outcome = await sync.refresh();
    if (!mounted) return;
    setState(() => syncNote = outcome.message);
  }

  DateTime? from, to;
  List<Entry> get filtered =>
      widget.store.liveEntries
          .where(
            (e) =>
                (person.isEmpty || e.personId == person) &&
                (status.isEmpty || e.fields['status'] == status) &&
                (author.isEmpty || e.author == author) &&
                (from == null || e.day.compareTo(dayKey(from!)) >= 0) &&
                (to == null || e.day.compareTo(dayKey(to!)) <= 0) &&
                '${widget.store.name(e.personId)} ${e.fields['note']}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
          )
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));

  Future<void> range() async {
    final picked = await showRangeSheet(
      context,
      from: from == null ? null : dayKey(from!),
      to: to == null ? null : dayKey(to!),
      title: '筛选日期范围',
      subtitle: '点选开始与结束日期，红色为请假日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      from = DateTime.parse(picked.$1);
      to = DateTime.parse(picked.$2);
      datePreset = '自定义';
    });
  }

  void setDatePreset(String value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? start;
    DateTime? end;
    if (value == '今日') {
      start = today;
      end = today;
    } else if (value == '本周') {
      start = today.subtract(Duration(days: today.weekday - 1));
      end = start.add(const Duration(days: 6));
    } else if (value == '本月') {
      start = DateTime(today.year, today.month);
      end = DateTime(today.year, today.month + 1, 0);
    }
    setState(() {
      datePreset = value;
      from = start;
      to = end;
    });
  }

  Future<void> filters() => showAppSheet<void>(
    context,
    (sheetContext) => StatefulBuilder(
      builder: (context, update) => SheetPanel(
        title: '筛选记录',
        subtitle: '条件会立即应用到下方的历史列表',
        child: Column(
          children: [
            SettingRow(
              '日期范围',
              detail: from == null ? '不限' : '${dayKey(from!)} — ${dayKey(to!)}',
              onTap: () {
                Navigator.of(sheetContext).pop();
                range();
              },
            ),
            SettingRow(
              '人员',
              detail: person.isEmpty ? '全部人员' : widget.store.name(person),
              onTap: () async {
                final v = await choose<String>(context, '筛选人员', {
                  '': '全部人员',
                  for (final p in widget.store.visiblePeople) p.id: p.name,
                });
                if (v != null && mounted) {
                  setState(() => person = v);
                  update(() {});
                }
              },
            ),
            SettingRow(
              '状态',
              detail: status.isEmpty ? '全部状态' : status,
              onTap: () async {
                final v = await choose<String>(context, '筛选状态', {
                  '': '全部状态',
                  for (final s in statuses) s: s,
                });
                if (v != null && mounted) {
                  setState(() => status = v);
                  update(() {});
                }
              },
            ),
            SettingRow(
              '修改人',
              detail: author.isEmpty ? '全部修改人' : author,
              onTap: () async {
                final v = await choose<String>(context, '最后修改人', {
                  '': '全部修改人',
                  for (final e in widget.store.liveEntries) e.author: e.author,
                });
                if (v != null && mounted) {
                  setState(() => author = v);
                  update(() {});
                }
              },
            ),
            CupertinoButton(
              onPressed: () {
                setState(() {
                  from = null;
                  to = null;
                  datePreset = '全部';
                  person = '';
                  status = '';
                  author = '';
                });
                Navigator.of(sheetContext).pop();
              },
              child: const Text('重置筛选'),
            ),
          ],
        ),
        footer: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const SizedBox(
            height: 52,
            child: Center(
              child: Text(
                '完成',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> export() async {
    final rows = filtered;
    if (rows.isEmpty) {
      await message(context, '没有可导出的记录', '请调整筛选条件或先录入考勤。');
      return;
    }
    final columns = exportColumns.toSet();
    final accepted = await showAppSheet<bool>(
      context,
      (sheetContext) => StatefulBuilder(
        builder: (context, update) => SheetPanel(
          title: '导出 Excel',
          subtitle: '导出当前筛选范围 · ${rows.length} 条记录 · 选择字段',
          child: Column(
            children: [
              for (final s in exportColumns)
                SettingRow(
                  s,
                  onTap: () => update(
                    () => columns.contains(s)
                        ? columns.remove(s)
                        : columns.add(s),
                  ),
                  trailing: Icon(
                    columns.contains(s)
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    color: columns.contains(s)
                        ? CupertinoTheme.of(context).primaryColor
                        : CupertinoColors.tertiaryLabel.resolveFrom(context),
                    size: 20,
                  ),
                ),
            ],
          ),
          footer: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: columns.isEmpty
                ? null
                : () => Navigator.of(sheetContext).pop(true),
            child: const SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  '导出',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await guarded(context, () async {
      final box = context.findRenderObject() as RenderBox;
      final result = await saveWorkbook(
        widget.store,
        rows,
        exportColumns.where(columns.contains).toList(),
        box.localToGlobal(Offset.zero) & box.size,
      );
      if (mounted && result != null) await message(context, '导出已生成', result);
    });
  }

  void detail(Entry e) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (c) => ListenableBuilder(
        listenable: widget.store,
        builder: (c, _) {
          final current = widget.store.liveEntries
              .where((r) => r.id == e.id)
              .firstOrNull;
          if (current == null) {
            return const CupertinoPageScaffold(
              child: Center(child: Text('记录已删除')),
            );
          }
          return _detailBody(c, current);
        },
      ),
    ),
  );

  Future<void> editField(Entry entry, String field) async {
    String? value;
    if (field == 'status') {
      value = await choose<String>(
        context,
        '修改状态',
        {for (final s in statuses) s: s},
        selected: {entry.fields['status'] ?? ''},
      );
    } else if (field == 'in' || field == 'out') {
      value = await showTimePickSheet(
        context,
        title: field == 'in' ? '修改签到' : '修改签退',
        initial: entry.fields[field] ?? '',
        presets: const ['08:30', '09:00', '12:00', '18:00', '现在'],
      );
    } else {
      value = await input(context, '修改备注', value: entry.fields['note'] ?? '');
    }
    if (value == null || !mounted) return;
    await guarded(
      context,
      () => widget.store.saveEntries(
        [entry.personId],
        entry.day,
        {...entry.fields, field: value!},
      ),
    );
  }

  Widget _detailBody(BuildContext c, Entry e) => CupertinoPageScaffold(
    child: Screen(
      title: widget.store.name(e.personId),
      children: [
        Text(
          e.day,
          style: AppType.footnoteStyle.copyWith(
            color: CupertinoColors.secondaryLabel.resolveFrom(c),
          ),
        ),
        const SizedBox(height: Gap.xs),
        SettingsGroup(
          children: [
            for (final f in e.fields.entries)
              SettingRow(
                {
                      'in': '签到',
                      'out': '签退',
                      'status': '状态',
                      'note': '备注',
                    }[f.key] ??
                    f.key,
                detail: f.value.isEmpty ? '未填写' : f.value,
              ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        const GroupLabel('最近修改'),
        SettingsGroup(
          children: [
            for (final h in e.history.reversed.take(2))
              SettingRow(
                prettyHistory(h),
                leading: Icon(
                  CupertinoIcons.time,
                  size: Sizes.icon - 3,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(c),
                ),
              ),
          ],
        ),
        if (e.history.length > 2)
          Align(
            alignment: Alignment.center,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              onPressed: () => Navigator.of(c).push(
                CupertinoPageRoute<void>(
                  builder: (_) => HistoryPage(history: e.history),
                ),
              ),
              child: Text(
                '全部 ${e.history.length} 条历史',
                style: AppType.footnoteStyle.copyWith(
                  color: CupertinoTheme.of(c).primaryColor,
                ),
              ),
            ),
          ),
        const SizedBox(height: Gap.md),
        PrimaryButton(
          onPressed: () => openEditor(c, widget.store, e.day, entry: e),
          child: const Text('编辑登记'),
        ),
        const SizedBox(height: Gap.lg),
        SettingsGroup(
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: Gap.sm),
              pressedOpacity: .5,
              onPressed: () => guarded(c, () async {
                if (await confirm(c, '删除这条记录？', '会保留删除标记和审计历史，并在后续同步。')) {
                  await widget.store.deleteEntry(e);
                  if (c.mounted) Navigator.pop(c);
                }
              }),
              child: const SizedBox(
                width: double.infinity,
                height: 40,
                child: Center(
                  child: Text(
                    '删除记录',
                    style: TextStyle(
                      fontSize: 17,
                      color: CupertinoColors.destructiveRed,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final rows = filtered;
    final groups = <String, List<Entry>>{};
    for (final row in rows) {
      groups.putIfAbsent(row.day, () => []).add(row);
    }
    final active = [person, status, author].where((s) => s.isNotEmpty).length;
    final filtersOn = active + (from == null ? 0 : 1);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Screen(
      title: '历史记录',
      sidebarCount: 3,
      onRefresh: refresh,
      actions: [
        GlassIconButton(
          icon: CupertinoIcons.square_arrow_up,
          label: '导出 Excel',
          onPressed: export,
        ),
      ],
      children: [
        Row(
          children: [
            Expanded(
              child: CupertinoSearchTextField(
                placeholder: '搜索姓名或备注',
                onChanged: (s) => setState(() => query = s),
              ),
            ),
            const SizedBox(width: Gap.xs),
            GlassIconButton(
              icon: CupertinoIcons.slider_horizontal_3,
              label: '筛选记录',
              onPressed: filters,
            ),
          ],
        ),
        CollaborationStatusBar(
          store: widget.store,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => SyncPage(
                store: widget.store,
                onSettings: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
        SegmentedControl<String>(
          values: const ['今日', '本周', '本月', '全部'],
          labels: const ['今日', '本周', '本月', '全部'],
          value: datePreset == '自定义' ? '全部' : datePreset,
          onChanged: setDatePreset,
        ),
        if (datePreset == '自定义')
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            onPressed: range,
            child: Text('${dayKey(from!)} — ${dayKey(to!)}'),
          ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                syncNote == null
                    ? '共 ${rows.length} 条记录'
                    : '共 ${rows.length} 条记录 · $syncNote',
                style: AppType.footnoteStyle.copyWith(color: secondary),
              ),
            ),
            if (filtersOn > 0)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xxs),
                onPressed: () => setState(() {
                  from = null;
                  to = null;
                  datePreset = '全部';
                  person = '';
                  status = '';
                  author = '';
                }),
                child: Text(
                  '清除 $filtersOn 项筛选',
                  style: AppType.footnoteStyle.copyWith(
                    color: CupertinoTheme.of(context).primaryColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        if (rows.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.doc_text_search,
            title: '暂无记录',
            message: '登记考勤后可在这里搜索、筛选和导出。',
          ),
        for (final day in groups.keys) ...[
          Padding(
            padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.xs),
            child: Row(
              children: [
                Text(day, style: AppType.groupLabel.copyWith(color: secondary)),
                const SizedBox(width: Gap.xs),
                Text(
                  '${groups[day]!.length} 人',
                  style: AppType.caption.copyWith(
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          _RecordHeader(),
          ...groups[day]!.map(
            (e) => _RecordTableRow(
              store: widget.store,
              entry: e,
              onOpen: () => detail(e),
              onEdit: (field) => editField(e, field),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecordHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xxs),
    child: Row(
      children: const [
        SizedBox(width: 108, child: Text('人员')),
        SizedBox(width: 64, child: Text('签到')),
        SizedBox(width: 64, child: Text('签退')),
        SizedBox(width: 72, child: Text('状态')),
        Expanded(child: Text('修改人')),
      ],
    ),
  );
}

class _RecordTableRow extends StatelessWidget {
  const _RecordTableRow({
    required this.store,
    required this.entry,
    required this.onOpen,
    required this.onEdit,
  });
  final Workspace store;
  final Entry entry;
  final VoidCallback onOpen;
  final ValueChanged<String> onEdit;

  Widget cell(BuildContext context, String field, String text, double width) =>
      SizedBox(
        width: width,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          alignment: Alignment.centerLeft,
          onPressed: () => onEdit(field),
          child: Text(
            text.isEmpty ? '—' : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.xxs),
    child: GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              alignment: Alignment.centerLeft,
              onPressed: onOpen,
              child: Text(
                store.name(entry.personId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowTitle,
              ),
            ),
          ),
          cell(context, 'in', entry.fields['in'] ?? '', 64),
          cell(context, 'out', entry.fields['out'] ?? '', 64),
          cell(context, 'status', entry.fields['status'] ?? '', 72),
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              alignment: Alignment.centerLeft,
              onPressed: onOpen,
              child: Text(
                '${entry.author}\n${prettyHistory(entry.updatedAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// `2026-10-18T03:25:52.167Z · 管理员 · 保存登记` → readable local time.
String prettyHistory(String line) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})(:\d{2})?([.0-9]*)?Z?',
  ).firstMatch(line);
  if (match == null) return line;
  return line.replaceRange(0, match.end, '${match[1]} ${match[2]}');
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.history});
  final List<String> history;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Screen(
      title: '修改历史',
      children: [
        GlassCard(
          child: Column(
            children: [
              for (final item in history.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(CupertinoIcons.time, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
