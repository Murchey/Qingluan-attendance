import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import '../../../core/config/legal_text.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../legal/presentation/legal_page.dart';

/// First-run guide. Shows once per policy version: finishing it (or skipping)
/// records the accepted version so the gate stays out of the way afterwards.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.store});
  final Workspace store;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pages = PageController();
  int index = 0;
  bool agreed = false;

  static const _slides = <_Slide>[
    _Slide(
      icon: CupertinoIcons.lock_shield,
      title: '数据先存在手机上',
      body: [
        '人员、考勤、请假都写在本机数据库，没网也能登记。',
        '青鸾没有服务器，看不到你的名单和考勤。',
      ],
    ),
    _Slide(
      icon: CupertinoIcons.checkmark_seal,
      title: '每天登记一次就够',
      body: [
        '首页「今日登记」逐个选人，「批量登记」一次选多人，「补录历史」补过去的日子。',
        '签到、签退、状态和备注都在同一个面板里填完。',
      ],
    ),
    _Slide(
      icon: CupertinoIcons.calendar,
      title: '请假会锁住当天考勤',
      body: [
        '只有「已确认」的请假会挡住登记，改成待确认或已取消即刻解锁。',
        '提前返岗就把结束日期改到实际返岗前一天，算是销假。',
      ],
    ),
    _Slide(
      icon: CupertinoIcons.cloud,
      title: '云端同步是可选的',
      body: [
        '填上你自己的对象存储桶，改完数据约 0.7 秒后自动上传。',
        '不填也能一直用，随时可以在设置里补。',
      ],
    ),
  ];

  bool get isLast => index == _slides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    widget.store.settings['onboarded'] = true;
    widget.store.settings['policyVersion'] = kPolicyVersion;
    await widget.store.persist();
  }

  void _next() {
    if (isLast) {
      if (agreed) _finish();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openPolicy() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => const LegalPage.privacy()),
    );
    if (!mounted) return;
    if (agreed) await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      const SizedBox(width: Gap.sm),
                      const Text(
                        '青鸾考勤',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.2,
                        ),
                      ),
                      const Spacer(),
                      if (!isLast)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.sm,
                          ),
                          minimumSize: Size.zero,
                          onPressed: _finish,
                          child: Text(
                            '跳过',
                            style: TextStyle(fontSize: 15, color: secondary),
                          ),
                        ),
                      const SizedBox(width: Gap.xs),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => index = i),
                    itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Gap.lg,
                    Gap.sm,
                    Gap.lg,
                    bottom + Gap.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _slides.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == index ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == index
                                    ? CupertinoDynamicColor.resolve(
                                        AppColors.navy,
                                        context,
                                      )
                                    : separatorOf(context),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: Gap.md),
                      if (isLast) ...[
                        _AgreementTile(
                          agreed: agreed,
                          onChanged: (v) => setState(() => agreed = v),
                          onOpenPolicy: _openPolicy,
                        ),
                        const SizedBox(height: Gap.sm),
                      ],
                      PrimaryButton(
                        onPressed: isLast && !agreed ? null : _next,
                        child: Text(isLast ? '开始使用' : '下一步'),
                      ),
                      const SizedBox(height: Gap.xs),
                      Center(
                        child: Text(
                          isLast ? '同意后会记住这份政策版本，之后不再打扰' : '可随时跳过，稍后在设置里查看',
                          style: const TextStyle(fontSize: AppType.caption1, height: 1.3).copyWith(color: secondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // A hairline keeps the header from floating on the page background.
          Positioned(
            top: top + 44,
            left: 0,
            right: 0,
            child: Container(height: .5, color: separatorOf(context)),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final List<String> body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;
  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(AppColors.navy, context)
                  .withValues(alpha: .12),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Icon(
              slide.icon,
              size: 30,
              color: CupertinoDynamicColor.resolve(AppColors.navy, context),
            ),
          ),
          const SizedBox(height: Gap.md),
          Text(slide.title, style: AppType.pageTitle),
          const SizedBox(height: Gap.sm),
          for (final line in slide.body) ...[
            Text(line, style: AppType.calloutStyle.copyWith(color: secondary)),
            const SizedBox(height: Gap.xs),
          ],
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _AgreementTile extends StatefulWidget {
  const _AgreementTile({
    required this.agreed,
    required this.onChanged,
    required this.onOpenPolicy,
  });
  final bool agreed;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenPolicy;
  @override
  State<_AgreementTile> createState() => _AgreementTileState();
}

class _AgreementTileState extends State<_AgreementTile> {
  late final TapGestureRecognizer _policyTap = TapGestureRecognizer()
    ..onTap = widget.onOpenPolicy;

  @override
  void dispose() {
    _policyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoButton(
          key: const Key('onboarding-agree'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(30, 30),
          onPressed: () => widget.onChanged(!widget.agreed),
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.agreed ? accent : const Color(0x00000000),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: widget.agreed ? accent : secondary.withValues(alpha: .6),
                width: 1.4,
              ),
            ),
            child: widget.agreed
                ? const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 14,
                    color: CupertinoColors.white,
                  )
                : null,
          ),
        ),
        const SizedBox(width: Gap.xs),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onChanged(!widget.agreed),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '我已阅读并同意',
                    style: AppType.footnoteStyle.copyWith(color: secondary),
                  ),
                  TextSpan(
                    text: '《隐私政策》',
                    recognizer: _policyTap,
                    style: AppType.footnoteStyle.copyWith(color: accent),
                  ),
                  TextSpan(
                    text: '，数据只存在本机和你自己的存储桶。',
                    style: AppType.footnoteStyle.copyWith(color: secondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
/// Entry shown in settings so the guide and policy stay reachable later.
void openOnboardingHelp(BuildContext context, {required bool privacy}) {
  Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) =>
          privacy ? const LegalPage.privacy() : const LegalPage.guide(),
    ),
  );
}
