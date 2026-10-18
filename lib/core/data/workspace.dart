import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../update/update_config.dart';

String businessDay([DateTime? instant]) => (instant ?? DateTime.now())
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);
const statuses = ['正常', '迟到', '早退', '请假', '缺勤'];
const leaveTypes = ['事假', '病假', '年假', '调休', '婚假', '产假', '其他'];
const leaveStatuses = ['已确认', '待确认', '已取消'];

class Person {
  Person(
    this.id,
    this.name, {
    this.gender = '',
    this.employeeId = '',
    this.active = true,
    this.deleted = false,
  });
  final String id;
  String name;
  String gender;
  String employeeId;
  bool active;
  bool deleted;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'gender': gender,
    'employeeId': employeeId,
    'active': active,
    'deleted': deleted,
  };
  factory Person.fromJson(Map<String, dynamic> j) => Person(
    j['id'],
    j['name'],
    gender: j['gender'] ?? '',
    employeeId: j['employeeId'] ?? '',
    active: j['active'],
    deleted: j['deleted'] ?? false,
  );
}

class Entry {
  Entry({
    required this.id,
    required this.personId,
    required this.day,
    required this.fields,
    required this.author,
    required this.updatedAt,
    Map<String, String>? fieldTimes,
    List<String>? history,
    this.deleted = false,
  }) : fieldTimes = fieldTimes ?? {},
       history = history ?? [];
  final String id;
  final String personId;
  final String day;
  final Map<String, String> fields;
  final Map<String, String> fieldTimes;
  final String author;
  final String updatedAt;
  final List<String> history;
  final bool deleted;
  Map<String, dynamic> toJson() => {
    'id': id,
    'personId': personId,
    'day': day,
    'fields': fields,
    'author': author,
    'updatedAt': updatedAt,
    'fieldTimes': fieldTimes,
    'history': history,
    'deleted': deleted,
  };
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'],
    personId: j['personId'],
    day: j['day'],
    fields: Map<String, String>.from(j['fields']),
    author: j['author'],
    updatedAt: j['updatedAt'],
    fieldTimes: Map<String, String>.from(j['fieldTimes'] ?? {}),
    history: List<String>.from(j['history'] ?? []),
    deleted: j['deleted'] ?? false,
  );
}

/// A confirmed leave interval. Only `已确认` leaves block attendance entry for
/// the covered days; `待确认` and `已取消` stay editable without side effects.
class Leave {
  Leave({
    required this.id,
    required this.personId,
    required this.startDay,
    required this.endDay,
    required this.type,
    required this.status,
    this.reason = '',
    required this.author,
    required this.updatedAt,
    List<String>? history,
    this.deleted = false,
  }) : history = history ?? [];
  final String id;
  final String personId;
  final String startDay;
  final String endDay;
  final String type;
  final String status;
  final String reason;
  final String author;
  final String updatedAt;
  final List<String> history;
  final bool deleted;

  bool get confirmed => !deleted && status == '已确认';
  bool covers(String day) =>
      day.compareTo(startDay) >= 0 && day.compareTo(endDay) <= 0;
  int get dayCount {
    final start = DateTime.tryParse(startDay);
    final end = DateTime.tryParse(endDay);
    if (start == null || end == null) return 0;
    return end.difference(start).inDays + 1;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'personId': personId,
    'startDay': startDay,
    'endDay': endDay,
    'type': type,
    'status': status,
    'reason': reason,
    'author': author,
    'updatedAt': updatedAt,
    'history': history,
    'deleted': deleted,
  };
  factory Leave.fromJson(Map<String, dynamic> j) => Leave(
    id: j['id'],
    personId: j['personId'],
    startDay: j['startDay'],
    endDay: j['endDay'],
    type: j['type'] ?? '事假',
    status: j['status'] ?? '已确认',
    reason: j['reason'] ?? '',
    author: j['author'] ?? '',
    updatedAt: j['updatedAt'] ?? '',
    history: List<String>.from(j['history'] ?? []),
    deleted: j['deleted'] ?? false,
  );
}

