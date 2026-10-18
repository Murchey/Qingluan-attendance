import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';
import 'package:qingluan_attendance/core/result/app_result.dart';
import 'package:qingluan_attendance/core/storage/object_storage.dart';
import 'package:qingluan_attendance/core/sync/sync_service.dart';

class FakeStorage implements ObjectStorage {
  FakeStorage({this.fail = false});
  bool fail;
  final List<String> puts = [];
  final Map<String, List<int>> objects = {};

  @override
  Future<AppResult<RemoteObject?>> get(String key) async {
    final bytes = objects[key];
    if (bytes == null) return const Success(null);
    return Success(RemoteObject(key: key, sha256: '', bytes: bytes));
  }

  @override
  Future<AppResult<void>> put(
    String key,
    List<int> bytes, {
    required String sha256,
  }) async {
    if (fail) return const Failure('签名校验失败');
    puts.add(key);
    objects[key] = bytes;
    return const Success(null);
  }
}

Future<void> settle([int ms = 200]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('a local save uploads once, debounced, and clears the queue', () async {
    final store = Workspace.memory();
    final storage = FakeStorage();
    final sync = SyncService(
      store,
      storageFactory: () async => storage,
      debounce: const Duration(milliseconds: 30),
    );
    sync.attach();
    addTearDown(sync.dispose);

    // Identity alone is not a business mutation for the queue.
    await store.setIdentity('Admin');
    await settle(60);
    expect(storage.puts, isEmpty);

    // A burst of two saves collapses into a single snapshot + manifest pair.
    await store.savePerson('林晓');
    await store.savePerson('周宁');
    await settle();
    expect(storage.puts.where((k) => k == 'data/workspace.json'), hasLength(1));
    expect(storage.puts, contains('index.json'));
    expect(store.pendingDays, isEmpty);
    expect(sync.phase, SyncPhase.synced);
    // The manifest carries the snapshot hash and the data file list.
    final manifest = String.fromCharCodes(storage.objects['index.json']!);
    expect(manifest, contains('"data"'));
    expect(manifest, contains('data/workspace.json'));
    expect(store.lastSync, isNotNull);
  });

  test('a failed upload keeps the queue for a later retry', () async {
    final store = Workspace.memory();
    final storage = FakeStorage(fail: true);
    final sync = SyncService(
      store,
      storageFactory: () async => storage,
      debounce: const Duration(milliseconds: 20),
    );
    sync.attach();
    addTearDown(sync.dispose);

    await store.savePerson('陈默');
    await settle();
    expect(sync.phase, SyncPhase.failed);
    expect(store.pendingDays, isNotEmpty);
    expect(sync.message, contains('签名校验失败'));

    // No tight retry loop: the second attempt needs an explicit trigger.
    storage.fail = false;
    storage.puts.clear();
    await settle(300);
    expect(storage.puts, isEmpty);

    final ok = await sync.upload(manual: true);
    expect(ok, isTrue);
    expect(store.pendingDays, isEmpty);
    expect(sync.phase, SyncPhase.synced);
  });

  test('uploads a published admin notice before the manifest', () async {
    final store = Workspace.memory();
    final storage = FakeStorage();
    final sync = SyncService(
      store,
      storageFactory: () async => storage,
      debounce: const Duration(milliseconds: 20),
    );
    sync.attach();
    addTearDown(sync.dispose);

    await store.setIdentity('Admin');
    await store.queueNotice({
      'channel': 'admin',
      'key': 'note.md',
      'version': 'v1',
      'title': '今日考勤',
      'markdown': '# 今日考勤\n\n- 全员正常',
      'createdAt': '2026-10-18T09:00:00Z',
    });
    await settle();
    final noteIndex = storage.puts.indexOf('note.md');
    final manifestIndex = storage.puts.indexOf('index.json');
    expect(noteIndex, isNonNegative);
    expect(manifestIndex, greaterThan(noteIndex));
    final manifest = String.fromCharCodes(storage.objects['index.json']!);
    expect(manifest, contains('"adminNote"'));
    expect(manifest, contains('"version":"v1"'));
  });

  test('auto upload can be switched off in settings', () async {
    final store = Workspace.memory();
    final storage = FakeStorage();
    final sync = SyncService(
      store,
      storageFactory: () async => storage,
      debounce: const Duration(milliseconds: 20),
    );
    sync.attach();
    addTearDown(sync.dispose);

    store.settings['autoUpload'] = false;
    await store.savePerson('王琪');
    await settle();
    expect(storage.puts, isEmpty);

    store.settings['autoUpload'] = true;
    final ok = await sync.upload(manual: true);
    expect(ok, isTrue);
    expect(storage.puts, contains('data/workspace.json'));
  });

  test('unconfigured storage reports a quiet state instead of failing', () async {
    final store = Workspace.memory();
    final sync = SyncService(
      store,
      storageFactory: () async => null,
      debounce: const Duration(milliseconds: 20),
    );
    sync.attach();
    addTearDown(sync.dispose);

    await store.savePerson('李航');
    await settle();
    expect(sync.phase, SyncPhase.unconfigured);
    expect(store.pendingDays, isNotEmpty);
    expect(sync.label, contains('本机'));
  });

  test('pull-to-refresh reports up to date when hashes match', () async {
    final store = Workspace.memory();
    final storage = FakeStorage();
    final sync = SyncService(
      store,
      storageFactory: () async => storage,
      debounce: const Duration(milliseconds: 20),
    );
    sync.attach();
    addTearDown(sync.dispose);

    await store.savePerson('林晓');
    await settle();

    final outcome = await sync.refresh();
    expect(outcome.ok, isTrue);
    expect(outcome.message, contains('已是最新'));
  });

  test('pull-to-refresh downloads the cloud snapshot when local is clean',
      () async {
    final store = Workspace.memory();
    final storage = FakeStorage();
    final sync = SyncService(
      store,
      storageFactory: () async => storage,
      debounce: const Duration(milliseconds: 20),
    );
    sync.attach();
    addTearDown(sync.dispose);

    await store.savePerson('林晓');
    await settle();

    // Simulate another device publishing a bigger workspace.
    final payload =
        jsonDecode(String.fromCharCodes(storage.objects['data/workspace.json']!))
            as Map<String, dynamic>;
    (payload['people'] as List).add({
      'id': 'remote-1',
      'name': '周宁',
      'gender': '男',
      'employeeId': 'EMP-9001',
      'active': true,
    });
    final bytes = utf8.encode(jsonEncode(payload));
    storage.objects['data/workspace.json'] = bytes;
    final hash = sha256.convert(bytes).toString();
    storage.objects['index.json'] = utf8.encode(
      jsonEncode({
        'schema': 1,
        'data': {'hash': hash, 'updatedAt': '2026-10-18T02:00:00Z'},
      }),
    );

    final outcome = await sync.refresh();
    expect(outcome.ok, isTrue);
    expect(outcome.message, contains('云端版本'));
    expect(store.people.map((p) => p.name), contains('周宁'));
    expect(store.pendingDays, isEmpty);
  });
}