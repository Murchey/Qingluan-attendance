import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'workspace.dart';

class ImportPreview {
  ImportPreview(
    this.names,
    this.issues, {
    this.gender = const {},
    this.employeeIds = const {},
  });
  final List<String> names;
  final List<String> issues;
  final Map<String, String> gender;
  final Map<String, String> employeeIds;
}

const _nameHeaders = {
  '姓名',
  '人员',
  '人员姓名',
  '员工姓名',
  '员工',
  '名字',
  '成员',
  'name',
  'employeename',
  'staffname',
};

const _genderHeaders = {'性别', 'gender', 'sex'};

const _idHeaders = {
  '工号',
  '员工号',
  '员工编号',
  '职工号',
  '编号',
  'employeeid',
  'staffid',
  'jobnumber',
};

String _normalizeHeader(Object? raw) {
  var text = (raw ?? '')
      .toString()
      .replaceAll('\uFEFF', '')
      .trim()
      .toLowerCase();
  text = text.replaceAll(RegExp(r'[\s*＊:：]'), '');
  text = text.replaceAll(RegExp(r'[（(].*?[）)]'), '');
  return text;
}

int _findColumn(List<dynamic> row, Set<String> aliases) =>
    row.indexWhere((cell) => aliases.contains(_normalizeHeader(cell)));

/// Parses a roster sheet or CSV. The header may appear after title rows; the
/// first row within the first 30 that contains a name column is used. A file
/// without a name column is rejected instead of guessing that its first column
/// is a name, which used to import arbitrary spreadsheets as people.
ImportPreview parsePeople(
  List<List<dynamic>> rows,
  Iterable<String> existing, {
  String source = '文件',
}) {
  if (rows.isEmpty) throw FormatException('$source没有内容');
  var headerRow = -1;
  var nameColumn = -1;
  final limit = rows.length < 30 ? rows.length : 30;
  for (var i = 0; i < limit; i++) {
    final column = _findColumn(rows[i], _nameHeaders);
    if (column >= 0) {
      headerRow = i;
      nameColumn = column;
      break;
    }
  }
  if (headerRow < 0) {
    throw FormatException(
      '$source未找到「姓名」列。请使用模板：第一行为列标题（姓名、性别、工号），从第二行开始填写人员。',
    );
  }
  final header = rows[headerRow];
  final genderColumn = _findColumn(header, _genderHeaders);
  final idColumn = _findColumn(header, _idHeaders);
  final seen = existing.toSet();
  final names = <String>[];
  final issues = <String>[];
  final genders = <String, String>{};
  final employeeIds = <String, String>{};
  for (var i = headerRow + 1; i < rows.length; i++) {
    final row = rows[i];
    final name =
        (nameColumn < row.length ? row[nameColumn] : null)
            ?.toString()
            .replaceAll('\uFEFF', '')
            .trim() ??
        '';
    if (name.isEmpty) {
      final hasData = row.any(
        (cell) => cell?.toString().trim().isNotEmpty ?? false,
      );
      if (hasData) issues.add('第 ${i + 1} 行缺少姓名');
      continue;
    }
    if (const {'姓名', '合计', '总计', '小计', '备注', '说明'}.contains(name)) {
      continue;
    }
    var importedName = name;
    if (!seen.add(importedName)) {
      var suffix = 1;
      while (seen.contains('$name$suffix')) {
        suffix++;
      }
      importedName = '$name$suffix';
      seen.add(importedName);
      issues.add('第 ${i + 1} 行“$name”重名，已保存为“$importedName”；可在导入预览中取消。');
    }
    names.add(importedName);
    genders[importedName] = genderColumn >= 0 && row.length > genderColumn
        ? row[genderColumn]?.toString().replaceAll('\uFEFF', '').trim() ?? ''
        : '';
    employeeIds[importedName] = idColumn >= 0 && row.length > idColumn
        ? row[idColumn]?.toString().replaceAll('\uFEFF', '').trim() ?? ''
        : '';
  }
  if (names.isEmpty && issues.isEmpty) {
    throw FormatException('$source没有人员数据，请从第二行开始填写姓名。');
  }
  return ImportPreview(
    names,
    issues,
    gender: genders,
    employeeIds: employeeIds,
  );
}

/// Tries every worksheet and returns the first one that contains a roster.
/// Bill records, attendance logs and other unrelated workbooks are rejected
/// with a message instead of being imported by column position.
ImportPreview parsePeopleWorkbook(Uint8List bytes, Iterable<String> existing) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) throw const FormatException('工作簿没有表格');
  final errors = <String>[];
  for (final entry in book.tables.entries) {
    final rows = entry.value.rows
        .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
        .toList();
    try {
      return parsePeople(rows, existing, source: '工作表「${entry.key}」');
    } on FormatException catch (e) {
      errors.add(e.message.toString());
    }
  }
  throw FormatException(
    errors.isEmpty ? '工作簿没有可导入的人员' : '未找到可导入的人员名单。${errors.first}',
  );
}

Future<ImportPreview?> pickPeople(Workspace store) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'csv'],
    dialogTitle: '选择人员名单',
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final existing = store.visiblePeople.map((p) => p.name);
  if (file.name.toLowerCase().endsWith('.csv')) {
    final text = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(text);
    return parsePeople(rows, existing, source: '文件「${file.name}」');
  }
  return parsePeopleWorkbook(bytes, existing);
}

