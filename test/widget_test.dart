import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/app/app.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';
import 'package:qingluan_attendance/features/attendance/presentation/entry_editor.dart';
import 'package:qingluan_attendance/features/sync/presentation/conflict_page.dart';

void main() {
  testWidgets(
    'home counts live records and quick entry edits the selected person',
    (tester) async {
      final store = Workspace.memory();
      await store.setIdentity('主管');
      await store.savePerson('甲');
      await store.savePerson('乙');
      await store.saveEntries(
        [store.people.first.id],
        businessDay(),
        {'in': '09:00', 'out': '', 'status': '正常', 'note': '已有备注'},
      );
      await store.saveEntries(
        [store.people.last.id],
        businessDay(),
        {'in': '', 'out': '', 'status': '正常', 'note': ''},
      );
      await store.deleteEntry(
        store.record(store.people.last.id, businessDay())!,
      );
      await tester.pumpWidget(QingLuanApp(store: store));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('today-record-count')))
            .data,
        '1',
      );
      expect(find.text('还有 1 人待登记'), findsOneWidget);
      await tester.tap(find.text('今日登记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('甲 · 已有记录'));
      await tester.pumpAndSettle();
      final editor = tester.widget<EntryEditor>(find.byType(EntryEditor));
      expect(editor.entry?.personId, store.people.first.id);
      expect(editor.day, businessDay());
      expect(find.text('已有备注'), findsOneWidget);
      expect(find.text('保存 1 人登记'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'backfill picks a date only on demand and preselects new entries',
    (tester) async {
      final store = Workspace.memory();
      await store.setIdentity('主管');
      await store.savePerson('甲');
      await tester.pumpWidget(QingLuanApp(store: store));
      expect(find.byType(CupertinoDatePicker), findsNothing);
      await tester.tap(find.text('补录历史'));
      await tester.pumpAndSettle();
      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      final yesterday = DateTime.parse(
        businessDay(),
      ).subtract(const Duration(days: 1));
      picker.onDateTimeChanged(yesterday);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EntryEditor>(find.byType(EntryEditor)).day,
        yesterday.toIso8601String().substring(0, 10),
      );
      await tester.tap(find.bySemanticsLabel('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日登记'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoActionSheetAction, '甲'));
      await tester.pumpAndSettle();
      expect(find.text('保存 1 人登记'), findsOneWidget);
      expect(
        tester.widget<EntryEditor>(find.byType(EntryEditor)).initialPersonId,
        store.people.single.id,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('application starts with the four-section shell', (tester) async {
    await tester.pumpWidget(QingLuanApp(store: Workspace.memory()));
    expect(find.text('今日概览'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('同步'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('bottom navigation switches sections', (tester) async {
    await tester.pumpWidget(QingLuanApp(store: Workspace.memory()));
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('历史记录'), findsOneWidget);
    await tester.tap(find.text('同步'));
    await tester.pumpAndSettle();
    expect(find.text('同步中心'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('人员名单'), findsOneWidget);
    expect(find.byType(CupertinoPageScaffold), findsWidgets);
  });

  testWidgets('wide landscape keeps local overview and shortcuts usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final store = Workspace.memory();
    await tester.pumpWidget(QingLuanApp(store: store));
    expect(find.text('今日已登记'), findsOneWidget);
    expect(find.text('今日登记'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('搜索姓名或备注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen dark theme and dragging pill navigate correctly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    await tester.pumpWidget(QingLuanApp(store: Workspace.memory()));
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getCenter(find.text('今日')),
      const Offset(230, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('人员名单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'appearance changes immediately on secondary pages and follows system',
    (tester) async {
      final store = Workspace.memory();
      await tester.pumpWidget(QingLuanApp(store: store));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('存储桶直链'), findsNothing);
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      Future<void> selectTheme(String label) async {
        await tester.tap(find.text('主题'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CupertinoActionSheetAction, label),
        );
        await tester.pumpAndSettle();
      }

      await selectTheme('深色');
      expect(store.settings['theme'], 'dark');
      final context = tester.element(find.text('主题'));
      expect(CupertinoTheme.brightnessOf(context), Brightness.dark);
      await selectTheme('浅色');
      expect(
        CupertinoTheme.brightnessOf(tester.element(find.text('主题'))),
        Brightness.light,
      );
      await selectTheme('跟随系统');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        CupertinoTheme.brightnessOf(tester.element(find.text('主题'))),
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'person deletion can be cancelled and retains historical attendance',
    (tester) async {
      final store = Workspace.memory();
      await store.setIdentity('主管');
      await store.savePerson('甲');
      final id = store.people.single.id;
      await store.saveEntries(
        [id],
        businessDay(),
        {'in': '09:00', 'out': '', 'status': '正常', 'note': ''},
      );
      await tester.pumpWidget(QingLuanApp(store: store));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('人员名单'));
      await tester.pumpAndSettle();
      Future<void> delete() async {
        await tester.tap(find.bySemanticsLabel('甲的选项'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除人员'));
        await tester.pumpAndSettle();
      }

      await delete();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.visiblePeople, hasLength(1));
      await delete();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(store.visiblePeople, isEmpty);
      expect(store.activePeople, isEmpty);
      expect(find.text('甲'), findsNothing);
      expect(store.name(id), '甲');
      expect(store.record(id, businessDay()), isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('navigation follows a partial drag before finger release', (
    tester,
  ) async {
    await tester.pumpWidget(QingLuanApp(store: Workspace.memory()));
    await tester.pumpAndSettle();
    final pageView = tester.widget<PageView>(find.byType(PageView));
    final nav = find.byKey(const ValueKey('bottom-navigation'));
    final segment = tester.getSize(nav).width / 4;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('今日')),
    );
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    final start = pageView.controller!.page!;
    await gesture.moveBy(Offset(segment * .35, 0));
    await tester.pump();
    expect(pageView.controller!.page, closeTo(start + .35, .02));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch editor saves selected people and notes', (tester) async {
    final store = Workspace.memory();
    await store.setIdentity('主管');
    await store.savePerson('甲');
    await store.savePerson('乙');
    await tester.pumpWidget(
      CupertinoApp(
        home: EntryEditor(store: store, day: '2026-10-17'),
      ),
    );
    await tester.tap(find.text('甲'));
    await tester.tap(find.text('乙'));
    await tester.enterText(find.byType(CupertinoTextField), '批量备注');
    await tester.ensureVisible(find.text('保存 2 人登记'));
    await tester.tap(find.text('保存 2 人登记'));
    await tester.pumpAndSettle();
    expect(store.liveEntries.length, 2);
    expect(store.liveEntries.every((e) => e.fields['note'] == '批量备注'), true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflict table accepts remote and queues resolved day', (
    tester,
  ) async {
    final store = Workspace.memory();
    await store.setIdentity('主管');
    await store.savePerson('甲');
    await store.saveEntries(
      [store.people.single.id],
      '2026-10-17',
      {'in': '09:00', 'out': '18:00', 'status': '正常', 'note': '本地'},
    );
    final local = store.liveEntries.single;
    store.remoteEntries.add(
      Entry(
        id: local.id,
        personId: local.personId,
        day: local.day,
        fields: {...local.fields, 'note': '云端'},
        author: '另一管理员',
        updatedAt: local.updatedAt,
      ),
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: ConflictPage(store: store, day: local.day),
      ),
    );
    await tester.tap(find.text('全部采用远端'));
    await tester.pump();
    await tester.ensureVisible(find.text('保存合并 · 等待上传'));
    await tester.tap(find.text('保存合并 · 等待上传'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(store.liveEntries.single.fields['note'], '云端');
    expect(store.remoteEntries, isEmpty);
    expect(store.pendingDays, contains(local.day));
    expect(tester.takeException(), isNull);
  });
}
