import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/widgets/app_widgets.dart';
import 'conflict_page.dart';

enum SyncStatusKind { ready, pending, conflict, unconfigured }

class SyncStatusSummary {
  const SyncStatusSummary({
    required this.kind,
    required this.title,
    required this.detail,
    required this.count,
    required this.icon,
    required this.color,
  });
  final SyncStatusKind kind;
  final String title;
  final String detail;
  final int count;
  final IconData icon;
  final Color color;
}

SyncStatusSummary syncSummary(Workspace store) {
  final conflicts = store.remoteEntries.map((e) => e.day).toSet().length;
  final pending = store.pendingDays.length;
  final configured = (store.settings['provider'] ?? '').toString().isNotEmpty;
  if (conflicts > 0) {
    return SyncStatusSummary(
      kind: SyncStatusKind.conflict,
      title: '有远端冲突待处理',
      detail: '$conflicts 个日期需要审查合并',
      count: conflicts,
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      color: AppColors.warning,
    );
  }
  if (pending > 0) {
    return SyncStatusSummary(
      kind: SyncStatusKind.pending,
      title: '有本地变更待上传',
      detail: '$pending 项本地变更等待同步',
      count: pending,
      icon: CupertinoIcons.arrow_up_circle_fill,
      color: AppColors.navy,
    );
  }
  if (!configured) {
    return const SyncStatusSummary(
      kind: SyncStatusKind.unconfigured,
      title: '尚未配置同步存储',
      detail: '可以继续离线登记，数据会保存在本机',
      count: 0,
      icon: CupertinoIcons.cloud,
      color: AppColors.muted,
    );
  }
  return const SyncStatusSummary(
    kind: SyncStatusKind.ready,
    title: '当前已同步',
    detail: '没有待处理的本地或远端变化',
    count: 0,
    icon: CupertinoIcons.checkmark_circle_fill,
    color: AppColors.success,
  );
}

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.store, required this.onSettings});
  final Workspace store;
  final VoidCallback onSettings;
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  bool checking = false;
  SyncStatusSummary get summary => syncSummary(widget.store);
  Future<void> check() async {
    if (checking) return;
    setState(() => checking = true);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => checking = false);
    await unavailable();
  }

  Future<void> unavailable() =>
      message(context, '同步尚未就绪', '当前版本暂不提供云端上传和下载。请继续离线登记，云端服务启用后可处理待上传记录。');
  @override
  Widget build(BuildContext context) {
    final s = summary;
    final pending = widget.store.pendingDays.toList()..sort();
    final conflictDays =
        widget.store.remoteEntries.map((e) => e.day).toSet().toList()..sort();
    return Screen(
      title: '同步中心',
      actions: [
        checking
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CupertinoActivityIndicator(),
              )
            : GlassIconButton(
                icon: CupertinoIcons.refresh,
                label: '刷新同步状态',
                onPressed: check,
              ),
        GlassIconButton(
          icon: CupertinoIcons.gear,
          label: '同步设置',
          onPressed: widget.onSettings,
        ),
      ],
      children: [
        _statusCard(context, s),
        const SizedBox(height: 24),
        if (pending.isNotEmpty) ...[
          SectionTitle(
            '本地待上传',
            action: Text(
              '${pending.length} 项',
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...pending.map((day) => _pendingTile(day)),
          const SizedBox(height: 20),
        ],
        if (conflictDays.isNotEmpty) ...[
          SectionTitle(
            '远端冲突待审查',
            action: Text(
              '${conflictDays.length} 个日期',
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...conflictDays.map((day) => _conflictTile(day)),
        ],
        if (pending.isEmpty && conflictDays.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.cloud,
            title: '暂无待同步变更',
            message: '新增人员或登记后，本地变化会出现在这里。离线数据会在同步服务启用后继续保留。',
          ),
        const SizedBox(height: 18),
        const Text(
          '当前版本暂未启用云端同步。可继续离线登记，人员、记录与待上传标记在重启后保留。',
          style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13),
        ),
      ],
    );
  }

  Widget _statusCard(BuildContext context, SyncStatusSummary s) => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: .13),
                shape: BoxShape.circle,
              ),
              child: Icon(s.icon, color: s.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.detail,
                    style: TextStyle(
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (s.count > 0)
              Text(
                '${s.count}',
                style: TextStyle(
                  color: s.color,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '存储提供商：${widget.store.settings['provider']}',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        Text(
          '最近同步：${widget.store.lastSync ?? '尚未同步'}',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                onPressed: checking ? null : check,
                child: const Text('立即检查'),
              ),
            ),
            Expanded(
              child: CupertinoButton.filled(
                onPressed: checking ? null : unavailable,
                child: const Text('立即同步'),
              ),
            ),
          ],
        ),
        CupertinoButton(
          onPressed: widget.onSettings,
          child: const Text('配置对象存储'),
        ),
      ],
    ),
  );
  Widget _pendingTile(String day) => GlassCard(
    child: SettingRow(
      day,
      detail:
          '本地待上传 · ${widget.store.identity.isEmpty ? '未设置身份' : widget.store.identity}',
      trailing: const Icon(CupertinoIcons.arrow_up_circle),
    ),
  );
  Widget _conflictTile(String day) => GlassCard(
    child: SettingRow(
      day,
      detail: '远端变化 / 冲突待审查',
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ConflictPage(store: widget.store, day: day),
        ),
      ),
      trailing: const Icon(CupertinoIcons.chevron_right),
    ),
  );
}
