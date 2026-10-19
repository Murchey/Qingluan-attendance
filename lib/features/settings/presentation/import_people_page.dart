import 'package:flutter/cupertino.dart';
import '../../../core/data/spreadsheet_io.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/ui.dart';

/// Dedicated import page: explains the expected columns, offers the Excel
/// template, and only then opens the system file picker.
class ImportPeoplePage extends StatefulWidget {
  const ImportPeoplePage({super.key, required this.store});
  final Workspace store;
  @override
  State<ImportPeoplePage> createState() => _ImportPeoplePageState();
}

class _ImportPeoplePageState extends State<ImportPeoplePage> {
  bool busy = false;
  Workspace get store => widget.store;

  Future<void> downloadTemplate() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    await guarded(context, () async {
      final result = await savePeopleTemplate(origin);
      if (result != null && mounted) {
        await message(
          context,
          '模板已生成',
          '文件：$result\n\n请在系统分享面板中保存到「文件」或发送到电脑后填写。',
        );
      }
    });
  }

  Future<void> pickAndImport() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final preview = await pickPeople(store);
      if (preview == null || !mounted) return;
      if (preview.names.isEmpty) {
        await message(
          context,
          '没有可导入的人员',
          preview.issues.isEmpty
              ? '文件中没有人员数据。请从第二行开始填写姓名，或下载模板后重新填写。'
              : preview.issues.take(8).join('\n'),
        );
        return;
      }
      final accepted = await Navigator.of(context).push<bool>(
        CupertinoPageRoute(
          builder: (_) => _ImportPreviewPage(preview: preview),
        ),
      );
      if (accepted != true || !mounted) return;
      final hasDuplicates = preview.issues.any((s) => s.contains('重名'));
      if (hasDuplicates) {
        final choice = await choose(context, '发现重复人员', {
          'copy': '作为副本保存（自动追加数字）',
          'skip': '不保存重复项',
        });
        if (!mounted || choice != 'copy') return;
      }
      for (final name in preview.names) {
        await store.savePerson(
          name,
          gender: preview.gender[name] ?? '',
          employeeId: preview.employeeIds[name] ?? '',
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      if (mounted) await message(context, '导入失败', e.message.toString());
    } catch (_) {
      if (mounted) {
        await message(
          context,
          '导入失败',
          '无法读取文件，请确认文件为有效的 Excel（.xlsx）或 CSV，并检查存储权限后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      child: Screen(
        title: '导入人员',
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.person_2,
                      size: Sizes.icon,
                      color: AppColors.navy.resolveFrom(context),
                    ),
                    const SizedBox(width: Gap.sm),
                    Text('批量导入名单', style: AppType.rowTitleEmphasized),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '支持 Excel（.xlsx）与 CSV。第一行需包含「姓名」列，'
                  '可选「性别」「工号」列；从第二行开始填写人员。',
                  style: AppType.footnoteStyle.copyWith(color: secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          GroupLabel('模板'),
          SettingsGroup(
            children: [
              SettingRow(
                '下载 Excel 模板',
                detail: '含「姓名 / 性别 / 工号」表头与填写说明',
                onTap: downloadTemplate,
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            '示例：张三 / 男 / EMP-1001。模板第一行表头请勿修改。',
            style: AppType.caption.copyWith(color: secondary),
          ),
          const SizedBox(height: Gap.lg),
          PrimaryButton(
            onPressed: busy ? null : pickAndImport,
            child: Text(busy ? '正在读取…' : '选择文件并导入'),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            '同名人员会提示作为副本或跳过；缺少姓名的行会跳过。',
            style: AppType.caption.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }
}

class _ImportPreviewPage extends StatelessWidget {
  const _ImportPreviewPage({required this.preview});
  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final warning = AppColors.warning.resolveFrom(context);
    final names = preview.names;
    const maxNames = 50;
    return CupertinoPageScaffold(
      child: Screen(
        title: '导入预览',
        children: [
          Text(
            '仅新增名单，不覆盖现有人名、考勤和停用状态。',
            style: AppType.footnoteStyle.copyWith(color: secondary),
          ),
          if (preview.issues.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            SectionTitle(
              '需要注意',
              action: Text(
                '${preview.issues.length} 条',
                style: AppType.footnoteStyle.copyWith(color: warning),
              ),
            ),
            const SizedBox(height: Gap.xs),
            for (final issue in preview.issues.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xxs),
                child: Text(
                  issue,
                  style: TextStyle(fontSize: 12, height: 1.4, color: warning),
                ),
              ),
            if (preview.issues.length > 12)
              Text(
                '其余 ${preview.issues.length - 12} 条问题已省略。',
                style: AppType.caption.copyWith(color: secondary),
              ),
          ],
          const SizedBox(height: Gap.lg),
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('确认导入 ${names.length} 人'),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            '确认后返回人员名单；如需取消请点左上角返回。',
            style: AppType.caption.copyWith(color: secondary),
          ),
          const SizedBox(height: Gap.lg),
          SectionTitle('名单预览'),
          const SizedBox(height: Gap.xs),
          SettingsGroup(
            children: [
              for (final name in names.take(maxNames))
                SettingRow(
                  name,
                  detail: [
                    preview.gender[name] ?? '',
                    preview.employeeIds[name] ?? '',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
            ],
          ),
          if (names.length > maxNames) ...[
            const SizedBox(height: Gap.xs),
            Text(
              '其余 ${names.length - maxNames} 人将在确认后一并导入。',
              style: AppType.caption.copyWith(color: secondary),
            ),
          ],
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }
}
