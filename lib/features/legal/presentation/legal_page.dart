import 'package:flutter/cupertino.dart';

import '../../../core/config/legal_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/markdown.dart';
import '../../../core/widgets/ui.dart';

/// Full text of the privacy policy or the user guide. Both are plain Markdown
/// rendered by the same renderer used for notices, so they scroll and wrap like
/// the rest of the app and stay readable in either appearance.
class LegalPage extends StatelessWidget {
  const LegalPage.privacy({super.key})
    : title = '隐私政策',
      body = kPrivacyPolicy;
  const LegalPage.guide({super.key})
    : title = '使用指南',
      body = kUserGuide;

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Screen(
      title: title,
      children: [
        const SizedBox(height: Gap.xs),
        MarkdownView(body, baseSize: 14.5),
        const SizedBox(height: Gap.lg),
        Center(
          child: Text(
            '青鸾考勤 v$kAppVersion · 政策版本 $kPolicyVersion',
            style: const TextStyle(fontSize: AppType.caption1, height: 1.3).copyWith(color: secondary),
          ),
        ),
        const SizedBox(height: Gap.md),
      ],
    );
  }
}

/// One-line summary used by the onboarding consent card.
String get privacySummary => kPrivacySummary;

/// Ink colour used by legal links inside long text.
Color legalLinkColor(BuildContext context) =>
    CupertinoDynamicColor.resolve(AppColors.navy, context);
