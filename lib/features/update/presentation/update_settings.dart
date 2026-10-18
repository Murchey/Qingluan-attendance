import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/update/release_update_checker.dart';
import '../../../core/update/update_config.dart';
import '../../../core/update/update_platform.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/toast.dart';
import '../../../core/widgets/ui.dart';
import 'update_panel.dart';

class UpdateSettingsSection extends StatefulWidget {
  const UpdateSettingsSection({super.key, required this.store});
  final Workspace store;
  @override
  State<UpdateSettingsSection> createState() => _UpdateSettingsSectionState();
}

class _UpdateSettingsSectionState extends State<UpdateSettingsSection> {
  bool checking = false;
  String version = '';
  Workspace get store => widget.store;

  @override
  void initState() {
    super.initState();
    UpdatePlatform.version().then((v) {
      if (mounted) setState(() => version = v);
    });
  }

  Future<void> editRepository(String source) async {
    final value = await input(
      context,
      '$source 更新地址',
      value: UpdateDefaults.repository(store.settings, source),
      hint: source == '自建服务' ? '版本信息 JSON 的 HTTPS 地址' : '仓库主页 HTTPS 地址',
    );
    if (value == null || !mounted) return;
    await guarded(context, () async {
      if (value.isNotEmpty) ReleaseUpdateChecker.endpoint(source, value);
      store.settings['update_$source'] = value.isNotEmpty
          ? value
          : source == 'Gitee'
          ? UpdateDefaults.gitee
          : source == 'GitHub'
          ? UpdateDefaults.github
          : '';
      await store.persist();
    });
  }

  Future<void> editProxy(int index) async {
    final value = await input(
      context,
      '代理 ${index + 1} 地址',
      value: UpdateDefaults.proxy(store.settings, index),
      hint: '只填写 HTTPS 代理前缀',
    );
    if (value == null || !mounted) return;
    await guarded(context, () async {
      store.settings['updateProxy$index'] = UpdateDefaults.normalizeProxy(
        value.isEmpty ? UpdateDefaults.proxies[index] : value,
      );
      await store.persist();
    });
  }

  Future<void> selectProxy() async {
    final index = await choose(
      context,
      '默认下载代理',
      {
        for (var i = 0; i < 3; i++)
          i: Uri.parse(UpdateDefaults.proxy(store.settings, i)).host,
      },
      selected: {UpdateDefaults.proxyIndex(store.settings)},
      fallbackIcon: CupertinoIcons.globe,
    );
    if (index != null && mounted) {
      store.settings['updateProxyIndex'] = index;
      await store.persist();
    }
  }

  Future<void> check() async {
    if (checking) return;
    setState(() => checking = true);
    try {
      await checkForUpdates(context, store);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  /// Developer shortcut: open the real update panel with a fake release so the
  /// layout, mirror list and architecture picker can be reviewed without
  /// publishing a repository release.
  Future<void> showMockUpdate() async {
    final current = await UpdatePlatform.version();
    if (!mounted) return;
    const version = '9.9.9';
    AppRelease release(String source) => AppRelease(
      version: version,
      source: source,
      title: '模拟更新 V$version',
      body: '''## 模拟更新 V$version

- 这是开发者选项生成的测试数据，不会请求更新仓库
- 可检查下载源、安装包架构与 Markdown 排版
- **请勿点击下载**：示例下载地址不可用''',
      assets: {
        for (final abi in UpdateDefaults.architectures)
          abi: ReleaseAsset(
            name: UpdateDefaults.apkName(version, abi),
            url: Uri.parse(
              'https://example.com/$source/${UpdateDefaults.apkName(version, abi)}',
            ),
            size: 20 * 1024 * 1024,
          ),
      },
    );
    await showUpdatePanel(
      context,
      store,
      catalog: UpdateCatalog(
        releases: [release('Gitee'), release('GitHub')],
        errors: const {},
      ),
      currentVersion: current,
    );
  }

  Widget group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupLabel(title),
        SettingsGroup(children: children),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      group('版本与检查', [
        SettingRow('当前版本', detail: version.isEmpty ? '正在读取…' : 'V$version'),
        SettingRow(
          '启动时检查更新',
          detail: '仅冷启动检查，有新版本时显示底部面板',
          trailing: CupertinoSwitch(
            value: store.settings['autoUpdate'] != false,
            onChanged: (value) async {
              store.settings['autoUpdate'] = value;
              await store.persist();
            },
          ),
        ),
        SettingRow(
          '检查更新',
          detail:
              store.settings['updateLastResult']?.toString() ??
              'Gitee 优先，同版本也可选择 GitHub 下载',
          trailing: checking ? const CupertinoActivityIndicator() : null,
          onTap: checking ? null : check,
        ),
      ]),
      group('更新仓库与下载源', [
        for (final source in ['Gitee', 'GitHub', '自建服务'])
          SettingRow(
            '$source 更新地址',
            detail: UpdateDefaults.repository(store.settings, source).isEmpty
                ? '未配置 · 可选'
                : UpdateDefaults.repository(store.settings, source),
            onTap: () => editRepository(source),
          ),
      ]),
      group('GitHub 下载代理', [
        SettingRow(
          '默认使用代理链接下载',
          detail: '更新面板选择 GitHub 时默认勾选',
          trailing: CupertinoSwitch(
            value: store.settings['updateUseProxy'] != false,
            onChanged: (value) async {
              store.settings['updateUseProxy'] = value;
              await store.persist();
            },
          ),
        ),
        SettingRow(
          '默认代理',
          detail: Uri.parse(UpdateDefaults.proxy(store.settings)).host,
          onTap: selectProxy,
        ),
        for (var i = 0; i < 3; i++)
          SettingRow(
            '代理 ${i + 1} 地址',
            detail: UpdateDefaults.proxy(store.settings, i),
            onTap: () => editProxy(i),
          ),
      ]),
      group('开发者选项', [
        SettingRow(
          '测试更新弹窗',
          detail: '模拟 V9.9.9，不请求仓库',
          onTap: showMockUpdate,
        ),
        SettingRow(
          '测试检查失败提示',
          detail: '显示两个更新仓库都失败时的 Toast',
          onTap: () => showToast(
            context,
            '检查更新失败，请检查网络或仓库地址',
            icon: CupertinoIcons.wifi_exclamationmark,
          ),
        ),
      ]),
      Text(
        '安装包默认选择 arm64-v8a。下载前可更改架构、下载源和 GitHub 代理；代理前缀后会自动追加原始下载地址。',
        style: AppType.footnoteStyle.copyWith(
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    ],
  );
}
