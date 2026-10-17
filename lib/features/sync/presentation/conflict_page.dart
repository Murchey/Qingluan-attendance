import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/widgets/ui.dart';

const fieldLabels = {
  'in': '签到时间',
  'out': '签退时间',
  'status': '状态',
  'note': '备注',
  'deleted': '记录存在状态',
};
bool remoteIsNewer(Entry? local, Entry remote, String field) {
  final a = DateTime.tryParse(local?.fieldTimes[field] ?? '');
  final b = DateTime.tryParse(remote.fieldTimes[field] ?? '');
  return a != null && b != null && b.isAfter(a);
}

Entry resolveEntry(
  Entry? local,
  Entry remote,
  Map<String, bool> choices,
  String author,
  String device,
) {
  final now = DateTime.now().toUtc().toIso8601String();
  final fields = {
    for (final f in fieldLabels.keys.where((k) => k != 'deleted'))
      f: (choices[f] == true ? remote.fields[f] : local?.fields[f]) ?? '',
  };
  return Entry(
    id: local?.id ?? remote.id,
    personId: remote.personId,
    day: remote.day,
    fields: fields,
    author: author,
    updatedAt: now,
    fieldTimes: {
      for (final f in fieldLabels.keys)
        f:
            (choices[f] == true
                ? remote.fieldTimes[f]
                : local?.fieldTimes[f]) ??
            now,
    },
    deleted: choices['deleted'] == true
        ? remote.deleted
        : local?.deleted ?? true,
    history: [
      ...?local?.history,
      ...remote.history,
      '$now · $author（$device）· 合并：${fieldLabels.keys.map((f) => '${fieldLabels[f]}=${choices[f] == true ? '远端' : '本地'}').join('，')}',
    ],
  );
}

class ConflictPage extends StatefulWidget {
  const ConflictPage({super.key, required this.store, required this.day});
  final Workspace store;
  final String day;
  @override
  State<ConflictPage> createState() => _ConflictPageState();
}

class _ConflictPageState extends State<ConflictPage> {
  final Map<String, bool> choices = {};
  List<Entry> get remote =>
      widget.store.remoteEntries.where((e) => e.day == widget.day).toList();
  Entry? local(Entry r) => widget.store.entries
      .where((e) => e.personId == r.personId && e.day == r.day)
      .firstOrNull;
  String key(Entry r, String f) => '${r.id}:$f';
  void all(int mode) => setState(() {
    for (final r in remote) {
      for (final f in fieldLabels.keys) {
        choices[key(r, f)] =
            mode == 1 || (mode == 2 && remoteIsNewer(local(r), r, f));
      }
    }
  });
  Future<void> save() async {
    if (widget.store.identity.isEmpty) {
      await message(context, '请先填写本地显示名', '在设置中填写，用于记录合并作者。');
      return;
    }
    if (!await confirm(context, '保存合并结果？', '只保存至本地待上传队列，确认同步后才提交云端。')) return;
    if (!mounted) return;
    await guarded(context, () async {
      await widget.store.commitMerge(
        remote
            .map(
              (r) => resolveEntry(
                local(r),
                r,
                {
                  for (final f in fieldLabels.keys)
                    f: choices[key(r, f)] ?? false,
                },
                widget.store.identity,
                widget.store.deviceId,
              ),
            )
            .toList(),
        widget.day,
      );
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Screen(
      title: widget.day,
      sidebarCount: 2,
      children: [
        const Text('表格可横向滚动。红色列为本地，绿色列为远端；勾选要保留的值。一键合并按字段更新时间选择，时间相同或缺失则保留本地。'),
        Wrap(
          children: [
            CupertinoButton(
              onPressed: () => all(0),
              child: const Text('全部采用本地'),
            ),
            CupertinoButton(
              onPressed: () => all(1),
              child: const Text('全部采用远端'),
            ),
            CupertinoButton(onPressed: () => all(2), child: const Text('一键合并')),
          ],
        ),
        for (final r in remote) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '${widget.store.name(r.personId)} · 本地 ${local(r)?.author ?? '无记录'} / 远端 ${r.author}',
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 680,
              child: Table(
                columnWidths: const {0: FixedColumnWidth(120)},
                border: TableBorder.all(
                  color: CupertinoColors.systemGrey3.resolveFrom(context),
                ),
                children: [
                  const TableRow(
                    children: [
                      Padding(padding: EdgeInsets.all(12), child: Text('字段')),
                      Padding(padding: EdgeInsets.all(12), child: Text('本地')),
                      Padding(padding: EdgeInsets.all(12), child: Text('远端')),
                    ],
                  ),
                  for (final f in fieldLabels.keys)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(fieldLabels[f]!),
                        ),
                        cell(r, f, false),
                        cell(r, f, true),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        CupertinoButton.filled(
          onPressed: remote.isEmpty ? null : save,
          child: const Text('保存合并 · 等待上传'),
        ),
      ],
    ),
  );
  Widget cell(Entry r, String f, bool isRemote) {
    final l = local(r);
    final value = f == 'deleted'
        ? ((isRemote ? r.deleted : l?.deleted ?? true) ? '删除 / 不存在' : '保留记录')
        : (isRemote ? r.fields[f] : l?.fields[f]) ?? '—';
    final chosen = (choices[key(r, f)] ?? false) == isRemote;
    return Container(
      color:
          (isRemote ? CupertinoColors.systemGreen : CupertinoColors.systemRed)
              .withValues(alpha: .09),
      child: CupertinoButton(
        padding: const EdgeInsets.all(12),
        onPressed: () => setState(() => choices[key(r, f)] = isRemote),
        child: Row(
          children: [
            Icon(
              chosen
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isEmpty ? '（空）' : value,
                style: TextStyle(
                  color: CupertinoColors.label.resolveFrom(context),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