/// SQLite-backed UI workspace. Credentials are intentionally excluded.
class Workspace extends ChangeNotifier {
  Workspace.memory();

  /// QA helper: build with `--dart-define=DEMO_SEED=true` to fill an empty
  /// device with demo people/records/leaves for layout review. Off by default,
  /// so normal builds still start without sample business data.
  static const demoSeed = bool.fromEnvironment('DEMO_SEED');

  Database? _db;
  bool get persistent => _db != null;
  String dataPath = '内存（测试）';
  String identity = '';
  String deviceId = const Uuid().v4();
  List<Person> people = [];
  List<Entry> entries = [];
  Map<String, dynamic> settings = {
    'provider': 'COS',
    'autoUpdate': true,
    'glass': true,
    ...UpdateDefaults.settings,
  };
  final List<Entry> remoteEntries = [];
  final Set<String> pendingDays = {};
  String? lastSync;
  String syncMessage = '尚未配置对象存储，数据保存在本机';
  String name(String id) =>
      people.where((p) => p.id == id).firstOrNull?.name ?? '已移除人员';
  List<Person> get visiblePeople => people.where((p) => !p.deleted).toList();
  List<Person> get activePeople =>
      people.where((p) => p.active && !p.deleted).toList();
  List<Entry> get liveEntries => entries.where((e) => !e.deleted).toList();
  Entry? record(String personId, String day) => liveEntries
      .where((e) => e.personId == personId && e.day == day)
      .firstOrNull;

  List<Leave> leaves = [];

  /// Last read versions and bodies for the two notification channels, plus the
  /// local outbox of admin notices waiting for an upload adapter.
  Map<String, dynamic> notices = {
    'adminVersion': '',
    'devVersion': '',
    'adminTitle': '',
    'devTitle': '',
    'adminBody': '',
    'devBody': '',
    'adminUpdatedAt': '',
    'devUpdatedAt': '',
    'lastCheck': '',
    'lastResult': '尚未检查通知',
    'dataHash': '',
    'outbox': <dynamic>[],
  };

  List<Leave> get liveLeaves => leaves.where((l) => !l.deleted).toList();
  List<Leave> leavesOn(String day) =>
      liveLeaves.where((l) => l.confirmed && l.covers(day)).toList();
  Leave? leaveOf(String personId, String day) => liveLeaves
      .where((l) => l.confirmed && l.personId == personId && l.covers(day))
      .firstOrNull;
  bool onLeave(String personId, String day) => leaveOf(personId, day) != null;

  /// Leaves overlapping the inclusive [from]..[to] range.
  List<Leave> leavesInRange(String from, String to) => liveLeaves
      .where(
        (l) =>
            l.confirmed &&
            l.startDay.compareTo(to) <= 0 &&
            l.endDay.compareTo(from) >= 0,
      )
      .toList();

  /// Calendar marks: every confirmed leave day inside the range.
  Set<String> leaveDaysIn(String from, String to) {
    final days = <String>{};
    for (final leave in leavesInRange(from, to)) {
      final start = leave.startDay.compareTo(from) < 0 ? from : leave.startDay;
      final end = leave.endDay.compareTo(to) > 0 ? to : leave.endDay;
      for (
        var d = DateTime.parse(start);
        !d.isAfter(DateTime.parse(end));
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        days.add(d.toIso8601String().substring(0, 10));
      }
    }
    return days;
  }

  int leavePeopleIn(String from, String to) =>
      leavesInRange(from, to).map((l) => l.personId).toSet().length;

  int leaveDaysCountIn(String from, String to) {
    var total = 0;
    for (final leave in leavesInRange(from, to)) {
      final start = leave.startDay.compareTo(from) < 0 ? from : leave.startDay;
      final end = leave.endDay.compareTo(to) > 0 ? to : leave.endDay;
      final a = DateTime.tryParse(start);
      final b = DateTime.tryParse(end);
      if (a == null || b == null) continue;
      total += b.difference(a).inDays + 1;
    }
    return total;
  }

