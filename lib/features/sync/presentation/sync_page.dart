import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/bucket_address.dart';
import '../../../core/data/workspace.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/storage/cos_storage.dart';
import '../../../core/result/app_result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../notice/presentation/notice_panel.dart';
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
  final provider = (store.settings['provider'] ?? '').toString();
  final configured = provider == 'OSS' || provider == 'COS'
      ? BucketAddress.configuredUrl(store.settings, provider).isNotEmpty
      : (store.settings['endpoint'] ?? '').toString().isNotEmpty &&
            (store.settings['bucket'] ?? '').toString().isNotEmpty;
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
  final last = store.lastSync;
  final lastText = last == null ? '' : formatSyncTime(last);
  return SyncStatusSummary(
    kind: SyncStatusKind.ready,
    title: lastText.isEmpty ? '本地数据已保存' : '已与云端同步',
    detail: lastText.isEmpty ? '配置完成后，每次保存都会自动上传' : '最近同步 $lastText · 保存后自动上传',
    count: 0,
    icon: CupertinoIcons.checkmark_circle_fill,
    color: AppColors.success,
  );
}

class CollaborationStatusBar extends StatelessWidget {
  const CollaborationStatusBar({
    super.key,
    required this.store,
    required this.onTap,
    this.onConfigure,
  });
  final Workspace store;
  final VoidCallback onTap;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final failed = store.sync?.phase == SyncPhase.failed;
    final uploading = store.sync?.phase == SyncPhase.uploading;
    final unconfigured = store.sync?.phase == SyncPhase.unconfigured;
    final pending = store.pendingDays.length;
    final remote = store.remoteEntries.length;

    final danger = AppColors.danger.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final success = AppColors.success.resolveFrom(context);

