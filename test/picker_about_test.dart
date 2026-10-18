import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';
import 'package:qingluan_attendance/core/widgets/person_picker.dart';
import 'package:qingluan_attendance/features/settings/presentation/settings_page.dart';

Workspace seed() {
  final store = Workspace.memory();
  store
    ..identity = 'Admin'
    ..people.addAll([
      Person('p1', '林晓', employeeId: 'EMP-1024'),
      Person('p2', '周宁', employeeId: 'EMP-1025'),
      Person('p3', '王琪', employeeId: 'EMP-1028'),
    ]);
  return store;
}

void main() {
  testWidgets('the person picker filters by name and employee id', (
    tester,
  ) async {
    final store = seed();
    String? picked;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () async {
              picked = await showPersonPickerSheet(
                context,
                people: store.visiblePeople,
                title: '请假人员',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('林晓'), findsOneWidget);
    expect(find.text('周宁'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), '周');
    await tester.pumpAndSettle();
    expect(find.text('林晓'), findsNothing);
    expect(find.text('周宁'), findsOneWidget);

    // Employee id search works too.
    await tester.enterText(find.byType(CupertinoSearchTextField), '1028');
    await tester.pumpAndSettle();
    expect(find.text('王琪'), findsOneWidget);
    expect(find.text('周宁'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的人员'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), '王');
    await tester.pumpAndSettle();
    await tester.tap(find.text('王琪'));
    await tester.pumpAndSettle();
    expect(picked, 'p3');
  });

  testWidgets('about lists the GitHub and Gitee repositories', (tester) async {
    final store = seed();
    await tester.pumpWidget(
      CupertinoApp(home: SettingsPage(store: store, section: '关于')),
    );
    await tester.pumpAndSettle();

    expect(find.text('GitHub 仓库'), findsOneWidget);
    expect(find.text('Gitee 仓库'), findsOneWidget);

    await tester.tap(find.text('GitHub 仓库'));
    await tester.pumpAndSettle();
    expect(find.textContaining('github.com/Murchey'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
  });

  testWidgets('tapping the search field focuses it and opens the keyboard', (
    tester,
  ) async {
    final store = seed();
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showPersonPickerSheet(
              context,
              people: store.visiblePeople,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CupertinoSearchTextField));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
  });}
