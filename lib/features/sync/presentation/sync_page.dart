import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/widgets/app_widgets.dart';
import 'conflict_page.dart';

class SyncPage extends StatelessWidget {
  const SyncPage({super.key, required this.store, required this.onSettings});
  final Workspace store;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => Screen(
    title: '同步中心',
    children: [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '本地数据已保存',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(store.syncMessage),
            const SizedBox(height: 8),
            Text('存储提供商：${store.settings['provider']}'),
            Text('最近同步：${store.lastSync ?? '尚未同步'}'),
            const Text('本地 manifest：待生成\n远端 manifest：尚未读取'),
            Wrap(
              children: [
                CupertinoButton(
                  onPressed: () => unavailable(context),
                  child: const Text('立即检查'),
                ),
                CupertinoButton.filled(
                  onPressed: () => unavailable(context),
                  child: const Text('立即同步'),
                ),
              ],
            ),
            CupertinoButton(onPressed: onSettings, child: const Text('配置对象存储')),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const SectionTitle('待处理变化'),
      const SizedBox(height: 12),
      if (store.pendingDays.isEmpty && store.remoteEntries.isEmpty)
        const EmptyState(
          icon: CupertinoIcons.cloud,
          title: '暂无待同步变更',
          message: '新增人员或登记后，本地变化会出现在这里。',
        ),
      ...store.pendingDays.map(
        (d) => GlassCard(
          child: SettingRow(
            d,
            detail:
                '本地待上传 · ${store.identity.isEmpty ? '未设置身份' : store.identity}',
            trailing: const Icon(CupertinoIcons.arrow_up_circle),
          ),
        ),
      ),
      for (final day in store.remoteEntries.map((e) => e.day).toSet())
        GlassCard(
          child: SettingRow(
            day,
            detail: '远端变化 / 冲突待审查',
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => ConflictPage(store: store, day: day),
              ),
            ),
          ),
        ),
      const SizedBox(height: 24),
      const Text(
        '当前版本暂未启用云端同步。可继续离线登记，人员、记录与待上传标记在重启后保留。',
        style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13),
      ),
    ],
  );
  void unavailable(BuildContext context) =>
      message(context, '同步尚未就绪', '当前版本暂不提供云端上传和下载。请继续离线登记，云端服务启用后可处理待上传记录。');
}