  Map<String, int> leaveDaysByType(String from, String to) {
    final counts = <String, int>{};
    for (final leave in leavesInRange(from, to)) {
      final start = leave.startDay.compareTo(from) < 0 ? from : leave.startDay;
      final end = leave.endDay.compareTo(to) > 0 ? to : leave.endDay;
      final a = DateTime.tryParse(start);
      final b = DateTime.tryParse(end);
      if (a == null || b == null) continue;
      counts[leave.type] =
          (counts[leave.type] ?? 0) + b.difference(a).inDays + 1;
    }
    return counts;
  }

  String noticeVersion(String channel) =>
      notices['${channel}Version'] as String? ?? '';
  String noticeTitle(String channel) =>
      notices['${channel}Title'] as String? ?? '';
  String noticeBody(String channel) =>
      notices['${channel}Body'] as String? ?? '';
  String noticeUpdatedAt(String channel) =>
      notices['${channel}UpdatedAt'] as String? ?? '';

  List<Map<String, dynamic>> get noticeOutbox => [
    for (final item in (notices['outbox'] as List? ?? const []))
      if (item is Map) Map<String, dynamic>.from(item),
  ];

  Future<void> saveNotice(
    String channel, {
    required String version,
    required String title,
    required String body,
    String updatedAt = '',
  }) async {
    notices['${channel}Version'] = version;
    notices['${channel}Title'] = title;
    notices['${channel}Body'] = body;
    notices['${channel}UpdatedAt'] = updatedAt;
    notices['lastCheck'] = DateTime.now().toUtc().toIso8601String();
    await persist();
  }

  Future<void> setNoticeState({
    String? lastResult,
    String? dataHash,
    bool markChecked = true,
  }) async {
    if (lastResult != null) notices['lastResult'] = lastResult;
    if (dataHash != null) notices['dataHash'] = dataHash;
    if (markChecked) {
      notices['lastCheck'] = DateTime.now().toUtc().toIso8601String();
    }
    await persist();
  }

  /// Queue an admin notice for upload and mirror it locally so the author can
  /// preview exactly what other devices will receive.
  Future<void> queueNotice(Map<String, dynamic> draft) async {
    final outbox = notices['outbox'] is List
        ? notices['outbox'] as List
        : (notices['outbox'] = <dynamic>[]);
    outbox.add(draft);
    notices['adminVersion'] = draft['version'];
    notices['adminTitle'] = draft['title'];
    notices['adminBody'] = draft['markdown'];
    notices['adminUpdatedAt'] = draft['createdAt'];
    pendingDays.add('通知');
    await persist();
  }

