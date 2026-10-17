import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/data/spreadsheet_io.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../attendance/presentation/entry_editor.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, required this.store});
  final Workspace store;
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String query = '', person = '', status = '', author = '';
  DateTime? from, to;
  List<Entry> get filtered =>
      widget.store.liveEntries
          .where(
            (e) =>
                (person.isEmpty || e.personId == person) &&
                (status.isEmpty || e.fields['status'] == status) &&
                (author.isEmpty || e.author == author) &&
                (from == null ||
                    e.day.compareTo(from!.toIso8601String().substring(0, 10)) >=
                        0) &&
                (to == null ||
                    e.day.compareTo(to!.toIso8601String().substring(0, 10)) <=
                        0) &&
                '${widget.store.name(e.personId)} ${e.fields['note']}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
          )
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));
  Future<void> range() async {
    var start =
        from ??
        DateTime.parse(businessDay()).subtract(const Duration(days: 30));
    var end = to ?? DateTime.parse(businessDay());
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (c) => Container(
        height: 480,
        color: CupertinoColors.systemBackground.resolveFrom(c),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              CupertinoButton(
                onPressed: () {
                  if (start.isAfter(end)) {
                    message(c, '日期范围无效', '开始日期不能晚于结束日期。');
                    return;
                  }
                  setState(() {
                    from = start;
                    to = end;
                  });
                  Navigator.pop(c);
                },
                child: const Text('应用日期范围'),
              ),
              const Text('开始日期'),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: start,
                  onDateTimeChanged: (v) => start = v,
                ),
              ),
              const Text('结束日期'),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: end,
                  onDateTimeChanged: (v) => end = v,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> export() async {
    final rows = filtered;
    if (rows.isEmpty) {
      await message(context, '没有可导出的记录', '请调整筛选条件或先录入考勤。');
      return;
    }
    final columns = exportColumns.toSet();
    final accepted = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => Container(
          height: 560,
          color: CupertinoColors.systemBackground.resolveFrom(c),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('导出当前筛选范围 · 选择字段'),
                ...exportColumns.map(
                  (s) => SettingRow(
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
                    ),
                  ),
                ),
                CupertinoButton.filled(
                  onPressed: columns.isEmpty
                      ? null
                      : () => Navigator.pop(c, true),
                  child: Text('导出 ${rows.length} 条'),
                ),
              ],
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
  Widget _detailBody(BuildContext c, Entry e) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('考勤详情')),
    child: Screen(
      title: widget.store.name(e.personId),
      children: [
        Text(e.day),
        ...e.fields.entries.map(
          (f) => SettingRow(
            {'in': '签到', 'out': '签退', 'status': '状态', 'note': '备注'}[f.key] ??
                f.key,
            detail: f.value,
          ),
        ),
        const Text('修改历史'),
        ...e.history.map(
          (h) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(h, style: const TextStyle(fontSize: 12)),
          ),
        ),
        CupertinoButton.filled(
          onPressed: () => openEditor(c, widget.store, e.day, entry: e),
          child: const Text('编辑登记'),
        ),
        CupertinoButton(
          onPressed: () => guarded(c, () async {
            if (await confirm(c, '删除这条记录？', '会保留删除标记和审计历史，并在后续同步。')) {
              await widget.store.deleteEntry(e);
              if (c.mounted) Navigator.pop(c);
            }
          }),
          child: const Text(
            '删除记录',
            style: TextStyle(color: CupertinoColors.destructiveRed),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final rows = filtered;
    final groups = rows.map((e) => e.day).toSet();
    return Screen(
      title: '历史记录',
      sidebarCount: 3,
      actions: [
        CupertinoButton(
          onPressed: export,
          child: const Icon(
            CupertinoIcons.square_arrow_up,
            semanticLabel: '导出 Excel',
          ),
        ),
      ],
      children: [
        CupertinoSearchTextField(
          placeholder: '搜索姓名或备注',
          onChanged: (s) => setState(() => query = s),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          children: [
            CupertinoButton(
              onPressed: range,
              child: Text(
                from == null
                    ? '日期范围'
                    : '${from!.month}/${from!.day}—${to!.month}/${to!.day}',
              ),
            ),
            CupertinoButton(
              onPressed: () async {
                final v = await choose(context, '筛选人员', {
                  '': '全部人员',
                  for (final p in widget.store.people) p.id: p.name,
                });
                if (v != null) setState(() => person = v);
              },
              child: Text(person.isEmpty ? '人员' : widget.store.name(person)),
            ),
            CupertinoButton(
              onPressed: () async {
                final v = await choose(context, '筛选状态', {
                  '': '全部状态',
                  for (final s in statuses) s: s,
                });
                if (v != null) setState(() => status = v);
              },
              child: Text(status.isEmpty ? '状态' : status),
            ),
            CupertinoButton(
              onPressed: () async {
                final v = await choose(context, '最后修改人', {
                  '': '全部修改人',
                  for (final e in widget.store.liveEntries) e.author: e.author,
                });
                if (v != null) setState(() => author = v);
              },
              child: Text(author.isEmpty ? '修改人' : author),
            ),
            CupertinoButton(
              onPressed: () => setState(() {
                from = null;
                to = null;
                person = '';
                status = '';
                author = '';
              }),
              child: const Text('重置'),
            ),
          ],
        ),
        Text('共 ${rows.length} 条记录'),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.doc_text_search,
            title: '暂无记录',
            message: '登记考勤后可在这里搜索、筛选和导出。',
          ),
        for (final day in groups) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SectionTitle(
              '$day · ${rows.where((e) => e.day == day).length} 人',
            ),
          ),
          ...rows
              .where((e) => e.day == day)
              .map(
                (e) => EntryTile(
                  store: widget.store,
                  entry: e,
                  onTap: () => detail(e),
                ),
              ),
        ],
      ],
    );
  }
}
