import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/update/apk_downloader.dart';
import '../../../core/update/release_update_checker.dart';
import '../../../core/update/update_config.dart';
import '../../../core/update/update_platform.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/markdown.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/ui.dart';

Future<void> checkForUpdates(
  BuildContext context,
  Workspace store, {
  bool automatic = false,
  ReleaseUpdateChecker? checker,
}) async {
  final current = await UpdatePlatform.version();
  final catalog = await (checker ?? ReleaseUpdateChecker()).check(
    store.settings,
  );
  final latest = catalog.latest;
  final summary = latest == null
      ? catalog.errors.isEmpty
            ? '仓库尚未发布正式版本'
            : '检查更新失败，请检查网络或仓库地址'
      : compareVersions(latest.version, current) > 0
      ? '发现新版本 ${latest.version}'
      : '当前版本 $current，未发现更新版本';
  store.settings['updateLastCheck'] = DateTime.now().toUtc().toIso8601String();
  store.settings['updateLastResult'] = summary;
  await store.persist();
  if (!context.mounted) return;
  if (latest != null && compareVersions(latest.version, current) > 0) {
    await showUpdatePanel(
      context,
      store,
      catalog: catalog,
      currentVersion: current,
    );
  } else if (automatic) {
    // A background check must not interrupt the roster: the result is stored
    // in settings and shown on the update page when the administrator asks.
  } else {
    await showMessageSheet(
      context,
      latest == null || catalog.errors.isNotEmpty ? '检查更新' : '已是最新版本',
      '$summary${latest == null && catalog.errors.isEmpty ? '，发布安装包后即可在这里选择来源与架构。' : ''}'
      '${catalog.errors.isEmpty ? '' : '\n\n${catalog.errors.entries.map((e) => '${e.key}：${e.value}').join('\n')}'}',
      icon: CupertinoIcons.arrow_down_circle,
    );
  }
}

Future<void> showUpdatePanel(
  BuildContext context,
  Workspace store, {
  required UpdateCatalog catalog,
  required String currentVersion,
}) => showAppSheet<void>(
  context,
  (_) => UpdatePanel(
    store: store,
    catalog: catalog,
    currentVersion: currentVersion,
  ),
  barrierDismissible: false,
);

class UpdatePanel extends StatefulWidget {
  const UpdatePanel({
    super.key,
    required this.store,
    required this.catalog,
    required this.currentVersion,
  });
  final Workspace store;
  final UpdateCatalog catalog;
  final String currentVersion;
  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  late final target = widget.catalog.latest!;
  late final mirrors = widget.catalog.mirrors(target.version);
  late String source = mirrors.containsKey('Gitee') ? 'Gitee' : target.source;
  String architecture = 'arm64-v8a';
  late bool useProxy = widget.store.settings['updateUseProxy'] != false;
  bool busy = false;
  int received = 0, total = -1;
  String error = '';
  File? downloaded;
  final downloader = ApkDownloader();
  ReleaseAsset? get asset => mirrors[source]?.assets[architecture];

  @override
  void dispose() {
    downloader.cancel();
    super.dispose();
  }

  Future<void> selectSource() async {
    final value = await choose(
      context,
      '选择下载源',
      {
        'Gitee': 'Gitee',
        'GitHub': 'GitHub',
        if (mirrors.containsKey('自建服务')) '自建服务': '自建服务',
      },
      selected: {source},
      disabled: {
        for (final s in ['Gitee', 'GitHub'])
          if (!mirrors.containsKey(s)) s,
      },
      details: {
        for (final s in ['Gitee', 'GitHub', '自建服务'])
          s: mirrors.containsKey(s)
              ? 'V${target.version}${s == 'Gitee' ? ' · 默认优先' : ''}'
              : '该源尚未发布此版本',
      },
      fallbackIcon: CupertinoIcons.cloud_download,
    );
    if (value != null && mounted) {
      setState(() {
        source = value;
        downloaded = null;
        error = '';
      });
    }
  }

  Future<void> selectArchitecture() async {
    final value = await choose(
      context,
      '选择安装包架构',
      {
        'arm64-v8a': 'arm64-v8a',
        'armeabi-v7a': 'armeabi-v7a',
        'x86_64': 'x86_64',
      },
      selected: {architecture},
      disabled: {
        for (final abi in UpdateDefaults.architectures)
          if (!mirrors[source]!.assets.containsKey(abi)) abi,
      },
      details: {
        for (final abi in UpdateDefaults.architectures)
          abi: !mirrors[source]!.assets.containsKey(abi)
              ? '该源未提供此架构'
              : abi == 'arm64-v8a'
              ? '默认 · 64 位 ARM 手机'
              : abi == 'armeabi-v7a'
              ? '32 位 ARM 设备'
              : '64 位 x86 设备',
      },
      fallbackIcon: CupertinoIcons.device_phone_portrait,
    );
    if (value != null && mounted) {
      setState(() {
        architecture = value;
        downloaded = null;
        error = '';
      });
    }
  }

