import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

String businessDay([DateTime? instant]) => (instant ?? DateTime.now())
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);
const statuses = ['正常', '迟到', '早退', '请假', '缺勤'];

class Person {
  Person(this.id, this.name, {this.gender = '', this.employeeId = '', this.active = true, this.deleted = false});
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

/// SQLite-backed UI workspace. Credentials are intentionally excluded.
class Workspace extends ChangeNotifier {
  Workspace.memory();
  Database? _db;
  String dataPath = '内存（测试）';
  String identity = '';
  String deviceId = const Uuid().v4();
  List<Person> people = [];
  List<Entry> entries = [];
  Map<String, dynamic> settings = {
    'provider': 'COS',
    'autoUpdate': true,
    'glass': true,
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
    }
  }

  Future<void> persist() async {
    await _db?.insert('workspace', {
      'id': 1,
      'payload': jsonEncode({
        'identity': identity,
        'deviceId': deviceId,
        'people': people.map((p) => p.toJson()).toList(),
        'entries': entries.map((p) => p.toJson()).toList(),
        'settings': settings,
        'pendingDays': pendingDays.toList(),
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> setIdentity(String value) async {
    identity = value.trim();
    await persist();
  }

  Future<void> savePerson(String name, {Person? person}) async {
    name = name.trim();
    if (name.isEmpty) throw const FormatException('姓名不能为空');
    if (visiblePeople.any((p) => p.id != person?.id && p.name == name)) {
      throw const FormatException('已有同名人员，请使用可区分的姓名');
    }
    if (person == null) {
      people.add(Person(const Uuid().v4(), name));
    } else {
      person.name = name;
    }
    pendingDays.add('人员名单');
    await persist();
  }

  Future<void> updatePeople(List<Person> selected, {String? gender, String? employeeId}) async {
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
