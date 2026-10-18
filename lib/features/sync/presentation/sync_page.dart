import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/bucket_address.dart';
import '../../../core/data/workspace.dart';
import '../../../core/storage/cos_storage.dart';
import '../../../core/storage/object_storage.dart';
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
  return const SyncStatusSummary(
    kind: SyncStatusKind.ready,
    title: '本地数据已保存',
    detail: '没有待上传变更，云端同步服务尚未启用',
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
  bool syncing = false;
  SyncStatusSummary get summary => syncSummary(widget.store);
  Future<void> check() async {
    if (checking) return;
    setState(() => checking = true);
    final storage = await _storage();
    final result = storage == null
        ? const Failure<int>('请先配置 COS 地址和密钥')
        : await storage.probe();
    if (!mounted) return;
    setState(() => checking = false);
    await message(
      context,
      result is Success ? 'COS 连接成功' : 'COS 连接失败',
      result is Success
          ? ((result as Success<int>).value == 404
                ? '签名请求已通过，但桶内尚未创建 index.json。'
                : '签名请求已通过。')
          : (result as Failure).message,
    );
  }

  Future<CosObjectStorage?> _storage() async {
    const secure = FlutterSecureStorage();
    return CosObjectStorage.fromSettings(
      widget.store.settings,
      await secure.read(key: 'storage_id') ?? '',
      await secure.read(key: 'storage_key') ?? '',
    );
  }

  Future<void> sync() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      final storage = await _storage();
      if (storage == null) throw const FormatException('请先配置 COS 地址和密钥');
      final remote = await storage.get('data/workspace.json');
      if (remote is Success<RemoteObject?> &&
          remote.value != null &&
          widget.store.pendingDays.isEmpty) {
        try {
          final payload = jsonDecode(utf8.decode(remote.value!.bytes));
          if (payload is Map<String, dynamic>) {
            await widget.store.loadPayload(payload);
            widget.store.lastSync = DateTime.now().toUtc().toIso8601String();
            widget.store.syncMessage = '同步成功';
            if (mounted) await message(context, '同步成功', '已从腾讯云 COS 下载最新工作区数据。');
            return;
          }
        } on FormatException {
          // A malformed remote snapshot is reported by the upload path below.
        }
      }
      final payload = utf8.encode(jsonEncode(widget.store.toPayload()));
      final digest = sha256.convert(payload).toString();
      final put = await storage.put(
        'data/workspace.json',
        payload,
        sha256: digest,
      );
      if (put is Failure) throw Exception(put.message);
      final index = utf8.encode(
        jsonEncode({
          'schema': 1,
          'data': {
            'hash': digest,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
        }),
      );
      final indexResult = await storage.put(
        'index.json',
        index,
        sha256: sha256.convert(index).toString(),
      );
      if (indexResult is Failure) throw Exception(indexResult.message);
      widget.store.pendingDays.clear();
      widget.store.lastSync = DateTime.now().toUtc().toIso8601String();
      widget.store.syncMessage = '同步成功';
      await widget.store.persist();
      if (mounted) await message(context, '同步成功', '本机数据已上传到腾讯云 COS。');
    } on Object catch (e) {
      widget.store.syncMessage = '同步失败';
      if (mounted) await message(context, '同步失败', '$e');
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final pending = widget.store.pendingDays.toList()..sort();
    final conflictDays =
        widget.store.remoteEntries.map((e) => e.day).toSet().toList()..sort();
    return Screen(
      title: '同步中心',
      actions: [
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
          '已支持腾讯云 COS 签名上传。首次使用请在设置中填写存储桶直链和密钥。',
          style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13),
        ),
      ],
    );
  }

  Widget _statusCard(BuildContext context, SyncStatusSummary s) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final tertiary = CupertinoColors.tertiaryLabel.resolveFrom(context);
    final provider = (widget.store.settings['provider'] ?? '未配置').toString();
    final lastSync = widget.store.lastSync ?? '尚未同步';
    final notice = widget.store.notices['lastResult']?.toString() ?? '尚未检查通知';
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
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  onPressed: syncing ? null : sync,
                  child: const Text('立即同步'),
                ),
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: _tonalButton(
                  context,
                  label: checking ? '检查中…' : '立即检查',
                  icon: CupertinoIcons.refresh,
                  busy: checking,
                  onPressed: checking ? null : check,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Expanded(
                child: _toolTile(
                  context,
                  label: '配置存储',
                  icon: CupertinoIcons.cloud,
                  onTap: widget.onSettings,
                ),
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: _toolTile(
                  context,
                  label: '更新与通知',
                  icon: CupertinoIcons.bell,
                  onTap: () => refreshNotices(
                    context,
                    widget.store,
                    quietWhenIdle: true,
                  ),
                ),
              ),
            ],
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

  Widget _tonalButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool busy,
    VoidCallback? onPressed,
  }) {
    final disabled = onPressed == null;
    final color = disabled
        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    return CupertinoButton(
      minimumSize: const Size(0, Sizes.cta),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(Radii.control),
      pressedOpacity: .7,
      color: AppColors.raised.resolveFrom(context),
      disabledColor: AppColors.raised
          .resolveFrom(context)
          .withValues(alpha: .5),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            CupertinoActivityIndicator(radius: 8, color: color)
          else
            Icon(icon, size: Sizes.iconSmall, color: color),
          const SizedBox(width: 6),
          Text(label, style: AppType.button.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _toolTile(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
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