    late final String label;
    late final Color color;
    late final IconData icon;
    if (failed) {
      label = '同步失败，点击重试';
      color = danger;
      icon = CupertinoIcons.exclamationmark_circle;
    } else if (uploading) {
      label = '正在同步…';
      color = secondary;
      icon = CupertinoIcons.arrow_2_circlepath;
    } else if (unconfigured) {
      label = '离线使用中，数据保存在本机';
      color = secondary;
      icon = CupertinoIcons.cloud;
    } else if (pending > 0) {
      label = '$pending 项待上传，点击重试';
      color = AppColors.warning.resolveFrom(context);
      icon = CupertinoIcons.arrow_up_circle;
    } else if (remote > 0) {
      label = '另一台设备修改了 $remote 条记录 · 查看';
      color = AppColors.warning.resolveFrom(context);
      icon = CupertinoIcons.person_2;
    } else if (store.lastSync != null) {
      final at = DateTime.tryParse(store.lastSync!)?.toLocal();
      if (at == null) {
        label = '已同步';
      } else {
        String two(int v) => v.toString().padLeft(2, '0');
        final today = DateTime.now();
        final sameDay =
            at.year == today.year &&
            at.month == today.month &&
            at.day == today.day;
        final stamp = sameDay
            ? '${two(at.hour)}:${two(at.minute)}'
            : '${at.month}月${at.day}日 ${two(at.hour)}:${two(at.minute)}';
        label = '已于 $stamp 同步';
      }
      color = success;
      icon = CupertinoIcons.checkmark_circle;
    } else {
      label = '数据保存在本机，点击查看同步状态';
      color = secondary;
      icon = CupertinoIcons.cloud;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.xs),
      padding: const EdgeInsets.only(left: Gap.sm, right: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(0, 36),
              onPressed: onTap,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: color),
                ),
              ),
            ),
          ),
          if (failed || pending > 0)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              minimumSize: const Size(0, 36),
              onPressed: () => retrySync(context, store),
              child: Text(
                '重试',
                style: AppType.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (unconfigured && onConfigure != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              minimumSize: const Size(0, 36),
              onPressed: onConfigure,
              child: Text(
                '去配置',
                style: AppType.caption.copyWith(
                  color: CupertinoColors.label.resolveFrom(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Manual retry used by the home status bar: pushes the pending queue and
/// reports the result inline, so a failed upload is never a silent dead end.
Future<void> retrySync(BuildContext context, Workspace store) async {
  final sync = store.sync;
  if (sync == null) {
    await message(context, '同步服务未启动', '请重新打开应用后再试。');
    return;
  }
  final ok = await sync.upload(manual: true);
  if (!context.mounted) return;
  if (!ok) {
    await message(
      context,
      '同步失败',
      sync.message.isEmpty ? '请检查网络与储存桶配置后重试。' : sync.message,
    );
  }
}

/// Cloud timestamps are stored as UTC ISO strings; show them in device time.
String formatSyncTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class SyncPage extends StatefulWidget {
  const SyncPage({
    super.key,
    required this.store,
    required this.onSettings,
    this.onStorageSettings,
  });
  final Workspace store;
  final VoidCallback onSettings;
  final VoidCallback? onStorageSettings;
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  bool checking = false;
  bool syncing = false;
  SyncStatusSummary get summary => syncSummary(widget.store);
  Future<void> check() async {
    if (checking) return;
    setState(() => checking = true);
    final storage = await _storage();
    final result = storage == null
        ? const Failure<int>('还没有配置储存桶地址和密钥')
        : await storage.probe();
    if (!mounted) return;
    setState(() => checking = false);
    await message(
      context,
      result is Success ? '储存桶连接正常' : '储存桶连接失败',
      result is Success
          ? ((result as Success<int>).value == 404
                ? '签名请求已通过，桶内还没有 index.json。首次同步会自动创建。'
                : '签名请求已通过，可以开始同步。')
          : (result as Failure).message,
    );
  }

  Future<CosObjectStorage?> _storage() async {
    const secure = FlutterSecureStorage();
    return CosObjectStorage.fromSettings(
      widget.store.settings,
      await secure.read(key: 'storage_id') ?? '',
      await secure.read(key: 'storage_key') ?? '',
      token: await secure.read(key: 'storage_token') ?? '',
    );
  }

  Future<void> sync() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      final service = widget.store.sync;
      if (service == null) throw const FormatException('同步服务未启动');
      // Same path as pull-to-refresh: push pending edits, then compare the
      // remote manifest before pulling, so 「立即同步」 never silently replaces
      // local work with an older cloud copy.
      final outcome = await service.refresh();
      if (!mounted) return;
      await message(context, outcome.ok ? '同步完成' : '同步失败', outcome.message);
    } on Object catch (e) {
      widget.store.syncMessage = '同步失败';
      if (mounted) await message(context, '同步失败', '$e');
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (syncing) return const SyncSkeletonPage();
    final s = summary;
    final pending = widget.store.pendingDays.toList()..sort();
    final conflictDays =
        widget.store.remoteEntries.map((e) => e.day).toSet().toList()..sort();
    return Screen(
      title: '同步中心',
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
          EmptyState(
            icon: CupertinoIcons.cloud,
            title: '暂无待同步变更',
            message: s.kind == SyncStatusKind.unconfigured
                ? '新增人员或登记后，本地变化会出现在这里。'
                : '保存后会自动上传，这里只保留上传失败的变更。',
          ),
        const SizedBox(height: 18),
        if (s.kind == SyncStatusKind.unconfigured)
          const Text(
            '还没填存储桶直链与密钥。填好后每次保存都会自动上传，失败也不会丢数据。',
            style: TextStyle(
              color: CupertinoColors.secondaryLabel,
              fontSize: 13,
            ),
          ),
      ],
    );
  }

  Widget _statusCard(BuildContext context, SyncStatusSummary s) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final tertiary = CupertinoColors.tertiaryLabel.resolveFrom(context);
    final provider = (widget.store.settings['provider'] ?? '未配置').toString();
    final lastSync = widget.store.lastSync == null
        ? '尚未同步'
        : formatSyncTime(widget.store.lastSync!);
    final notice = widget.store.notices['lastResult']?.toString() ?? '尚未检查通知';
    final autoUpload = widget.store.sync;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: .13),
                  shape: BoxShape.circle,
                ),
                child: Icon(s.icon, color: s.color, size: 22),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.detail,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.count > 0)
                Container(
                  margin: const EdgeInsets.only(left: Gap.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '${s.count}',
                    style: TextStyle(
                      color: s.color,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Container(height: .5, color: separatorOf(context)),
          const SizedBox(height: Gap.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fact(context, '存储服务', provider, tertiary),
              _factDivider(context),
              _fact(context, '最近同步', lastSync, tertiary),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Icon(
                autoUpload?.phase == SyncPhase.failed
                    ? CupertinoIcons.exclamationmark_circle
                    : CupertinoIcons.arrow_up_circle,
                size: 12,
                color: autoUpload?.phase == SyncPhase.failed
                    ? AppColors.danger.resolveFrom(context)
                    : tertiary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  autoUpload == null ? '自动上传：未启用' : '自动上传：${autoUpload.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: autoUpload?.phase == SyncPhase.failed
                        ? AppColors.danger.resolveFrom(context)
                        : secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxs),
          Row(
            children: [
              Icon(CupertinoIcons.bell, size: 12, color: tertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '通知：$notice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          PrimaryButton(
            onPressed: syncing ? null : sync,
            child: const Text('立即同步'),
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Expanded(
                child: _toolTile(
                  context,
                  label: '配置储存桶',
                  icon: CupertinoIcons.cloud,
                  onTap: widget.onStorageSettings ?? widget.onSettings,
                ),
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: _toolTile(
                  context,
                  label: checking ? '测试中…' : '测试连接',
                  icon: CupertinoIcons.wifi,
                  onTap: checking ? null : check,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Center(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 6),
              onPressed: () =>
                  refreshNotices(context, widget.store, quietWhenIdle: true),
              child: Text(
                '检查通知与更新',
                style: AppType.caption.copyWith(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fact(
    BuildContext context,
    String label,
    String value,
    Color tertiary,
  ) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            letterSpacing: .2,
            color: tertiary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ],
    ),
  );

  Widget _factDivider(BuildContext context) => Container(
    width: .5,
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: Gap.md),
    color: separatorOf(context),
  );

  Widget _toolTile(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: .6,
      onPressed: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.raised.resolveFrom(context),
          borderRadius: BorderRadius.circular(Radii.field),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: Sizes.iconSmall, color: secondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppType.caption.copyWith(
                color: CupertinoColors.label.resolveFrom(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
