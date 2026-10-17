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
  const SettingsPage({super.key, required this.store, this.section});
  final Workspace store;
  final String? section;
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
      final value = await input(
        context,
        title,
        value: old,
        secret: true,
        copyable: true,
      );
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Screen(
      title: widget.section ?? '设置',
      children: [
        if (widget.section == null) ...[
          _group('工作区', [
            SettingRow(
              '本地身份',
              detail: store.identity.isEmpty ? '设置登记时使用的显示名' : store.identity,
              onTap: () => openSection('本地身份'),
            ),
            SettingRow(
              '人员名单',
              detail: '${store.activePeople.length} 名启用人员',
              onTap: people,
            ),
          ]),
          _group('偏好与服务', [
            SettingRow(
              '外观',
              detail: themeLabel,
              onTap: () => openSection('外观'),
            ),
            SettingRow(
              '对象存储',
              detail: provider,
              onTap: () => openSection('对象存储'),
            ),
            SettingRow('时间', onTap: () => openSection('时间')),
            SettingRow('自动更新', onTap: () => openSection('自动更新')),
            SettingRow('数据导出', onTap: () => openSection('数据导出')),
          ]),
          _group('应用', [
            SettingRow(
              '关于',
              detail: '青鸾考勤 1.0.0',
              onTap: () => openSection('关于'),
            ),
          ]),
        ],
        if (widget.section == '本地身份')
          _group('本地身份', [
            SettingRow(
              '显示名',
              detail: store.identity.isEmpty ? '未填写 · 登记前必填' : store.identity,
              onTap: identity,
            ),
            SettingRow('设备标识', detail: store.deviceId),
          ]),
        if (widget.section == '人员名单')
          _group('人员名单', [
            SettingRow(
              '人员管理',
              detail: '${store.activePeople.length} 名启用人员 · 手动新增 / 导入',
              onTap: people,
            ),
          ]),
        if (widget.section == '对象存储')
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
                    BucketAddress.configuredUrl(
                      store.settings,
                      provider,
                    ).isEmpty
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
              onTap: () =>
                  credential('storage_key', 'SecretAccessKey / SecretKey'),
            ),
            SettingRow('连接测试', detail: '仅检查地址连通性，不验证存储权限', onTap: probe),
          ]),
        if (widget.section == '时间')
          _group('时间', [
            const SettingRow('业务时区', detail: 'Asia/Shanghai · UTC+08:00'),
            SettingRow(
              '网络时间服务',
              detail: store.settings['timeUrl'] ?? '未配置',
              onTap: () => edit('timeUrl', '时间服务 HTTPS 地址', url: true),
            ),
            const SettingRow('当前时间来源', detail: '本地回退 · 网络校时尚未启用'),
          ]),
        if (widget.section == '自动更新')
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
              onTap: () => message(
                context,
                '更新服务待接入',
                '更新源配置已保存在本机。当前版本暂未启用版本检查、下载与安装。',
              ),
            ),
          ]),
        if (widget.section == '外观')
          _group('外观', [
            SettingRow(
              '主题',
              detail: themeLabel,
              onTap: () async {
                final value = await choose(context, '外观模式', {
                  'system': '跟随系统',
                  'light': '浅色',
                  'dark': '深色',
                });
                if (value == null || !context.mounted) return;
                await guarded(context, () async {
                  store.settings['theme'] = value;
                  await store.persist();
                });
              },
            ),
            SettingRow(
              '首页卡片',
              detail: homeCardLabel,
              onTap: () async {
                final value = await choose(context, '首页卡片', {
                  'sync': '当前同步状态',
                  'today': '今日登记人数',
                });
                if (value != null) {
                  store.settings['homeCard'] = value;
                  await store.persist();
                }
              },
            ),
            SettingRow(
              '轻毛玻璃',
              detail: '仅用于浮动控件；关闭可进一步减少绘制开销',
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
        if (widget.section == '数据导出')
          _group('数据导出', [
            const Text('可导出 SQLite、Excel 或 CSV。移动端会打开系统分享面板。'),
            SettingRow(
              '导出 SQLite 文件',
              detail: '完整本地工作区',
              onTap: () => exportData('db'),
            ),
            SettingRow(
              '导出 Excel',
              detail: '全部有效考勤记录',
              onTap: () => exportData('xlsx'),
            ),
            SettingRow(
              '导出 CSV',
              detail: '全部有效考勤记录',
              onTap: () => exportData('csv'),
            ),
          ]),
        if (widget.section == '关于')
          _group('关于', [
            const SettingRow('青鸾考勤', detail: '1.0.0 · 本地优先'),
            SettingRow('数据目录', detail: store.dataPath),
            SettingRow(
              '开源许可',
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const LicensesScreen(),
                ),
              ),
            ),
          ]),
      ],
    ),
  );
  String get themeLabel => switch (store.settings['theme']) {
    'light' => '浅色',
    'dark' => '深色',
    _ => '跟随系统',
  };
  String get homeCardLabel =>
      store.settings['homeCard'] == 'today' ? '今日登记人数' : '当前同步状态';
  Future<void> exportData(String kind) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    await guarded(context, () async {
      final result = switch (kind) {
        'db' => await saveDatabase(store, origin),
        'csv' => await saveCsv(store, store.liveEntries, origin),
        _ => await saveWorkbook(
          store,
          store.liveEntries,
          exportColumns,
          origin,
        ),
      };
      if (result != null && mounted) await message(context, '导出已生成', result);
    });
  }

  void openSection(String section) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => SettingsPage(store: store, section: section),
    ),
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

  Future<void> options(BuildContext context, Person person) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: Text(person.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c, 'edit'),
            child: const Text('编辑姓名'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c, 'toggle'),
            child: Text(person.active ? '停用人员' : '启用人员'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(c, 'delete'),
            child: const Text('删除人员'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c),
          child: const Text('取消'),
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      await add(context, person: person);
      return;
    }
    await guarded(context, () async {
      if (action == 'delete') {
        if (await confirm(
          context,
          '删除 ${person.name}？',
          '将从名单中移除，已有考勤与姓名保留，可在历史记录中查询。',
        )) {
          await store.deletePerson(person);
        }
      } else if (!person.active ||
          await confirm(
            context,
            '停用 ${person.name}？',
            '历史考勤保留，停用后不再计入应登记人数。',
          )) {
        await store.togglePerson(person);
      }
    });
  }

  Future<void> import(BuildContext context) async => guarded(context, () async {
    final preview = await pickPeople(store);
    if (preview == null || !context.mounted) return;
    final accepted = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (c) => CupertinoPageScaffold(
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
      if (!context.mounted) return;
      final hasDuplicates = preview.issues.any((s) => s.contains('重名'));
      if (hasDuplicates) {
        final choice = await choose(context, '发现重复人员', {
          'copy': '作为副本保存（自动追加数字）',
          'skip': '不保存重复项',
        });
        if (!context.mounted) return;
        if (choice != 'copy') return;
      }
      for (final name in preview.names) {
        await store.savePerson(
          name,
          gender: preview.gender[name] ?? '',
          employeeId: preview.employeeIds[name] ?? '',
        );
      }
    }
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => CupertinoPageScaffold(
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
              CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => PeopleBatchPage(store: store),
                  ),
                ),
                child: const Text('批量编辑'),
              ),
            ],
          ),
          const Text('文件首行需包含“姓名”列。支持 .xlsx 和 UTF-8 CSV。'),
          const Text('支持带表头或无表头模板：第一列姓名（可选）、第二列性别（可选）、第三列工号（可选）。重名行会在导入预览中提示。'),
          if (store.visiblePeople.isEmpty)
            const EmptyState(
              icon: CupertinoIcons.person_2,
              title: '还没有人员',
              message: '手动新增或从表格导入开始。',
            ),
          ...store.visiblePeople.map(
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
                    padding: EdgeInsets.zero,
                    onPressed: () => options(context, p),
                    child: Icon(
                      CupertinoIcons.ellipsis,
                      semanticLabel: '${p.name}的选项',
                    ),
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

class PeopleBatchPage extends StatefulWidget {
  const PeopleBatchPage({super.key, required this.store});
  final Workspace store;
  @override
  State<PeopleBatchPage> createState() => _PeopleBatchPageState();
}

class _PeopleBatchPageState extends State<PeopleBatchPage> {
  final selected = <String>{};
  Future<void> edit() async {
    if (selected.isEmpty) return;
    final gender = await choose(context, '批量设置性别', {
      '': '不修改',
      '男': '男',
      '女': '女',
      '其他': '其他',
    });
    if (gender == null) return;
    await widget.store.updatePeople(
      widget.store.visiblePeople.where((p) => selected.contains(p.id)).toList(),
      gender: gender.isEmpty ? null : gender,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Screen(
      title: '批量编辑人员',
      children: [
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                onPressed: () => setState(
                  () => selected.addAll(
                    widget.store.visiblePeople.map((p) => p.id),
                  ),
                ),
                child: const Text('全选'),
              ),
            ),
            Expanded(
              child: CupertinoButton(
                onPressed: () => setState(selected.clear),
                child: const Text('清除'),
              ),
            ),
            Expanded(
              child: CupertinoButton.filled(
                onPressed: edit,
                child: const Text('编辑'),
              ),
            ),
          ],
        ),
        Text('已选 ${selected.length} 人'),
        ...widget.store.visiblePeople.map(
          (p) => SettingRow(
            p.name,
            detail: [
              p.gender,
              p.employeeId,
            ].where((s) => s.isNotEmpty).join(' · '),
            onTap: () => setState(
              () => selected.contains(p.id)
                  ? selected.remove(p.id)
                  : selected.add(p.id),
            ),
            trailing: Icon(
              selected.contains(p.id)
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
            ),
          ),
        ),
      ],
    ),
  );
}
