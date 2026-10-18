import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/app/app.dart';
import 'package:qingluan_attendance/core/config/legal_text.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';
import 'package:qingluan_attendance/features/legal/presentation/legal_page.dart';

void main() {
  testWidgets('first launch shows the guide instead of the shell', (
    tester,
  ) async {
    final store = Workspace.memory();
    await tester.pumpWidget(QingLuanApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('数据先存在手机上'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('今日名单'), findsNothing);
    expect(find.text('跳过'), findsOneWidget);
  });

  testWidgets('agreeing on the last slide unlocks the app', (tester) async {
    final store = Workspace.memory();
    await tester.pumpWidget(QingLuanApp(store: store));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }
    expect(find.text('云端同步是可选的'), findsOneWidget);

    // Without the consent tick the primary button does nothing.
    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
    expect(store.settings['onboarded'], isNot(true));

    await tester.tap(find.byKey(const Key('onboarding-agree')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();

    expect(store.settings['onboarded'], isTrue);
    expect(store.settings['policyVersion'], kPolicyVersion);
    expect(find.text('今日名单'), findsWidgets);
  });

  testWidgets('skipping records the policy version too', (tester) async {
    final store = Workspace.memory();
    await tester.pumpWidget(QingLuanApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(store.settings['onboarded'], isTrue);
    expect(store.settings['policyVersion'], kPolicyVersion);
    expect(find.text('今日名单'), findsWidgets);
  });

  test('a newer policy version asks again', () {
    final store = Workspace.memory();
    expect(needsOnboarding(store), isTrue);
    store.settings['onboarded'] = true;
    store.settings['policyVersion'] = kPolicyVersion;
    expect(needsOnboarding(store), isFalse);
    store.settings['policyVersion'] = '2020-01-01';
    expect(needsOnboarding(store), isTrue);
  });

  testWidgets('the privacy policy and guide render their sections', (
    tester,
  ) async {
    await tester.pumpWidget(const CupertinoApp(home: LegalPage.privacy()));
    await tester.pumpAndSettle();
    expect(find.textContaining('我们处理哪些信息'), findsOneWidget);
    expect(find.textContaining('数据保存与删除'), findsOneWidget);

    await tester.pumpWidget(const CupertinoApp(home: LegalPage.guide()));
    await tester.pumpAndSettle();
    expect(find.textContaining('第一次打开'), findsOneWidget);
  });
}
