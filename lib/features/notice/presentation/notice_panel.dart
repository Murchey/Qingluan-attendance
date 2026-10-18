import 'package:flutter/cupertino.dart';
import '../../../core/data/workspace.dart';
import '../../../core/reminders/notice_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/markdown.dart';
import '../../../core/widgets/sheet.dart';

const noticeChannelLabels = {'admin': '管理员通知', 'dev': '开发者通知'};

/// UTC ISO stamps are stored for sorting; show a short readable form.
String prettyStamp(Object? value) {
  final text = value?.toString() ?? '';
  if (text.isEmpty) return '尚未检查';
  final normalized = text.replaceFirst('T', ' ');
  return normalized.length >= 16
      ? '${normalized.substring(0, 16)} UTC'
      : normalized;
}

/// Notification bodies often repeat the title as an H1; keep one heading.
String stripDuplicateTitle(String body, String title) {
  final lines = body.split('\n');
  if (lines.isEmpty) return body;
  final first = lines.first.trim();
  if (first.startsWith('# ') &&
      (title.isEmpty || first.substring(2).trim() == title.trim())) {
    return lines.skip(1).join('\n').trimLeft();
  }
  return body;
}

/// Renders one notice body (Markdown) in the shared bottom panel.
Future<void> showNoticePanel(
  BuildContext context,
  Workspace store, {
  required String channel,
  required String title,
  required String body,
  String updatedAt = '',
  String? note,
}) => showAppSheet<void>(
  context,
  (sheetContext) => SheetPanel(
    title: title.isEmpty ? noticeChannelLabels[channel]! : title,
    subtitle: [
      noticeChannelLabels[channel]!,
      if (updatedAt.isNotEmpty) '更新于 $updatedAt',
      if (note != null && note.isNotEmpty) note,
    ].join(' · '),
    titleIcon: channel == 'dev'
        ? CupertinoIcons.hammer
        : CupertinoIcons.bell,
    child: MarkdownView(
      stripDuplicateTitle(body, title),
      baseSize: 14.5,
    ),
    footer: CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => Navigator.of(sheetContext).pop(),
      child: const SizedBox(
        height: 52,
        child: Center(
          child: Text(
            '知道了',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  ),
);

/// Shows every channel that has a version this device has not displayed yet.
Future<void> presentNoticeResult(
  BuildContext context,
  Workspace store,
  NoticeSyncResult result,
) async {
  final admin = result.admin;
  if (admin != null) {
    await showNoticePanel(
      context,
      store,
      channel: 'admin',
      title: admin.title,
      body: result.adminBody,
      updatedAt: admin.updatedAt,
    );
    await store.saveNotice(
      'admin',
      version: admin.version,
      title: admin.title,
      body: result.adminBody,
      updatedAt: admin.updatedAt,
    );
  }
  final dev = result.dev;
  if (dev != null && context.mounted) {
    await showNoticePanel(
      context,
      store,
      channel: 'dev',
      title: dev.title,
      body: result.devBody,
      updatedAt: dev.updatedAt,
    );
    await store.saveNotice(
      'dev',
      version: dev.version,
      title: dev.title,
      body: result.devBody,
      updatedAt: dev.updatedAt,
    );
  }
}

/// Manual check used by the home bell and the settings page.
Future<NoticeSyncResult> refreshNotices(
  BuildContext context,
  Workspace store, {
  bool quietWhenIdle = false,
}) async {
  final result = await syncNotices(store);
  if (!context.mounted) return result;
  if (result.hasNews) {
    await presentNoticeResult(context, store, result);
  } else if (!quietWhenIdle) {
    await showMessageSheet(
      context,
      '通知检查',
      result.message.isEmpty
          ? '${store.notices['lastResult'] ?? '已是最新'}'
          : result.message,
      icon: CupertinoIcons.bell,
    );
  }
  return result;
}

/// Notification centre: channel history, outbox drafts and a manual refresh.
Future<void> showNoticeCenterSheet(
  BuildContext context,
  Workspace store, {
  Future<NoticeSyncResult> Function()? onRefresh,
}) => showAppSheet<void>(
  context,
  (sheetContext) => SheetPanel(
    title: '通知中心',
    subtitle: store.notices['lastResult']?.toString() ?? '尚未检查通知',
    titleIcon: CupertinoIcons.bell,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final channel in ['admin', 'dev'])
          _NoticeEntryRow(
            channel: channel,
            hasBody: store.noticeBody(channel).isNotEmpty,
            updatedAt: store.noticeUpdatedAt(channel),
            title: store.noticeTitle(channel),
            onTap: () async {
              if (store.noticeBody(channel).isEmpty) {
                await showMessageSheet(
                  sheetContext,
                  noticeChannelLabels[channel]!,
                  '还没有收到过${noticeChannelLabels[channel]}。'
                      '应用启动时会请求 index.json，发现新版本后才下载正文。',
                  icon: CupertinoIcons.tray,
                );
                return;
              }
              // Close the centre first so the notice panel is not stacked on
              // top of another sheet.
              Navigator.of(sheetContext).pop();
              if (!context.mounted) return;
              await showNoticePanel(
                context,
                store,
                channel: channel,
                title: store.noticeTitle(channel),
                body: store.noticeBody(channel),
                updatedAt: store.noticeUpdatedAt(channel),
              );
            },
          ),
        const SizedBox(height: 8),
        _MetricRow(
          icon: CupertinoIcons.cloud_upload,
          title: '待上传通知草稿',
          value: '${store.noticeOutbox.length} 条',
          detail: store.noticeOutbox.isEmpty
              ? '发布后先进入本地队列，签名上传接入后自动写入 note.md 与 index.json'
              : '接入签名上传后自动写入 note.md 与 index.json',
        ),
        _MetricRow(
          icon: CupertinoIcons.clock,
          title: '最近检查',
          value: prettyStamp(store.notices['lastCheck']),
          detail: '冷启动同步一次；从后台回到前台超过 1 小时再同步',
        ),
      ],
    ),
    footer: onRefresh == null
        ? null
        : CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              await onRefresh();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
            child: const SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  '立即检查更新与通知',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
  ),
);

class _NoticeEntryRow extends StatelessWidget {
  const _NoticeEntryRow({
    required this.channel,
    required this.hasBody,
    required this.title,
    required this.updatedAt,
    required this.onTap,
  });
  final String channel;
  final bool hasBody;
  final String title;
  final String updatedAt;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: .6,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.raised.resolveFrom(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                channel == 'dev'
                    ? CupertinoIcons.hammer
                    : CupertinoIcons.bell,
                size: 20,
                color: hasBody ? accent : secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      noticeChannelLabels[channel]!,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasBody
                          ? (title.isEmpty
                                ? '已收到，点击查看正文'
                                : '$title${updatedAt.isEmpty ? '' : ' · $updatedAt'}')
                          : '尚未收到',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 14.5),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(fontSize: 11.5, color: secondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
