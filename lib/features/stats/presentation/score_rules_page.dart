import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/ui.dart';
import '../domain/attendance_score.dart';

Future<void> openScoreRules(BuildContext context, Workspace store) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => ScoreRulesPage(store: store)),
    );

/// Editor for the default deduction values behind the attendance score. The
/// stats page opens this page, and 设置 → 考勤扣分规则 links here as well.
class ScoreRulesPage extends StatelessWidget {
  const ScoreRulesPage({super.key, required this.store});
  final Workspace store;

  Future<void> _edit(
    BuildContext context, {
    required String kind,
    String key = '',
    required String title,
    required String hint,
    required double max,
  }) async {
    final rules = scoreRulesOf(store);
    final current = switch (kind) {
      'base' => rules.base,
      'leave' => rules.leavePoints(key),
      _ => rules.statusPoints(key),
    };
    final value = await input(
      context,
      title,
      value: scoreText(current),
      hint: hint,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (value == null || !context.mounted) return;
    final parsed = double.tryParse(value);
    final points = parsed == null ? null : (parsed * 100).round() / 100;
    if (points == null || points < 0 || points > max) {
      await message(
        context,
        '扣分值无效',
        '请输入 0 至 ${scoreText(max)} 之间的数字，可保留两位小数。',
      );
      return;
    }
    await guarded(context, () async {
      final latest = scoreRulesOf(store);
      final next = kind == 'base'
          ? latest.withBase(points)
          : latest.withPoint(kind, key, points);
      await store.saveScoreRules(next.toJson());
    });
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await confirm(
      context,
      '恢复默认扣分值？',
      '当前自定义的扣分值会被覆盖，已计算的考勤分按默认规则重算。',
    );
    if (!confirmed || !context.mounted) return;
    await guarded(
      context,
      () => store.saveScoreRules(ScoreRules.defaults().toJson()),
    );
  }

  Widget _group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupLabel(title),
        SettingsGroup(children: children),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final rules = scoreRulesOf(store);
        String pointDetail(double points, String unit) =>
            points > 0 ? '每 1 $unit扣 ${scoreText(points)} 分' : '不扣分';
        return CupertinoPageScaffold(
          child: Screen(
            title: '考勤扣分规则',
            children: [
              Text(
                '考勤分从基准分开始，减去统计区间内已确认请假的天数与'
                '迟到、早退、缺勤的次数。修改后立即按新规则重算。',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
              const SizedBox(height: Gap.md),
              _group('基准分', [
                SettingRow(
                  '基准分',
                  detail: '每人从 ${scoreText(rules.base)} 分开始',
                  onTap: () => _edit(
                    context,
                    kind: 'base',
                    title: '基准分',
                    hint: '例如 100',
                    max: 1000,
                  ),
                ),
              ]),
              _group('请假扣分', [
                for (final type in leaveTypes)
                  SettingRow(
                    type,
                    detail: pointDetail(rules.leavePoints(type), '天'),
                    onTap: () => _edit(
                      context,
                      kind: 'leave',
                      key: type,
                      title: '$type扣分（分/天）',
                      hint: '例如 2 或 0.5',
                      max: 100,
                    ),
                  ),
              ]),
              _group('考勤状态扣分', [
                for (final status in scoreStatuses)
                  SettingRow(
                    status,
                    detail: pointDetail(rules.statusPoints(status), '次'),
                    onTap: () => _edit(
                      context,
                      kind: 'status',
                      key: status,
                      title: '$status扣分（分/次）',
                      hint: '例如 2 或 0.5',
                      max: 100,
                    ),
                  ),
              ]),
              PrimaryButton(
                onPressed: () => _reset(context),
                child: const Text('恢复默认扣分值'),
              ),
              const SizedBox(height: Gap.sm),
              Text(
                '默认：事假 2 分/天、病假 1 分/天、其他 1 分/天，'
                '年假 / 调休 / 婚假 / 产假不扣分；迟到、早退各 2 分/次，'
                '缺勤 5 分/次。考勤分最低为 0 分。',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ],
          ),
        );
      },
    );
  }
}
