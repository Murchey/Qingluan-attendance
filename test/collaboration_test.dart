import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';
import 'package:qingluan_attendance/features/records/presentation/records_page.dart';
import 'package:qingluan_attendance/features/settings/presentation/settings_page.dart';
import 'package:qingluan_attendance/core/widgets/sheet.dart';

Workspace seed() {
  final store = Workspace.memory()
    ..people.add(Person('p1', '林晓', employeeId: 'EMP-1024'));
  return store;
}

void main() {
  testWidgets('switching current operator uses a known audit author', (
    tester,
  ) async {
    final store = seed();
    store.identity = '李敏';
    await store.saveEntries(
      ['p1'],
      businessDay(),
      {'in': '09:00', 'out': '18:00', 'status': '正常', 'note': ''},
    );
    await store.setIdentity('王强');

    await tester.pumpWidget(CupertinoApp(home: SettingsPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地身份'));
    await tester.pumpAndSettle();
    expect(find.textContaining('李敏'), findsOneWidget);
    await tester.tap(find.text('李敏'));
    await tester.pumpAndSettle();
    expect(store.identity, '李敏');
  });

  testWidgets('records page exposes date presets and editable table cells', (
    tester,
  ) async {
    final store = seed()..identity = '李敏';
    await store.saveEntries(
      ['p1'],
      businessDay(),
      {'in': '09:00', 'out': '18:00', 'status': '正常', 'note': ''},
    );
    await tester.pumpWidget(CupertinoApp(home: RecordsPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('本月'), findsOneWidget);
    expect(find.text('人员'), findsOneWidget);
    expect(find.textContaining('李敏'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);

    await tester.tap(find.text('正常'));
    await tester.pumpAndSettle();
    expect(find.text('修改状态'), findsOneWidget);
    await tester.tap(find.text('缺勤'));
    await tester.pumpAndSettle();
    expect(store.record('p1', businessDay())!.fields['status'], '缺勤');
  });

  testWidgets('time preset buttons apply the current time without crashing', (
    tester,
  ) async {
    String? value;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () async {
              value = await showTimePickSheet(context, presets: const ['现在']);
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('现在'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(value, matches(RegExp(r'^\d{2}:\d{2}$')));
  });
}
