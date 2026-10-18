import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';
import 'package:qingluan_attendance/features/home/presentation/today_page.dart';

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

Widget host(Workspace store) => CupertinoApp(
  home: TodayPage(
    store: store,
    onSync: () {},
    onSettings: () {},
    onRecords: () {},
  ),
);

void main() {
  testWidgets('tapping a row books the check-in, tapping again books out', (
    tester,
  ) async {
    final store = seed();
    await tester.pumpWidget(host(store));
    await tester.pumpAndSettle();

    final day = businessDay();
    expect(find.text('未登记'), findsNWidgets(3));

    await tester.tap(find.text('林晓'));
    await tester.pumpAndSettle();
    final first = store.record('p1', day);
    expect(first, isNotNull);
    expect(first!.fields['in'], matches(RegExp(r'^\d{2}:\d{2}$')));
    expect(first.fields['out'], isNull);
    expect(first.fields['status'], anyOf('正常', '迟到'));

    await tester.tap(find.text('林晓'));
    await tester.pumpAndSettle();
    final second = store.record('p1', day);
    expect(second!.fields['out'], matches(RegExp(r'^\d{2}:\d{2}$')));
  });

  testWidgets('全员正常 books the rest and 撤销 puts them back', (tester) async {
    final store = seed();
    await tester.pumpWidget(host(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全员正常'));
    await tester.pumpAndSettle();
    expect(find.textContaining('把 3 人登记为正常'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    final day = businessDay();
    expect(store.liveEntries.length, 3);
    expect(store.record('p1', day)!.fields['in'], '09:00');
    expect(store.record('p1', day)!.fields['status'], '正常');
    expect(find.text('未登记'), findsNothing);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(store.record('p1', day), isNull);
    expect(find.text('未登记'), findsNWidgets(3));
  });

  testWidgets('结束今天 marks the rest absent', (tester) async {
    final store = seed();
    await tester.pumpWidget(host(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('结束今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    final day = businessDay();
    expect(store.record('p2', day)!.fields['status'], '缺勤');
  });

  testWidgets('a confirmed leave keeps the row inert', (tester) async {
    final store = seed();
    final day = businessDay();
    await store.saveLeave(
      personId: 'p3',
      startDay: day,
      endDay: day,
      type: '事假',
      status: '已确认',
    );
    await tester.pumpWidget(host(store));
    await tester.pumpAndSettle();

    expect(find.textContaining('请假中'), findsOneWidget);
    await tester.tap(find.text('王琪'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(store.record('p3', day), isNull);
  });

  testWidgets('without a display name the roster asks for it first', (
    tester,
  ) async {
    final store = seed()..identity = '';
    await tester.pumpWidget(host(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('林晓'));
    await tester.pumpAndSettle();
    expect(find.text('先填本地显示名'), findsOneWidget);
    expect(store.record('p1', businessDay()), isNull);
  });
}
