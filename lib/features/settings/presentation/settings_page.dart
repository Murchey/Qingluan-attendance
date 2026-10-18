import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/legal_text.dart';
import '../../../core/data/workspace.dart';
import '../../../core/update/update_config.dart';
import '../../legal/presentation/legal_page.dart';
import '../../../core/data/spreadsheet_io.dart';
import '../../../core/widgets/link_sheet.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/licenses_screen.dart';
import '../../../core/config/bucket_address.dart';
import '../../../core/storage/cos_storage.dart';
import '../../../core/result/app_result.dart';
import '../../leave/presentation/leave_page.dart';
import '../../notice/presentation/notice_panel.dart';
import '../../stats/domain/attendance_score.dart';
import '../../stats/presentation/score_rules_page.dart';
import '../../update/presentation/update_settings.dart';

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
    if (provider == 'COS') {
      final id = await secure.read(key: 'storage_id') ?? '';
      final key = await secure.read(key: 'storage_key') ?? '';
      final token = await secure.read(key: 'storage_token') ?? '';
      final storage = CosObjectStorage.fromSettings(
        store.settings,
        id,
        key,
        token: token,
      );
      if (storage == null) {
        if (!mounted) return;
        await message(context, '未配置服务地址', '请先填写 COS 存储桶直链。');
        return;
      }
      final result = await storage.probe();
      if (!mounted) return;
      await message(
        context,
        result is Success ? 'COS 连接成功' : 'COS 连接失败',
        result is Success
            ? ((result as Success<int>).value == 404
                  ? '签名请求已通过，但桶内尚未创建 index.json。'
                  : '已完成签名请求，存储桶可访问。')
            : (result as Failure).message,
      );
      return;
    }
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
          _group('工作区', inset: 58, [
            _row(
              context,
              '本地身份',
              detail: store.identity.isEmpty ? '设置登记时使用的显示名' : store.identity,
              icon: CupertinoIcons.person_crop_circle,
              onTap: () => openSection('本地身份'),
            ),
            _row(
              context,
              '人员名单',
              detail: '${store.activePeople.length} 名启用人员',
              icon: CupertinoIcons.person_2,
              onTap: people,
            ),
            _row(
              context,
              '请假记录',
              detail:
                  '${store.leavesOn(businessDay()).length} 人今日请假 · '
                  '共 ${store.liveLeaves.length} 条',
              icon: CupertinoIcons.calendar_badge_minus,
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => LeavePage(store: store),
                ),
              ),
            ),
            _row(
              context,
              '考勤扣分规则',
              detail: scoreRulesOf(store).summary,
              icon: CupertinoIcons.chart_bar_alt_fill,
              onTap: () => openScoreRules(context, store),
            ),
            _row(
              context,
              '班次时间',
              detail: store.shift.label,
              icon: CupertinoIcons.clock_fill,
              onTap: () => openSection('班次'),
            ),
          ]),
          _group('偏好与服务', inset: 58, [
            _row(
              context,
              '外观',
              detail: themeLabel,
              icon: CupertinoIcons.paintbrush,
              onTap: () => openSection('外观'),
            ),
            _row(
              context,
              '通知',
              detail: store.notices['lastResult']?.toString() ?? '尚未检查通知',
              icon: CupertinoIcons.bell,
              onTap: () => openSection('通知'),
            ),
            SettingRow(
              '保存后自动上传',
              detail: store.sync == null
                  ? '同步服务未启动'
                  : store.settings['autoUpload'] != false
                  ? '每次保存后自动上传到对象存储'
                  : '已关闭：只保存在本机，需手动同步',
              leading: IconBadge(
                icon: CupertinoIcons.arrow_up_circle,
                tint: CupertinoDynamicColor.resolve(AppColors.navy, context),
              ),
              trailing: CupertinoSwitch(
                value: store.settings['autoUpload'] != false,
                onChanged: (v) {
                  store.settings['autoUpload'] = v;
                  store.persist();
                },
              ),
            ),
            _row(
              context,
              '对象存储',
              detail: provider,
              icon: CupertinoIcons.cloud,
              onTap: () => openSection('对象存储'),
            ),
            _row(
              context,
              '时间',
              icon: CupertinoIcons.clock,
              onTap: () => openSection('时间'),
            ),
            _row(
              context,
              '自动更新',
              icon: CupertinoIcons.arrow_down_circle,
              onTap: () => openSection('自动更新'),
            ),
            _row(
              context,
              '数据导出',
              icon: CupertinoIcons.square_arrow_up,
              onTap: () => openSection('数据导出'),
            ),
          ]),
          _group('应用', inset: 58, [
            _row(
              context,
              '关于',
              detail: '青鸾考勤 1.0.0',
              icon: CupertinoIcons.info_circle,
              onTap: () => openSection('关于'),
            ),
          ]),
        ],
        if (widget.section == '班次')
          _group('班次', [
            SettingRow(
              '上班时间',
              detail: store.shift.start,
              onTap: () async {
                final picked = await showTimePickSheet(
                  context,
                  title: '上班时间',
                  initial: store.shift.start,
                  presets: const ['08:00', '08:30', '09:00'],
                );
                if (picked == null) return;
                await store.setShift(store.shift.copyWith(start: picked));
              },
            ),
            SettingRow(
              '下班时间',
              detail: store.shift.end,
              onTap: () async {
                final picked = await showTimePickSheet(
                  context,
                  title: '下班时间',
                  initial: store.shift.end,
                  presets: const ['17:30', '18:00', '18:30'],
                );
                if (picked == null) return;
                await store.setShift(store.shift.copyWith(end: picked));
              },
            ),
            SettingRow(
              '迟到宽限',
              detail: store.shift.graceMinutes == 0
                  ? '不宽限'
                  : '${store.shift.graceMinutes} 分钟',
              onTap: () async {
                final value = await choose<int>(
                  context,
                  '迟到宽限',
                  const {0: '不宽限', 5: '5 分钟', 10: '10 分钟', 15: '15 分钟', 30: '30 分钟'},
                  subtitle: '超过上班时间加宽限即判定迟到',
                );
                if (value == null) return;
                await store.setShift(
                  store.shift.copyWith(graceMinutes: value),
                );
              },
            ),
            const SettingRow(
              '状态推导',
              detail: '签到晚于上班时间即迟到，签退早于下班时间即早退',
            ),
          ]),
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
            SettingRow(
              'SecurityToken（临时密钥可选）',
              detail: '仅临时 STS 密钥需要，保存至系统安全存储',
              onTap: () => credential('storage_token', 'SecurityToken'),
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
        if (widget.section == '自动更新') UpdateSettingsSection(store: store),
        if (widget.section == '通知')
          _group('通知', [
            SettingRow(
              '管理员通知',
              detail: store.noticeBody('admin').isEmpty
                  ? '尚未收到管理员通知'
                  : (store.noticeTitle('admin').isEmpty
                        ? '已收到，点按查看'
                        : store.noticeTitle('admin')),
              onTap: () => refreshNotices(context, store),
            ),
            SettingRow(
              '开发者通知',
              detail: store.noticeBody('dev').isEmpty
                  ? '尚未收到开发者通知'
                  : (store.noticeTitle('dev').isEmpty
                        ? '已收到，点按查看'
                        : store.noticeTitle('dev')),
              onTap: () => refreshNotices(context, store),
            ),
            SettingRow(
              '通知中心',
              detail: store.notices['lastResult']?.toString() ?? '尚未检查通知',
              onTap: () => showNoticeCenterSheet(
                context,
                store,
                onRefresh: () =>
                    refreshNotices(context, store, quietWhenIdle: true),
              ),
            ),
            SettingRow(
              '待上传通知草稿',
              detail: store.noticeOutbox.isEmpty
                  ? '没有待上传通知'
                  : '${store.noticeOutbox.length} 条 · 点按预览',
              onTap: () => drafts(),
            ),
            SettingRow(
              '自动检查（冷启动 + 回前台超过 1 小时）',
              detail: '只拉取 index.json，版本变化时才下载正文',
              trailing: CupertinoSwitch(
                value: store.settings['autoSync'] != false,
                onChanged: (v) {
                  store.settings['autoSync'] = v;
                  store.persist();
                },
              ),
            ),
            SettingRow('最近检查', detail: prettyStamp(store.notices['lastCheck'])),
          ]),
        if (widget.section == '外观')
          _group('外观', [
            SettingRow(
              '主题',
              detail: themeLabel,
              onTap: () async {
                final value = await choose(
                  context,
                  '外观模式',
                  {'system': '跟随系统', 'light': '浅色', 'dark': '深色'},
                  selected: {store.settings['theme']?.toString() ?? 'system'},
                  icons: {
                    'system': CupertinoIcons.circle_lefthalf_fill,
                    'light': CupertinoIcons.sun_max,
                    'dark': CupertinoIcons.moon,
                  },
                );
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
                final value = await choose(
                  context,
                  '首页卡片',
                  {'sync': '待上传变更', 'today': '今日登记人数'},
                  selected: {
                    store.settings['homeCard'] == 'sync' ? 'sync' : 'today',
                  },
                  icons: {
                    'sync': CupertinoIcons.cloud_upload,
                    'today': CupertinoIcons.person_2,
                  },
                );
                if (value != null) {
                  store.settings['homeCard'] = value;
                  await store.persist();
                }
              },
            ),
            SettingRow(
              '毛玻璃效果',
              detail: store.settings['glass'] != false
                  ? '导航栏与浮动按钮为磨砂玻璃；关闭后不再实时模糊'
                  : '已关闭：导航栏改为不透明，降低功耗与绘制开销',
              trailing: CupertinoSwitch(
                value: store.settings['glass'] != false,
                onChanged: (v) {
                  store.settings['glass'] = v;
                  store.persist();
                },
              ),
            ),
          ]),
        if (widget.section == '外观')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '关闭毛玻璃后，导航栏和圆形按钮使用不透明背景，停止实时模糊。系统要求减少动态效果时也会自动关闭。',
              style: AppType.footnoteStyle.copyWith(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
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
            SettingRow(
              'GitHub 仓库',
              detail: 'Murchey/Qingluan-attendance · 源码与 Release',
              onTap: () => showLinkSheet(
                context,
                title: 'GitHub 仓库',
                url: UpdateDefaults.github,
              ),
            ),
            SettingRow(
              'Gitee 仓库',
              detail: 'Murchey/qingluan-attendance · 国内镜像',
              onTap: () => showLinkSheet(
                context,
                title: 'Gitee 仓库',
                url: UpdateDefaults.gitee,
              ),
            ),
            SettingRow(
              '使用指南',
              detail: '首次使用、登记、请假、同步的步骤',
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const LegalPage.guide(),
                ),
              ),
            ),
            SettingRow(
              '隐私政策',
              detail: '数据只在本机与你自己的存储桶 · v$kPolicyVersion',
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const LegalPage.privacy(),
                ),
              ),
            ),
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
      store.settings['homeCard'] == 'sync' ? '待上传变更' : '今日登记人数';
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

  /// Preview of the notices queued for upload.
  Future<void> drafts() async {
    final outbox = store.noticeOutbox;
    if (outbox.isEmpty) {
      await message(context, '没有待上传通知', '在首页「管理员通知」中发布后会进入这里，等待签名上传。');
      return;
    }
    await showAppSheet<void>(
      context,
      (sheetContext) => SheetPanel(
        title: '待上传通知',
        subtitle: '${outbox.length} 条 · 签名上传接入后自动写入 note.md 与 index.json',
        titleIcon: CupertinoIcons.cloud_upload,
        child: Column(
          children: [
            for (final draft in outbox.reversed)
              SettingRow(
                (draft['title']?.toString().isEmpty ?? true)
                    ? '未命名通知'
                    : draft['title'].toString(),
                detail: '${draft['createdAt'] ?? ''}'.replaceFirst('T', ' '),
                onTap: () => showNoticePanel(
                  sheetContext,
                  store,
                  channel: 'admin',
                  title: draft['title']?.toString() ?? '',
                  body: draft['markdown']?.toString() ?? '',
                  note: '待上传',
                ),
              ),
          ],
        ),
      ),
    );
  }

  void openSection(String section) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => SettingsPage(store: store, section: section),
    ),
  );

  /// Grouped card with an iOS-style header label and inset dividers.
  Widget _group(String title, List<Widget> children, {double? inset}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GroupLabel(title),
            SettingsGroup(dividerInset: inset ?? Gap.md, children: children),
          ],
        ),
      );

  /// Neutral leading glyphs keep emphasis on the settings labels.
  Widget _row(
    BuildContext context,
    String title, {
    String detail = '',
    required IconData icon,
    VoidCallback? onTap,
    Widget? trailing,
  }) => SettingRow(
    title,
    detail: detail,
    leading: IconBadge(
      icon: icon,
      tint: CupertinoColors.secondaryLabel.resolveFrom(context),
    ),
    onTap: onTap,
    trailing: trailing,
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
              PrimaryButton(
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
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  onPressed: () => add(context),
                  child: const Text('新增人员'),
                ),
              ),
              const SizedBox(width: Gap.xs),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.sm,
                ),
                color: AppColors.raised.resolveFrom(context),
                borderRadius: BorderRadius.circular(Radii.control),
                onPressed: () => import(context),
                child: Text(
                  '导入',
                  style: AppType.button.copyWith(
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxs),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => PeopleBatchPage(store: store),
              ),
            ),
            child: Text(
              '批量编辑',
              style: AppType.footnoteStyle.copyWith(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          if (store.visiblePeople.isEmpty)
            const EmptyState(
              icon: CupertinoIcons.person_2,
              title: '还没有人员',
              message:
                  '手动新增，或从 Excel / CSV 导入名单。'
                  '文件首行需包含“姓名”列，可选性别与工号列。',
            ),
          ...store.visiblePeople.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: SettingRow(
                  p.name,
                  detail: p.active ? '启用中' : '已停用（历史保留）',
                  onTap: () => options(context, p),
                  trailing: CupertinoButton(
                    padding: const EdgeInsets.all(Gap.xs),
                    onPressed: () => options(context, p),
                    child: Icon(
                      CupertinoIcons.ellipsis,
                      size: Sizes.icon,
                      semanticLabel: '${p.name}的选项',
                    ),
                  ),
                ),
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
              child: PrimaryButton(onPressed: edit, child: const Text('编辑')),
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
