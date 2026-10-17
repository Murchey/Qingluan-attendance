import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';
import 'package:qingluan_attendance/core/data/spreadsheet_io.dart';
import 'package:qingluan_attendance/features/sync/presentation/conflict_page.dart';

void main() {
  test('business day crosses midnight at UTC 16:00', () {
    expect(businessDay(DateTime.utc(2026, 10, 16, 15, 59)), '2026-10-16');
    expect(businessDay(DateTime.utc(2026, 10, 16, 16)), '2026-10-17');
  });
  test('import previews duplicates and missing names without overwriting', () {
    final preview = parsePeople(
      [
        ['姓名', '部门'],
        ['林晓', '一'],
        ['周宁', '二'],
        ['', '三'],
        ['周宁', '四'],
      ],
      ['林晓'],
    );
    expect(preview.names, ['周宁']);
    expect(preview.issues.length, 3);
    expect(
      () => parsePeople([
        ['部门'],
      ], []),
      throwsFormatException,
    );
  });
  test(
    'identity required, duplicate people rejected, batch edit preserves audit',
    () async {
      final store = Workspace.memory();
      await store.savePerson('林晓');
      await store.savePerson('周宁');
      await expectLater(store.savePerson(' 林晓 '), throwsFormatException);
      await expectLater(
        store.saveEntries(
          [store.people.first.id],
          '2026-10-17',
          {'in': '09:00', 'out': '18:00', 'status': '正常', 'note': ''},
        ),
        throwsFormatException,
      );
      await store.setIdentity('主管');
      final ids = store.people.map((p) => p.id).toList();
      await store.saveEntries(ids, '2026-10-17', {
        'in': '09:00',
        'out': '18:00',
        'status': '正常',
        'note': '',
      });
      expect(store.liveEntries.length, 2);
      final old = store.liveEntries.first;
      await store.saveEntries(
        [ids.first],
        '2026-10-17',
        {'in': '09:10', 'out': '18:00', 'status': '迟到', 'note': '补录'},
      );
      final edited = store.record(ids.first, '2026-10-17')!;
      expect(edited.id, old.id);
      expect(edited.history.length, 2);
      await store.deleteEntry(edited);
      expect(store.entries.any((e) => e.id == old.id && e.deleted), true);
      await store.togglePerson(store.people.first);
      expect(store.activePeople.length, 1);
    },
  );
  test('xlsx export uses strings and includes export provenance', () async {
    final store = Workspace.memory();
    await store.savePerson('林晓');
    await store.setIdentity('主管');
    await store.saveEntries(
      [store.people.first.id],
      '2026-10-17',
      {'in': '09:00', 'out': '18:00', 'status': '正常', 'note': '=1+1'},
    );
    final book = Excel.decodeBytes(
      workbookBytes(store, store.liveEntries, exportColumns),
    );
    expect(book.tables.values.first.rows[0][0]!.value.toString(), '人员');
    expect(book.tables.values.first.rows[1][5]!.value, isA<TextCellValue>());
    expect(book.tables.containsKey('导出信息'), true);
  });
  test(
    'field timestamp tie and missing values retain local; newer remote wins',
    () {
      Entry entry(String note, String? time) => Entry(
        id: 'record',
        personId: 'person',
        day: '2026-10-17',
        fields: {'in': '09:00', 'out': '18:00', 'status': '正常', 'note': note},
        author: note,
        updatedAt: '2026-10-17T01:00:00Z',
        fieldTimes: time == null ? {} : {'note': time},
      );
      final local = entry('本地', '2026-10-17T01:00:00Z');
      expect(
        remoteIsNewer(local, entry('远端', '2026-10-17T01:00:00Z'), 'note'),
        false,
      );
      expect(remoteIsNewer(local, entry('远端', null), 'note'), false);
      final remote = entry('远端', '2026-10-17T02:00:00Z');
      expect(remoteIsNewer(local, remote, 'note'), true);
      final resolved = resolveEntry(local, remote, {'note': true}, '合并者', '设备');
      expect(resolved.fields['note'], '远端');
      expect(resolved.id, local.id);
      expect(resolved.author, '合并者');
      expect(resolved.history.single, contains('合并'));
    },
  );
  test(
    'SQLite restores people, records, pending queue and identity on restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('qingluan-test-');
      final path = '${dir.path}/workspace.db';
      final first = Workspace.memory();
      try {
        await first.open(path: path);
        await first.setIdentity('管理员');
        await first.savePerson('林晓');
        await first.saveEntries(
          [first.people.single.id],
          '2026-10-17',
          {'in': '09:00', 'out': '18:00', 'status': '正常', 'note': ''},
        );
        final id = first.deviceId;
        await first.close();
        final second = Workspace.memory();
        await second.open(path: path);
        expect(second.identity, '管理员');
        expect(second.deviceId, id);
        expect(second.liveEntries.length, 1);
        expect(second.pendingDays, contains('2026-10-17'));
        await second.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
