import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/data/workspace.dart';
import '../../../core/data/spreadsheet_io.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/licenses_screen.dart';
import '../../../core/config/bucket_address.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final Workspace store;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Workspace get store => widget.store;
  final secure = const FlutterSecureStorage();
  String get provider => store.settings['provider'] as String? ?? 'COS';
  bool get nativeCloud => provider == 'OSS' || provider == 'COS';
  Future<void> editBucketUrl() async {
    final selectedProvider = provider;
    final value = await input(
      context,
      '存储桶直链',
      value: BucketAddress.configuredUrl(store.settings, selectedProvider),
    );
    if (value == null || !mounted) return;
    await guarded(context, () async {
      final normalized = value.isEmpty
          ? ''
          : BucketAddress.parse(selectedProvider, value).url.toString();
      store.settings[BucketAddress.settingKey(selectedProvider)] = normalized;
      await store.persist();
    });
  }

  Future<void> edit(String key, String title, {bool url = false}) async {
    final value = await input(
      context,
      title,
      value: store.settings[key]?.toString() ?? '',
    );
    if (value == null || !mounted) return;
    if (url &&
        value.isNotEmpty &&
        (Uri.tryParse(value)?.scheme != 'https' ||
            Uri.tryParse(value)?.host.isEmpty == true)) {
      await message(context, '地址无效', '请输入完整 HTTPS 地址。');
      return;
    }
    await guarded(context, () async {
      store.settings[key] = value;
      await store.persist();
    });
  }

  Future<void> identity() async {
    final value = await input(context, '本地显示名', value: store.identity);
    if (value == null || !mounted) return;
    if (value.isEmpty) {
      await message(context, '显示名不能为空', '每次登记都需要记录修改人。');
      return;
    }
    await guarded(context, () => store.setIdentity(value));
  }

  Future<void> people() async => Navigator.of(
    context,
  ).push(CupertinoPageRoute<void>(builder: (_) => PeoplePage(store: store)));
  Future<void> credential(String key, String title) async {
    await guarded(context, () async {
      final old = await secure.read(key: key) ?? '';
      if (!mounted) return;
      final value = await input(context, title, value: old, secret: true);
      if (value != null) await secure.write(key: key, value: value);
    });
  }

  Future<void> probe() async => guarded(context, () async {
    final uri = Uri.tryParse(
      nativeCloud
          ? BucketAddress.configuredUrl(store.settings, provider)
          : store.settings['endpoint'] ?? '',
    );
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      await message(
        context,
        '未配置服务地址',
        nativeCloud ? '请先填写存储桶直链。' : '请先填写 HTTPS endpoint。',
      );
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .headUrl(uri)
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      if (mounted) {
        await message(
          context,
          '网络连通性检查',
          'HTTP ${response.statusCode}。这只验证地址连通，未验证密钥、存储桶权限或签名。',
        );
      }
    } finally {
      client.close(force: true);
    }
  });
  @override
  Widget build(BuildContext context) => Screen(
    title: '设置',
    children: [
      _group('本地身份', [
        SettingRow(
          '显示名',
          detail: store.identity.isEmpty ? '未填写 · 登记前必填' : store.identity,
          onTap: identity,
        ),
        SettingRow('设备标识', detail: store.deviceId),
      ]),
      _group('人员名单', [
        SettingRow(
          '人员管理',
          detail: '${store.activePeople.length} 名启用人员 · 手动新增 / 导入',
          onTap: people,
        ),
      ]),
      _group('对象存储', [
        SettingRow(
          '存储服务',
          detail: store.settings['provider'],
          onTap: () async {
            final v = await choose(context, '对象存储类型', {
              'OSS': '阿里云 OSS',
              'COS': '腾讯云 COS',
              'S3': 'S3 / MinIO',
            });
            if (v != null) {
              store.settings['provider'] = v;
              await store.persist();
            }
          },
        ),
        if (nativeCloud) ...[
          SettingRow(
            '存储桶直链',
            detail:
                BucketAddress.configuredUrl(store.settings, provider).isEmpty
                ? '未配置'
                : BucketAddress.configuredUrl(store.settings, provider),
            onTap: editBucketUrl,
          ),
          Text(
            provider == 'OSS'
                ? '例如 https://my-bucket.oss-cn-hangzhou.aliyuncs.com'
                : '例如 https://my-bucket-1250000000.cos.ap-guangzhou.myqcloud.com',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ] else ...[
          SettingRow(
            'Endpoint',
            detail: store.settings['endpoint'] ?? '未配置',
            onTap: () => edit('endpoint', '服务地址', url: true),
          ),
          SettingRow(
            'Bucket',
            detail: store.settings['bucket'] ?? '未配置',
            onTap: () => edit('bucket', '存储桶名称'),
          ),
        ],
        SettingRow(
          'AccessKeyId / SecretId',
          detail: '仅保存至系统安全存储',
          onTap: () => credential('storage_id', 'AccessKeyId / SecretId'),
        ),
        SettingRow(
          'SecretAccessKey / SecretKey',
          detail: '不会进入业务数据或日志',
          onTap: () => credential('storage_key', 'SecretAccessKey / SecretKey'),
        ),
        SettingRow('连接测试', detail: '仅检查地址连通性，不验证存储权限', onTap: probe),
      ]),
      _group('时间', [
        const SettingRow('业务时区', detail: 'Asia/Shanghai · UTC+08:00'),
        SettingRow(
          '网络时间服务',
          detail: store.settings['timeUrl'] ?? '未配置',
          onTap: () => edit('timeUrl', '时间服务 HTTPS 地址', url: true),
        ),
        const SettingRow('当前时间来源', detail: '本地回退 · 网络校时尚未启用'),
      ]),
      _group('自动更新', [
        for (final source in ['Gitee', 'GitHub', '自建服务'])
          SettingRow(
            '$source 更新地址',
            detail: store.settings['update_$source'] ?? '未配置',
            onTap: () => edit('update_$source', '$source 更新地址', url: true),
          ),
        SettingRow(
          '启动时检查（服务启用后生效）',
          detail: 'Gitee 优先，GitHub 备用',
          trailing: CupertinoSwitch(
            value: store.settings['autoUpdate'] == true,
            onChanged: (v) {
              store.settings['autoUpdate'] = v;
              store.persist();
            },
          ),
        ),
        SettingRow(
          '检查更新',
          detail: '当前仅保存更新源配置',
          onTap: () =>
              message(context, '更新服务待接入', '更新源配置已保存在本机。当前版本暂未启用版本检查、下载与安装。'),
        ),
      ]),
      _group('外观', [
        const SettingRow('主题', detail: '跟随系统 · 浅色 / 深色'),
        SettingRow(
          '轻毛玻璃',
          detail: '关闭可减少绘制开销；系统无障碍模式自动降级',
          trailing: CupertinoSwitch(
            value: store.settings['glass'] != false,
            onChanged: (v) {
              store.settings['glass'] = v;
              store.persist();
            },
          ),
        ),
        const GlassCard(child: Text('Aa  青鸾考勤 · 外观预览')),
      ]),
      _group('关于', [
        const SettingRow('青鸾考勤', detail: '1.0.0 · 本地优先'),
        SettingRow('数据目录', detail: store.dataPath),
        SettingRow(
          '开源许可',
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const LicensesScreen()),
          ),
        ),
      ]),
    ],
  );
  Widget _group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontSize: 13,
            ),
          ),
        ),
        GlassCard(child: Column(children: children)),
      ],
    ),
  );
}

