import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'app_widgets.dart';
import 'sheet.dart';
import 'toast.dart';

/// Shows a repository link with copy / share actions.
///
/// The app does not bundle a URL launcher: an administrator usually forwards
/// links on a desktop or a chat, so copy + system share covers the need without
/// an extra dependency or an intent that may be refused by the ROM.
Future<void> showLinkSheet(
  BuildContext context, {
  required String title,
  required String url,
  String subtitle = '复制链接后可在浏览器打开，或直接分享给同事。',
}) => showAppSheet<void>(
  context,
  (sheetContext) => SheetPanel(
    title: title,
    subtitle: subtitle,
    titleIcon: CupertinoIcons.link,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: Gap.md),
          padding: const EdgeInsets.all(Gap.sm),
          decoration: BoxDecoration(
            color: AppColors.raised.resolveFrom(sheetContext),
            borderRadius: BorderRadius.circular(Radii.field),
          ),
          child: Text(
            url,
            style: AppType.cell.copyWith(
              color: CupertinoTheme.of(sheetContext).primaryColor,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
    footer: Row(
      children: [
        Expanded(
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              if (context.mounted) {
                showToast(
                  context,
                  '链接已复制',
                  icon: CupertinoIcons.checkmark_circle,
                );
              }
            },
            child: const SizedBox(
              height: 52,
              child: Center(child: Text('复制链接')),
            ),
          ),
        ),
        Container(width: .5, height: 34, color: separatorOf(sheetContext)),
        Expanded(
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              await SharePlus.instance.share(ShareParams(text: url));
            },
            child: const SizedBox(
              height: 52,
              child: Center(child: Text('分享')),
            ),
          ),
        ),
      ],
    ),
  ),
);
