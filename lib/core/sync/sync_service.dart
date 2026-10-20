import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../config/object_layout.dart';
import '../data/workspace.dart';
import '../result/app_result.dart';
import '../storage/object_storage.dart';

/// Upload state surfaced in the home strip, the sync page and settings.
enum SyncPhase { idle, uploading, synced, failed, unconfigured }

/// Write-through sync: every local business change is uploaded shortly after it
/// is persisted, so "保存" and "上云" are one action instead of two.
///
/// The service listens to [Workspace]; a save marks [Workspace.pendingDays],
/// which schedules a debounced upload. Bursts of edits collapse into one
/// request pair, and failures keep the pending queue intact for a later retry
/// (next edit, app start or the manual button).
class SyncService extends ChangeNotifier {
  SyncService(
    this.store, {
    required this.storageFactory,
    this.debounce = const Duration(milliseconds: 700),
  });
  final Workspace store;

  /// Resolved lazily on every upload so credentials edited in settings are
  /// picked up without restarting the app.
  final Future<ObjectStorage?> Function() storageFactory;
  final Duration debounce;

  SyncPhase phase = SyncPhase.idle;
  String message = '';
  DateTime? lastSuccessAt;
  int uploadedBytes = 0;

  Timer? _timer;
  bool _busy = false;

  /// Set while this service itself writes to the store (clearing the pending
  /// queue), so its own notifications do not schedule another upload.
  bool _muted = false;

  bool get enabled => store.settings['autoUpload'] != false;

  int get pendingCount => store.pendingDays.length;

  /// Short label for the home status strip.
  String get label => switch (phase) {
    SyncPhase.uploading => '正在上传…',
    SyncPhase.synced => '已自动同步',
    SyncPhase.failed => '上传失败，稍后自动重试',
    SyncPhase.unconfigured => '未配置对象存储，仅保存在本机',
    SyncPhase.idle => pendingCount == 0 ? '本地数据已是最新' : '$pendingCount 项变更待上传',
  };