  Future<void> saveLeave({
    Leave? leave,
    required String personId,
    required String startDay,
    required String endDay,
    required String type,
    required String status,
    String reason = '',
  }) async {
    if (identity.trim().isEmpty) throw const FormatException('请先填写本地显示名');
    if (personId.isEmpty) throw const FormatException('请选择请假人员');
    if (startDay.compareTo(endDay) > 0) {
      throw const FormatException('开始日期不能晚于结束日期');
    }
    if (!leaveTypes.contains(type)) throw const FormatException('请假类型无效');
    if (!leaveStatuses.contains(status)) throw const FormatException('请假状态无效');
    if (status == '已确认') {
      final overlap = liveLeaves
          .where(
            (l) =>
                l.id != leave?.id &&
                l.confirmed &&
                l.personId == personId &&
                l.startDay.compareTo(endDay) <= 0 &&
                l.endDay.compareTo(startDay) >= 0,
          )
          .firstOrNull;
      if (overlap != null) {
        throw FormatException(
          '${name(personId)} 在 ${overlap.startDay} 至 ${overlap.endDay} 已有确认请假',
        );
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final record = Leave(
      id: leave?.id ?? const Uuid().v4(),
      personId: personId,
      startDay: startDay,
      endDay: endDay,
      type: type,
      status: status,
      reason: reason.trim(),
      author: identity,
      updatedAt: now,
      history: [
        ...?leave?.history,
        '$now · $identity · ${leave == null ? '新增请假' : '修改请假'}'
            '（$type · $status · $startDay→$endDay）',
      ],
    );
    leaves.removeWhere((l) => l.id == record.id);
    leaves.add(record);
    pendingDays.add('请假记录');
    await persist();
  }

  Future<void> deleteLeave(Leave leave) async {
    if (identity.trim().isEmpty) throw const FormatException('请先填写本地显示名');
    final now = DateTime.now().toUtc().toIso8601String();
    leaves.removeWhere((l) => l.id == leave.id);
    leaves.add(
      Leave(
        id: leave.id,
        personId: leave.personId,
        startDay: leave.startDay,
        endDay: leave.endDay,
        type: leave.type,
        status: leave.status,
        reason: leave.reason,
        author: identity,
        updatedAt: now,
        history: [...leave.history, '$now · $identity · 删除请假记录'],
        deleted: true,
      ),
    );
    pendingDays.add('请假记录');
    await persist();
  }

  /// Persist the default deduction rules used by the statistics page. Rules
  /// are a local preference, so no author stamp is required.
  Future<void> saveScoreRules(Map<String, dynamic> rules) async {
    settings['scoreRules'] = rules;
    await persist();
  }

  Future<void> open({String? path}) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    dataPath =
        path ??
        p.join((await getApplicationSupportDirectory()).path, 'qingluan.db');
    _db = await openDatabase(
      dataPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE workspace (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
        );
      },
    );
    final rows = await _db!.query('workspace', where: 'id = 1');
    if (rows.isNotEmpty) {
      final j =
          jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
      identity = j['identity'];
      deviceId = j['deviceId'];
      people = (j['people'] as List).map((p) => Person.fromJson(p)).toList();
      entries = (j['entries'] as List).map((p) => Entry.fromJson(p)).toList();
      settings.addAll(Map<String, dynamic>.from(j['settings']));
      pendingDays.addAll(List<String>.from(j['pendingDays'] ?? []));
      leaves = ((j['leaves'] as List?) ?? const [])
          .map((item) => Leave.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (j['notices'] is Map) {
        notices.addAll(Map<String, dynamic>.from(j['notices'] as Map));
      }
    }
    UpdateDefaults.apply(settings);
    if (demoSeed && people.isEmpty && entries.isEmpty) {
      await _seedDemo();
      await persist();
    }
  }

  Future<void> _seedDemo() async {
    identity = '管理员';
    const names = ['林晓', '周宁', '陈默', '赵敏', '王琪', '李航'];
    people = [
      for (var i = 0; i < names.length; i++)
        Person(
          const Uuid().v4(),
          names[i],
          employeeId: 'EMP-${1024 + i}',
          active: i != names.length - 1,
        ),
    ];
    final now = DateTime.now();
    final today = businessDay(now);
    final yesterday = businessDay(now.subtract(const Duration(days: 1)));
    final twoDaysAgo = businessDay(now.subtract(const Duration(days: 2)));
    final stamp = now.toUtc().toIso8601String();

    void entry(String personId, String day, Map<String, String> fields) {
      entries.add(
        Entry(
          id: const Uuid().v4(),
          personId: personId,
          day: day,
          fields: fields,
          author: identity,
          updatedAt: stamp,
          fieldTimes: {for (final key in fields.keys) key: stamp},
          history: ['$stamp · $identity · 保存登记（演示数据）'],
        ),
      );
    }

    entry(people[0].id, today, {
      'in': '08:58',
      'out': '',
      'status': '正常',
      'note': '',
    });
    entry(people[1].id, today, {
      'in': '09:26',
      'out': '',
      'status': '迟到',
      'note': '地铁延误',
    });
    entry(people[2].id, today, {
      'in': '08:45',
      'out': '',
      'status': '正常',
      'note': '',
    });
    entry(people[0].id, yesterday, {
      'in': '09:00',
      'out': '18:05',
      'status': '正常',
      'note': '',
    });
    entry(people[1].id, yesterday, {
      'in': '09:00',
      'out': '17:20',
      'status': '早退',
      'note': '',
    });
    entry(people[2].id, twoDaysAgo, {
      'in': '08:52',
      'out': '18:30',
      'status': '正常',
      'note': '月末盘点',
    });

    Leave leave(
      String personId,
      String startDay,
      String endDay,
      String type,
      String status,
      String reason,
    ) => Leave(
      id: const Uuid().v4(),
      personId: personId,
      startDay: startDay,
      endDay: endDay,
      type: type,
      status: status,
      reason: reason,
      author: identity,
      updatedAt: stamp,
      history: ['$stamp · $identity · 新增请假（演示数据）'],
    );

    leaves = [
      leave(
        people[3].id,
        today,
        businessDay(now.add(const Duration(days: 1))),
        '事假',
        '已确认',
        '家中有事',
      ),
      leave(people[4].id, yesterday, today, '年假', '已确认', '年假余额清零'),
      leave(
        people[0].id,
        businessDay(now.add(const Duration(days: 3))),
        businessDay(now.add(const Duration(days: 4))),
        '调休',
        '已确认',
        '周末值班调休',
      ),
      leave(people[2].id, today, today, '病假', '待确认', '上午就诊'),
    ];
    notices['adminTitle'] = '本周考勤与调休安排';
    notices['adminBody'] =
        '''# 本周考勤与调休安排

> 管理员 · $today · 管理员通知

- 本周调休已排定，请核对本人记录
- 请假当天不再登记考勤，如需变更请调整请假状态
- **周五 17:00 前**完成补录

---
*演示数据，仅用于界面检查。*
''';
    notices['adminVersion'] = 'demo-admin';
    notices['devTitle'] = '1.0.0 更新说明';
    notices['devBody'] = '''# 1.0.0 更新说明

- 新增请假记录与数据统计
- 底栏磨砂玻璃与深色配色调整
- 通知面板支持 Markdown''';
    notices['devVersion'] = 'demo-dev';
    notices['lastResult'] = '演示数据已载入';
    pendingDays.addAll([today, yesterday]);
  }

  Future<void> persist() async {
    await _db?.insert('workspace', {
      'id': 1,
      'payload': jsonEncode(toPayload()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Map<String, dynamic> toPayload() => {
    'identity': identity,
    'deviceId': deviceId,
    'people': people.map((p) => p.toJson()).toList(),
    'entries': entries.map((p) => p.toJson()).toList(),
    'leaves': leaves.map((l) => l.toJson()).toList(),
    'notices': notices,
    'settings': settings,
    'pendingDays': pendingDays.toList(),
  };

  Future<void> loadPayload(Map<String, dynamic> j) async {
    identity = j['identity']?.toString() ?? identity;
    deviceId = j['deviceId']?.toString() ?? deviceId;
    people = ((j['people'] as List?) ?? const [])
        .map((p) => Person.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    entries = ((j['entries'] as List?) ?? const [])
        .map((p) => Entry.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    leaves = ((j['leaves'] as List?) ?? const [])
        .map((p) => Leave.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    if (j['settings'] is Map) {
      settings.addAll(Map<String, dynamic>.from(j['settings'] as Map));
    }
    if (j['notices'] is Map) {
      notices.addAll(Map<String, dynamic>.from(j['notices'] as Map));
    }
    pendingDays
      ..clear()
      ..addAll(List<String>.from(j['pendingDays'] ?? const []));
    await persist();
  }

  Future<void> setIdentity(String value) async {
    identity = value.trim();
    await persist();
  }

  Future<void> savePerson(
    String name, {
    Person? person,
    String gender = '',
    String employeeId = '',
  }) async {
    name = name.trim();
    if (name.isEmpty) throw const FormatException('姓名不能为空');
    if (visiblePeople.any((p) => p.id != person?.id && p.name == name)) {
      throw const FormatException('已有同名人员，请使用可区分的姓名');
    }
    if (person == null) {
      people.add(
        Person(const Uuid().v4(), name, gender: gender, employeeId: employeeId),
      );
    } else {
      person.name = name;
      person.gender = gender.isEmpty ? person.gender : gender;
      person.employeeId = employeeId.isEmpty ? person.employeeId : employeeId;
    }
    pendingDays.add('人员名单');
    await persist();
  }

  Future<void> updatePeople(
    List<Person> selected, {
    String? gender,
    String? employeeId,
  }) async {
    for (final person in selected) {
      if (gender != null) person.gender = gender;
      if (employeeId != null) person.employeeId = employeeId;
    }
    pendingDays.add('人员名单');
    await persist();
  }

  Future<void> togglePerson(Person person) async {
    person.active = !person.active;
    pendingDays.add('人员名单');
    await persist();
  }

  /// Keep the person as a tombstone so historical attendance retains its name.
  Future<void> deletePerson(Person person) async {
    person.deleted = true;
    person.active = false;
    pendingDays.add('人员名单');
    await persist();
  }

  Future<void> saveEntries(
    List<String> personIds,
    String day,
    Map<String, String> fields,
  ) async {
    if (identity.trim().isEmpty) throw const FormatException('请先填写本地显示名');
    final blocked = personIds.where((id) => onLeave(id, day)).toList();
    if (blocked.isNotEmpty) {
      throw FormatException(
        '${blocked.map(name).join('、')} 当天为已确认请假，'
        '请先在请假记录中调整状态或时间',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    for (final personId in personIds) {
      final old = entries
          .where((e) => e.personId == personId && e.day == day)
          .firstOrNull;
      final times = Map<String, String>.from(old?.fieldTimes ?? {});
      if (old == null || old.deleted) times['deleted'] = now;
      for (final key in fields.keys) {
        if (old?.fields[key] != fields[key]) times[key] = now;
      }
      final entry = Entry(
        id: old?.id ?? const Uuid().v4(),
        personId: personId,
        day: day,
        fields: Map.of(fields),
        author: identity,
        updatedAt: now,
        fieldTimes: times,
        history: [...?old?.history, '$now · $identity · 保存登记（$deviceId）'],
      );
      entries.removeWhere((e) => e.id == entry.id);
      entries.add(entry);
    }
    pendingDays.add(day);
    await persist();
  }

  Future<void> deleteEntry(Entry entry) async {
    if (identity.trim().isEmpty) throw const FormatException('请先填写本地显示名');
    final now = DateTime.now().toUtc().toIso8601String();
    entries.removeWhere((e) => e.id == entry.id);
    entries.add(
      Entry(
        id: entry.id,
        personId: entry.personId,
        day: entry.day,
        fields: entry.fields,
        author: identity,
        updatedAt: now,
        fieldTimes: {...entry.fieldTimes, 'deleted': now},
        history: [...entry.history, '$now · $identity · 删除记录（$deviceId）'],
        deleted: true,
      ),
    );
    pendingDays.add(entry.day);
    await persist();
  }

  Future<void> close() async => _db?.close();

  Future<void> commitMerge(List<Entry> resolved, String day) async {
    if (identity.trim().isEmpty) throw const FormatException('请先填写本地显示名');
    final before = List<Entry>.of(entries);
    final pending = Set<String>.of(pendingDays);
    for (final entry in resolved) {
      entries.removeWhere((e) => e.personId == entry.personId && e.day == day);
      entries.add(entry);
    }
    pendingDays.add(day);
    try {
      await persist();
    } catch (_) {
      entries = before;
      pendingDays.clear();
      pendingDays.addAll(pending);
      rethrow;
    }
    remoteEntries.removeWhere((e) => e.day == day);
    notifyListeners();
  }
}