  Future<void> selectProxy() async {
    final settings = widget.store.settings;
    final value = await choose(
      context,
      '选择 GitHub 下载代理',
      {
        for (var i = 0; i < 3; i++)
          i: Uri.parse(UpdateDefaults.proxy(settings, i)).host,
      },
      selected: {UpdateDefaults.proxyIndex(settings)},
      fallbackIcon: CupertinoIcons.globe,
    );
    if (value != null && mounted) {
      settings['updateProxyIndex'] = value;
      await widget.store.persist();
      if (mounted) setState(() {});
    }
  }

  Future<void> downloadOrInstall() async {
    if (busy || asset == null) return;
    setState(() {
      busy = true;
      error = '';
      received = 0;
      total = -1;
    });
    try {
      final uri = UpdateDefaults.downloadUri(
        asset!.url,
        source: source,
        useProxy: useProxy,
        settings: widget.store.settings,
      );
      downloaded ??= await downloader.download(
        asset!,
        uri,
        onProgress: (r, t) {
          if (mounted) {
            setState(() {
              received = r;
              total = t;
            });
          }
        },
      );
      if (!mounted) return;
      final opened = await UpdatePlatform.install(downloaded!.path);
      if (mounted && !opened) {
        setState(() => error = '请在系统页面允许安装应用，返回后点击「安装更新」。');
      }
    } on UpdateCancelled {
      if (mounted) setState(() => error = '下载已取消，可重新下载。');
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message.toString()
              : e is PlatformException
              ? e.message ?? '无法打开系统安装器'
              : '下载失败，请检查网络，或更换下载源和代理后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return PopScope(
      canPop: !busy,
      child: SheetPanel(
        title: '发现新版本',
        subtitle: '${widget.currentVersion} → ${target.version}',
        titleIcon: CupertinoIcons.arrow_down_circle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (target.body.trim().isNotEmpty) ...[
              MarkdownView(target.body, baseSize: 14),
              const SizedBox(height: 18),
            ],
            SettingsGroup(
              children: [
                SettingRow(
                  '下载源',
                  detail: source,
                  onTap: busy ? null : selectSource,
                ),
                SettingRow(
                  '安装包架构',
                  detail:
                      '$architecture${architecture == 'arm64-v8a' ? ' · 默认' : ''}',
                  onTap: busy ? null : selectArchitecture,
                ),
                if (source == 'GitHub') ...[
                  SettingRow(
                    '使用代理链接下载',
                    detail: '仅代理 GitHub 安装包下载',
                    onTap: busy
                        ? null
                        : () async {
                            setState(() {
                              useProxy = !useProxy;
                              error = '';
                            });
                            widget.store.settings['updateUseProxy'] = useProxy;
                            await widget.store.persist();
                          },
                    trailing: Icon(
                      useProxy
                          ? CupertinoIcons.checkmark_square_fill
                          : CupertinoIcons.square,
                      color: useProxy
                          ? AppColors.accent.resolveFrom(context)
                          : secondary,
                      size: 23,
                    ),
                  ),
                  if (useProxy)
                    SettingRow(
                      '下载代理',
                      detail: Uri.parse(
                        UpdateDefaults.proxy(widget.store.settings),
                      ).host,
                      onTap: busy ? null : selectProxy,
                    ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              asset?.name ?? '此下载源未提供 $architecture，请选择其他架构或下载源。',
              style: AppType.caption.copyWith(color: secondary),
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => Container(
                  height: 4,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: AppColors.raised.resolveFrom(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Container(
                    width: total > 0
                        ? constraints.maxWidth * (received / total).clamp(0, 1)
                        : 0,
                    color: AppColors.accent.resolveFrom(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                total > 0
                    ? '${(received / total * 100).toStringAsFixed(0)}% · ${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB'
                    : received > 0
                    ? '已下载 ${(received / 1048576).toStringAsFixed(1)} MB'
                    : '正在连接下载源…',
                style: AppType.caption.copyWith(color: secondary),
              ),
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: AppType.rowDetail.copyWith(
                    color: AppColors.danger.resolveFrom(context),
                  ),
                ),
              ),
          ],
        ),
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                onPressed: busy || asset == null ? null : downloadOrInstall,
                child: Text(
                  busy
                      ? '正在下载'
                      : downloaded != null
                      ? '安装更新'
                      : '下载更新',
                ),
              ),
              CupertinoButton(
                onPressed: () {
                  if (busy) {
                    downloader.cancel();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(
                  busy ? '取消下载' : '稍后再说',
                  style: AppType.rowDetail.copyWith(color: secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
