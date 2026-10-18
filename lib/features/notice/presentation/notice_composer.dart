import 'package:flutter/cupertino.dart';
import '../../../core/config/object_layout.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/calendar_board.dart';
import '../../../core/widgets/markdown.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/ui.dart';

const noticeTemplates = ['今日考勤情况', '调休计划', '自定义'];

/// Compose an admin notice. Returns the generated Markdown when it has been
/// queued, or null when the author cancelled.
Future<String?> openNoticeComposer(
  BuildContext context,
  Workspace store,
) async {
  if (store.identity.isEmpty) {
    final name = await input(context, '请先填写本地显示名');
    if (name == null || name.isEmpty) return null;
    await store.setIdentity(name);
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(
    CupertinoPageRoute<String>(builder: (_) => NoticeComposerPage(store: store)),
  );
}

String adminNoteMarkdown({
  required String title,
  required String body,
  required String author,
  required DateTime shanghai,
}) {
  final stamp = shanghai.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
  return '''# ${title.trim()}

> $author · $stamp · 管理员通知

${body.trim()}

---
*本通知由青鸾考勤管理员发布；其他设备打开应用后会通过 index.json 自动拉取。*
''';
}

String attendanceTemplate(Workspace store) {
  final day = businessDay();
  final active = store.activePeople.length;
  final entries = store.liveEntries.where((e) => e.day == day).toList();
  final leaves = store.leavesOn(day);
  final names = leaves
      .map((l) => '${store.name(l.personId)}（${l.type}）')
      .join('、');
  final late = entries.where((e) => e.fields['status'] == '迟到').length;
  final early = entries.where((e) => e.fields['status'] == '早退').length;
  final absent = entries.where((e) => e.fields['status'] == '缺勤').length;
  return '''- 应登记：$active 人
- 已登记：${entries.length} 人
- 迟到：$late 人 · 早退：$early 人 · 缺勤：$absent 人
- 今日请假：${leaves.length} 人${names.isEmpty ? '' : '（$names）'}

请各位核对自己的记录；如需补录或调整请假状态，请在今日下班前完成。
''';
}

String exchangeTemplate(Workspace store) {
  final today = DateTime.parse(businessDay());
  final from = dayKey(today);
  final to = dayKey(today.add(const Duration(days: 14)));
  final rows = store
      .leavesInRange(from, to)
      .where((l) => l.type == '调休')
      .toList();
  final lines = rows.isEmpty
      ? '- 未来 14 天没有已确认的调休安排，可在正文补充值班与调休计划。'
      : rows
            .map(
              (l) =>
                  '- ${store.name(l.personId)}：${l.startDay} 至 ${l.endDay}'
                  '${l.reason.isEmpty ? '' : '（${l.reason}）'}',
            )
            .join('\n');
  return '''## 未来 14 天调休安排

$lines

## 值班要求

- 各岗位保持一人在岗，调休人员的交接事项请提前登记。
- 调休当天不再重复登记考勤，如需变更请在请假记录中调整状态或时间。
''';
}

class NoticeComposerPage extends StatefulWidget {
  const NoticeComposerPage({super.key, required this.store});
  final Workspace store;
  @override
  State<NoticeComposerPage> createState() => _NoticeComposerPageState();
}

class _NoticeComposerPageState extends State<NoticeComposerPage> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  String template = noticeTemplates.first;
  bool publishing = false;

  Workspace get store => widget.store;

  @override
  void initState() {
    super.initState();
    _apply(noticeTemplates.first);
    titleController.addListener(_refresh);
    bodyController.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  void _apply(String name) {
    setState(() => template = name);
    if (name == '今日考勤情况') {
      titleController.text = '${businessDay()} 考勤情况';
      bodyController.text = attendanceTemplate(store);
    } else if (name == '调休计划') {
      titleController.text = '${businessDay()} 调休与值班安排';
      bodyController.text = exchangeTemplate(store);
    }
  }

  String get markdown => adminNoteMarkdown(
    title: titleController.text.trim().isEmpty
        ? '管理员通知'
        : titleController.text.trim(),
    body: bodyController.text.trim(),
    author: store.identity.isEmpty ? '管理员' : store.identity,
    shanghai: DateTime.now().toUtc().add(const Duration(hours: 8)),
  );

  Future<void> publish() async {
    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      await showMessageSheet(context, '内容不完整', '标题与正文都不能为空。');
      return;
    }
    if (!await showConfirmSheet(
      context,
      '发布管理员通知？',
      '将生成 note.md 与更新后的 index.json，加入待上传队列。'
          '其他设备下次打开应用时会自动收到这条通知。',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => publishing = true);
    await guarded(context, () async {
      final shanghai = DateTime.now().toUtc().add(const Duration(hours: 8));
      final version = shanghai.toIso8601String();
      final noteBody = adminNoteMarkdown(
        title: title,
        body: bodyController.text.trim(),
        author: store.identity.isEmpty ? '管理员' : store.identity,
        shanghai: shanghai,
      );
      await store.queueNotice({
        'channel': 'admin',
        'key': ObjectLayout.adminNote,
        'version': version,
        'title': title,
        'markdown': noteBody,
        'createdAt': version,
        'author': store.identity,
        'deviceId': store.deviceId,
        'status': 'pending',
      });
      if (mounted) Navigator.of(context).pop(noteBody);
    });
    if (mounted) setState(() => publishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      child: Screen(
        title: '管理员通知',
        children: [
          Text(
            '向共用同一存储桶的同事发布通知。发布内容会先生成待上传的 note.md 与 index.json，'
            '签名上传接入后自动同步到其他设备。',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
          const SizedBox(height: 16),
          SegmentedControl<String>(
            values: noticeTemplates,
            labels: noticeTemplates,
            value: template,
            onChanged: _apply,
          ),          const SizedBox(height: 18),
          _field(
            context,
            label: '标题',
            controller: titleController,
            hint: '例如：10 月 17 日考勤情况',
            maxLines: 1,
          ),
          const SizedBox(height: 14),
          _field(
            context,
            label: '正文（支持 Markdown）',
            controller: bodyController,
            hint: '支持标题、列表、引用、加粗等简单 Markdown',
            maxLines: 10,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '预览',
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
              ),
              const Spacer(),
              Text(
                '${titleController.text.trim().length} / '
                '${bodyController.text.trim().length}',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GlassCard(
            child: MarkdownView(
              markdown,
              baseSize: 13.5,
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            onPressed: publishing ? null : publish,
            child: Text(publishing ? '保存中…' : '发布通知 · 加入待上传'),
          ),
          const SizedBox(height: 8),
          Text(
            '当前版本未接入签名上传：通知会保存在本地待上传队列，'
            '不会伪造发布成功。已发布 ${store.noticeOutbox.length} 条。',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String hint,
    required int maxLines,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
      CupertinoTextField(
        controller: controller,
        minLines: maxLines > 2 ? 5 : 1,
        maxLines: maxLines,
        placeholder: hint,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface.resolveFrom(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: CupertinoColors.separator
                .resolveFrom(context)
                .withValues(alpha: .35),
            width: .6,
          ),
        ),
      ),
    ],
  );
}