class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key, required this.store});
  final Workspace store;
  Future<void> add(BuildContext context, {Person? person}) async {
    final value = await input(
      context,
      person == null ? '新增人员' : '编辑姓名',
      value: person?.name ?? '',
    );
    if (value != null && context.mounted) {
      await guarded(context, () => store.savePerson(value, person: person));
    }
  }

  Future<void> import(BuildContext context) async => guarded(context, () async {
    final preview = await pickPeople(store);
    if (preview == null || !context.mounted) return;
    final accepted = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (c) => CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(middle: Text('导入预览')),
          child: Screen(
            title: '新增 ${preview.names.length} 人',
            children: [
              const Text('仅新增名单，不覆盖现有人名、考勤和停用状态。同名与缺失姓名行将跳过。'),
              ...preview.issues.map(
                (s) => Text(
                  s,
                  style: const TextStyle(color: CupertinoColors.systemOrange),
                ),
              ),
              ...preview.names.map((s) => SettingRow(s)),
              CupertinoButton.filled(
                onPressed: preview.names.isEmpty
                    ? null
                    : () => Navigator.pop(c, true),
                child: const Text('确认导入'),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true) {
      for (final name in preview.names) {
        await store.savePerson(name);
      }
    }
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('人员名单')),
      child: Screen(
        title: '人员管理',
        children: [
          Wrap(
            children: [
              CupertinoButton.filled(
                onPressed: () => add(context),
                child: const Text('新增人员'),
              ),
              CupertinoButton(
                onPressed: () => import(context),
                child: const Text('导入 Excel / CSV'),
              ),
            ],
          ),
          const Text('文件首行需包含“姓名”列。支持 .xlsx 和 UTF-8 CSV。'),
          if (store.people.isEmpty)
            const EmptyState(
              icon: CupertinoIcons.person_2,
              title: '还没有人员',
              message: '手动新增或从表格导入开始。',
            ),
          ...store.people.map(
            (p) => GlassCard(
              child: Row(
                children: [
                  Expanded(
                    child: SettingRow(
                      p.name,
                      detail: p.active ? '启用中' : '已停用（历史保留）',
                      onTap: () => add(context, person: p),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: () => guarded(context, () async {
                      if (!p.active ||
                          await confirm(
                            context,
                            '停用 ${p.name}？',
                            '历史考勤将保留，停用后不再计入应登记人数。',
                          )) {
                        await store.togglePerson(p);
                      }
                    }),
                    child: Text(p.active ? '停用' : '启用'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