  void attach() {
    store.addListener(_onStoreChanged);
    if (pendingCount > 0) _schedule();
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onStoreChanged() {
    if (_muted || !enabled) return;
    if (pendingCount == 0) return;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(upload());
    });
  }

  /// Uploads the sharded workspace files and the manifest. Safe to call manually.
  Future<bool> upload({bool manual = false}) async {
    if (_busy) return false;
    if (pendingCount == 0 && !manual) return true;
    _busy = true;
    _emit(SyncPhase.uploading, '正在上传到云端…');
    var ok = false;
    try {
      final storage = await storageFactory();
      if (storage == null) {
        _emit(SyncPhase.unconfigured, '未配置 COS 直链或密钥，数据仅保存在本机');
        return false;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      // A person deleted on another device must not be resurrected by this
      // device's next upload, so remote tombstones are folded in first.
      await _absorbRemoteDeletions(storage);
      final files = _shardedFiles(store, now: now);
      final fileHashes = <String, String>{};
      uploadedBytes = 0;
      for (final entry in files.entries) {
        final hash = sha256.convert(entry.value).toString();
        fileHashes[entry.key] = hash;
        uploadedBytes += entry.value.length;
        final put = await storage.put(entry.key, entry.value, sha256: hash);
        if (put is Failure) {
          _emit(SyncPhase.failed, '上传 ${entry.key} 失败：${put.message}');
          return false;
        }
      }
      final snapshotHash = sha256
          .convert(utf8.encode(jsonEncode(_cloudPayload(store))))
          .toString();

      // Publish the admin notice body first so the manifest never points at a
      // stale note.
      final drafts = store.noticeOutbox;
      if (drafts.isNotEmpty) {
        final note = drafts.last['markdown']?.toString() ?? '';
        if (note.isNotEmpty) {
          final noteBytes = utf8.encode(note);
          final notePut = await storage.put(
            ObjectLayout.adminNote,
            noteBytes,
            sha256: sha256.convert(noteBytes).toString(),
          );
          if (notePut is Failure) {
            _emit(SyncPhase.failed, '上传通知失败：${notePut.message}');
            return false;
          }
        }
      }

      // Only advertise note.md when this upload actually wrote it, otherwise
      // other devices would fetch a missing object.
      final NoticeRefJson? admin = drafts.isEmpty ? null : _noticeRef('admin');
      final NoticeRefJson? dev = _noticeRef('dev');
      final manifest = <String, dynamic>{
        'schema': 1,
        'generatedAt': now,
        'data': {'hash': snapshotHash, 'updatedAt': now, 'files': fileHashes},
        if (admin != null) 'adminNote': admin.toJson(),
        if (dev != null) 'devNote': dev.toJson(),
      };
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      final manifestPut = await storage.put(
        ObjectLayout.index,
        manifestBytes,
        sha256: sha256.convert(manifestBytes).toString(),
      );
      if (manifestPut is Failure) {
        _emit(SyncPhase.failed, '上传清单失败：${manifestPut.message}');
        return false;
      }

      _muted = true;
      try {
        store.pendingDays.clear();
        store.lastSync = now;
        store.syncMessage = '已自动上传';
        await store.persist();
      } finally {
        _muted = false;
      }
      lastSuccessAt = DateTime.now();
      ok = true;
      _emit(SyncPhase.synced, '已自动同步');
    } on Object catch (error) {
      _emit(SyncPhase.failed, '上传失败：$error');
    } finally {
      _busy = false;
    }
    // A change made while the upload was in flight stays pending; schedule one
    // more pass. Failed uploads are left to the manual button or app start so a
    // bad credential cannot spin in a retry loop.
    if (ok && pendingCount > 0) _schedule();
    return ok;
  }

  /// Pull-to-refresh entry point: push pending edits, then compare the remote
  /// manifest with the local shard hashes and pull the changed cloud files when the local
  /// side has nothing unsaved.
  Future<SyncOutcome> refresh() async {
    if (_busy) return const SyncOutcome(false, '正在同步，请稍候');
    if (pendingCount > 0) {
      final ok = await upload(manual: true);
      if (!ok) return SyncOutcome(false, message);
    }
    try {
      final storage = await storageFactory();
      if (storage == null) return const SyncOutcome(false, '未配置对象存储，仅保存在本机');
      final manifestResult = await storage.get(ObjectLayout.index);
      if (manifestResult case Failure(:final message)) {
        return SyncOutcome(false, '读取清单失败：$message');
      }
      final manifestBytes =
          (manifestResult as Success<RemoteObject?>).value?.bytes;
      if (manifestBytes == null || manifestBytes.isEmpty) {
        _emit(SyncPhase.synced, '云端暂无数据');
        return const SyncOutcome(true, '云端暂无数据，本地版本已就绪');
      }
      final manifest = jsonDecode(utf8.decode(manifestBytes));
      final remoteHash = manifest is Map
          ? (manifest['data'] is Map
                ? (manifest['data']['hash']?.toString() ?? '')
                : '')
          : '';
      final localHash = sha256
          .convert(utf8.encode(jsonEncode(_cloudPayload(store))))
          .toString();
      final now = DateTime.now().toUtc().toIso8601String();
      if (remoteHash == localHash) {
        store.lastSync = now;
        store.syncMessage = '已是最新';
        _emit(SyncPhase.synced, '已是最新');
        return const SyncOutcome(true, '已是最新');
      }
      final data = manifest is Map && manifest['data'] is Map
          ? Map<String, dynamic>.from(manifest['data'] as Map)
          : <String, dynamic>{};
      final fileMap = data['files'] is Map
          ? Map<String, dynamic>.from(data['files'] as Map)
          : <String, dynamic>{};
      if (fileMap.isEmpty) {
        return const SyncOutcome(false, '云端清单没有数据分片');
      }
      final shardBytes = <String, List<int>>{};
      for (final key in fileMap.keys.map((k) => k.toString())) {
        final result = await storage.get(key);
        if (result case Failure(:final message)) {
          return SyncOutcome(false, '下载 $key 失败：$message');
        }
        final bytes = (result as Success<RemoteObject?>).value?.bytes;
        if (bytes == null || bytes.isEmpty) {
          return SyncOutcome(false, '云端分片为空：$key');
        }
        shardBytes[key] = bytes;
      }
      final payload = _payloadFromShards(shardBytes);
      final remoteCanonical = sha256
          .convert(utf8.encode(jsonEncode(_project(payload))))
          .toString();
      if (remoteCanonical == localHash) {
        store.lastSync = now;
        store.syncMessage = '已是最新';
        _emit(SyncPhase.synced, '已是最新');
        return const SyncOutcome(true, '已是最新');
      }
      if (pendingCount > 0) {
        return const SyncOutcome(true, '本地有变更待上传，稍后再刷新');
      }
      _muted = true;
      try {
        await store.loadPayload(payload);
        store.lastSync = now;
        store.syncMessage = '已更新为云端版本';
        await store.persist();
      } finally {
        _muted = false;
      }
      _emit(SyncPhase.synced, '已更新为云端版本');
      return const SyncOutcome(true, '已更新为云端版本');
    } on Object catch (error) {
      _emit(SyncPhase.failed, '刷新失败：$error');
      return SyncOutcome(false, '刷新失败：$error');
    }
  }

  /// Business data only. Identity, device id, settings, the pending queue, the
  /// last-sync stamp and the notice read-check bookkeeping are all per-device
  /// state: syncing them makes the hash drift after every launch and lets one
  /// device overwrite another's preferences.
  static Map<String, dynamic> _cloudPayload(Workspace store) =>
      _project(store.toPayload());

  /// People are uploaded as live records only; deletions travel as light
  /// tombstones (`id`, `name`, `deletedAt`) so another device cannot resurrect
  /// them. Tombstones older than [tombstoneDays] are dropped from the cloud.
  static const int tombstoneDays = 30;

  static Map<String, List<int>> _shardedFiles(
    Workspace store, {
    required String now,
  }) {
    final live = <Map<String, dynamic>>[];
    final tombstones = <Map<String, dynamic>>[];
    final cutoff = DateTime.now().toUtc().subtract(
      const Duration(days: tombstoneDays),
    );
    for (final person in store.people) {
      if (!person.deleted) {
        live.add(person.toJson());
        continue;
      }
      final deletedAt = DateTime.tryParse(person.deletedAt);
      if (deletedAt != null && deletedAt.isBefore(cutoff)) continue;
      tombstones.add({
        'id': person.id,
        'name': person.name,
        // Legacy tombstones have no stamp; give them one so they age out too.
        'deletedAt': person.deletedAt.isEmpty ? now : person.deletedAt,
      });
    }
    final entriesByDay = <String, List<Map<String, dynamic>>>{};
    for (final entry in store.entries) {
      entriesByDay.putIfAbsent(entry.day, () => []).add(entry.toJson());
    }
    final leavesByMonth = <String, Map<String, Leave>>{};
    for (final leave in store.leaves) {
      final start = DateTime.tryParse(leave.startDay);
      final end = DateTime.tryParse(leave.endDay);
      if (start == null || end == null) continue;
      var cursor = DateTime(start.year, start.month);
      final last = DateTime(end.year, end.month);
      while (!cursor.isAfter(last)) {
        final month =
            '${cursor.year.toString().padLeft(4, '0')}-'
            '${cursor.month.toString().padLeft(2, '0')}';
        leavesByMonth.putIfAbsent(month, () => {})[leave.id] = leave;
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
    }

    final result = <String, List<int>>{
      ObjectLayout.people: utf8.encode(
        jsonEncode({
          'schema': 1,
          'updatedAt': now,
          'people': live,
          if (tombstones.isNotEmpty) 'deleted': tombstones,
        }),
      ),
    };
    for (final day in entriesByDay.keys) {
      result[ObjectLayout.record(day)] = utf8.encode(
        jsonEncode({
          'schema': 1,
          'day': day,
          'updatedAt': now,
          'entries': entriesByDay[day],
        }),
      );
    }
    for (final month in leavesByMonth.keys) {
      result[ObjectLayout.leaveMonth(month)] = utf8.encode(
        jsonEncode({
          'schema': 1,
          'month': month,
          'updatedAt': now,
          'leaves': leavesByMonth[month]!.values
              .map((l) => l.toJson())
              .toList(),
        }),
      );
    }
    return result;
  }

  /// Folds tombstones already present in the bucket into the local workspace
  /// before an upload, so a device that has not pulled yet cannot re-add a
  /// person another device deleted. Handles both the current `deleted` array
  /// and old shards that still carried `people` with `deleted: true`.
  Future<void> _absorbRemoteDeletions(ObjectStorage storage) async {
    final result = await storage.get(ObjectLayout.people);
    if (result is! Success<RemoteObject?> || result.value == null) return;
    Map<String, dynamic>? shard;
    try {
      final decoded = jsonDecode(utf8.decode(result.value!.bytes));
      if (decoded is Map) shard = Map<String, dynamic>.from(decoded);
    } on Object {
      return;
    }
    if (shard == null) return;
    final removed = <String, String>{};
    for (final item in (shard['deleted'] as List?) ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      removed[id] = item['deletedAt']?.toString() ?? '';
    }
    for (final item in (shard['people'] as List?) ?? const <dynamic>[]) {
      if (item is! Map || item['deleted'] != true) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      removed[id] = item['deletedAt']?.toString() ?? '';
    }
    if (removed.isEmpty) return;
    var changed = false;
    for (final person in store.people) {
      if (person.deleted || !removed.containsKey(person.id)) continue;
      person.deleted = true;
      person.active = false;
      person.deletedAt = removed[person.id]!.isEmpty
          ? DateTime.now().toUtc().toIso8601String()
          : removed[person.id]!;
      changed = true;
    }
    if (!changed) return;
    _muted = true;
    try {
      await store.persist();
    } finally {
      _muted = false;
    }
  }

  static Map<String, dynamic> _payloadFromShards(Map<String, List<int>> files) {
    final peopleJson = files[ObjectLayout.people];
    final peopleShard = peopleJson == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(utf8.decode(peopleJson)) as Map);
    final live = (peopleShard['people'] as List?) ?? const <dynamic>[];
    // Tombstones come back as deleted people so old entries keep their names
    // and the local list never silently re-adds the person.
    final removed = (peopleShard['deleted'] as List?) ?? const <dynamic>[];
    final people = <Map<String, dynamic>>[
      for (final person in live)
        if (person is Map) Map<String, dynamic>.from(person),
      for (final tombstone in removed)
        if (tombstone is Map)
          {
            'id': tombstone['id'],
            'name': tombstone['name'] ?? '',
            'gender': '',
            'employeeId': '',
            'active': false,
            'deleted': true,
            'deletedAt': tombstone['deletedAt'] ?? '',
          },
    ];
    final entries = <dynamic>[];
    final leavesById = <String, dynamic>{};
    for (final item in files.entries) {
      if (item.key.startsWith('${ObjectLayout.recordsRoot}/')) {
        final payload = jsonDecode(utf8.decode(item.value));
        if (payload is Map && payload['entries'] is List) {
          entries.addAll(payload['entries'] as List);
        }
      } else if (item.key.startsWith('${ObjectLayout.leavesRoot}/')) {
        final payload = jsonDecode(utf8.decode(item.value));
        if (payload is Map && payload['leaves'] is List) {
          for (final leave in payload['leaves'] as List) {
            if (leave is Map) {
              final id = leave['id']?.toString() ?? '';
              if (id.isNotEmpty) leavesById[id] = leave;
            }
          }
        }
      }
    }
    return {
      'schema': 1,
      'people': people,
      'entries': entries,
      'leaves': leavesById.values.toList(),
    };
  }

  static Map<String, dynamic> _project(Map<String, dynamic> payload) {
    final notices = <String, dynamic>{};
    final source = payload['notices'];
    if (source is Map) {
      for (final entry in source.entries) {
        final key = entry.key.toString();
        // Published notice metadata only (note.md version/title/body).
        if (key.startsWith('note')) notices[key] = entry.value;
      }
    }
    return {
      'schema': 1,
      'people': payload['people'] ?? const [],
      'entries': payload['entries'] ?? const [],
      'leaves': payload['leaves'] ?? const [],
      if (notices.isNotEmpty) 'notices': notices,
    };
  }

  NoticeRefJson? _noticeRef(String channel) {
    final version = store.noticeVersion(channel);
    if (version.isEmpty) return null;
    return NoticeRefJson(
      version: version,
      path: channel == 'dev' ? ObjectLayout.devNote : ObjectLayout.adminNote,
      title: store.noticeTitle(channel),
      updatedAt: store.noticeUpdatedAt(channel),
    );
  }

  void _emit(SyncPhase next, String text) {
    phase = next;
    message = text;
    // Rebuild every page that listens to the workspace, without letting this
    // state change schedule another upload (a failed upload must not retry in
    // a tight loop).
    _muted = true;
    try {
      store.touch();
    } finally {
      _muted = false;
    }
    notifyListeners();
  }
}

/// Result of a pull-to-refresh round, ready to show inline in a page.
class SyncOutcome {
  const SyncOutcome(this.ok, this.message);
  final bool ok;
  final String message;
}

class NoticeRefJson {
  const NoticeRefJson({
    required this.version,
    required this.path,
    required this.title,
    required this.updatedAt,
  });
  final String version;
  final String path;
  final String title;
  final String updatedAt;

  Map<String, dynamic> toJson() => {
    'version': version,
    'path': path,
    if (title.isNotEmpty) 'title': title,
    if (updatedAt.isNotEmpty) 'updatedAt': updatedAt,
  };
}