List<int> peopleTemplateBytes() {
  final book = Excel.createExcel();
  final defaultSheet = book.getDefaultSheet()!;
  book.rename(defaultSheet, '人员名单');
  final sheet = book['人员名单'];
  sheet.appendRow([
    TextCellValue('姓名'),
    TextCellValue('性别'),
    TextCellValue('工号'),
  ]);
  sheet.setColumnWidth(0, 18);
  sheet.setColumnWidth(1, 12);
  sheet.setColumnWidth(2, 20);
  final guide = book['填写说明'];
  for (final line in [
    '青鸾考勤 · 人员导入模板',
    '',
    '1. 在「人员名单」工作表中填写人员。',
    '2. 第一行表头请勿修改：姓名（必填）、性别（可选）、工号（可选）。',
    '3. 从第二行开始填写，每行一人；示例：张三 / 男 / EMP-1001。',
    '4. 同名人员导入时可选择保存为副本或跳过。',
    '5. 保存为 .xlsx 后，在 App 中进入「设置 → 人员名单 → 导入」选择此文件。',
  ]) {
    guide.appendRow([TextCellValue(line)]);
  }
  guide.setColumnWidth(0, 72);
  return book.encode()!;
}

Future<String?> savePeopleTemplate(Rect origin) async {
  final bytes = peopleTemplateBytes();
  const name = '青鸾考勤_人员导入模板.xlsx';
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], sharePositionOrigin: origin),
    );
    return name;
  }
  final target = await FilePicker.saveFile(
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    bytes: Uint8List.fromList(bytes),
  );
  return target?.toString();
}

const exportColumns = [
  '人员',
  '工作日',
  '签到时间',
  '签退时间',
  '状态',
  '备注',
  '最后修改人',
  '更新时间',
];
List<int> workbookBytes(
  Workspace store,
  List<Entry> entries,
  List<String> columns,
) {
  final book = Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  sheet.appendRow(columns.map((s) => TextCellValue(s)).toList());
  for (final e in entries) {
    final values = [
      store.name(e.personId),
      e.day,
      e.fields['in'] ?? '',
      e.fields['out'] ?? '',
      e.fields['status'] ?? '',
      e.fields['note'] ?? '',
      e.author,
      e.updatedAt,
    ];
    sheet.appendRow(
      columns
          .map((s) => TextCellValue(values[exportColumns.indexOf(s)]))
          .toList(),
    );
  }
  final metadata = book['导出信息'];
  for (final row in [
    ['应用', '青鸾考勤 1.0.3'],
    [
      '生成时间（东八区）',
      DateTime.now()
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .split('.')
          .first,
    ],
    ['记录数', '${entries.length}'],
    ['时间说明', '工作日与签到签退采用东八区；更新时间采用 UTC。'],
  ]) {
    metadata.appendRow(row.map((s) => TextCellValue(s)).toList());
  }
  return book.encode()!;
}

Future<String?> saveWorkbook(
  Workspace store,
  List<Entry> entries,
  List<String> columns,
  Rect origin,
) async {
  final days = entries.map((e) => e.day).toList()..sort();
  final stamp = DateTime.now()
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .replaceAll(':', '')
      .split('.')
      .first;
  final name = '青鸾考勤_${days.first}_${days.last}_$stamp.xlsx';
  // Include export provenance separately from the record table.
  final bytes = workbookBytes(store, entries, columns);
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], sharePositionOrigin: origin),
    );
    return name;
  }
  final target = await FilePicker.saveFile(
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    bytes: Uint8List.fromList(bytes),
  );
  return target?.toString();
}

Future<String?> saveCsv(
  Workspace store,
  List<Entry> entries,
  Rect origin,
) async {
  final rows = <List<dynamic>>[exportColumns];
  for (final e in entries) {
    rows.add([
      store.name(e.personId),
      e.day,
      e.fields['in'] ?? '',
      e.fields['out'] ?? '',
      e.fields['status'] ?? '',
      e.fields['note'] ?? '',
      e.author,
      e.updatedAt,
    ]);
  }
  final bytes = Uint8List.fromList(
    utf8.encode(const ListToCsvConverter().convert(rows)),
  );
  final name = '青鸾考勤_${businessDay()}.csv';
  if (Platform.isAndroid || Platform.isIOS) {
    final path = '${(await getTemporaryDirectory()).path}/$name';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], sharePositionOrigin: origin),
    );
    return name;
  }
  return (await FilePicker.saveFile(
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['csv'],
    bytes: bytes,
  ))?.toString();
}

Future<String?> saveDatabase(Workspace store, Rect origin) async {
  if (store.dataPath == '内存（测试）' || !File(store.dataPath).existsSync()) {
    throw const FormatException('当前工作区尚未保存为 SQLite 文件');
  }
  final name = 'qingluan_${businessDay()}.db';
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(store.dataPath)], sharePositionOrigin: origin),
    );
    return name;
  }
  final target = await FilePicker.saveFile(
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['db'],
    bytes: await File(store.dataPath).readAsBytes(),
  );
  if (target == null) return null;
  return target.toString();
}
