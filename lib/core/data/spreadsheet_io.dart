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
  ImportPreview(this.names, this.issues, {this.gender = const {}, this.employeeIds = const {}});
  final List<String> names;
  final List<String> issues;
  final Map<String, String> gender;
  final Map<String, String> employeeIds;
}

ImportPreview parsePeople(List<List<dynamic>> rows, Iterable<String> existing) {
  if (rows.isEmpty) throw const FormatException('文件没有内容');
  final header = rows.first
      .map((c) => c?.toString().replaceAll('\uFEFF', '').trim() ?? '')
      .toList();
  final hasHeader = header.any((s) => ['姓名', '人员', 'name'].contains(s.toLowerCase()));
  final column = header.indexWhere(
    (s) => ['姓名', '人员', 'name'].contains(s.toLowerCase()),
  );
  final start = hasHeader ? 1 : 0;
  if (!hasHeader && rows.length == 1) {
    throw const FormatException('文件没有可导入的人员行');
  }
  final nameColumn = hasHeader && column >= 0 ? column : 0;
  final genderColumn = hasHeader ? header.indexWhere((s) => ['性别', 'gender'].contains(s.toLowerCase())) : 1;
  final idColumn = hasHeader ? header.indexWhere((s) => ['工号', '员工号', 'employeeid'].contains(s.toLowerCase())) : 2;
  final seen = existing.toSet();
  final names = <String>[];
  final issues = <String>[];
  final genders = <String, String>{};
  final employeeIds = <String, String>{};
  for (var i = start; i < rows.length; i++) {
    final name = rows[i].length > nameColumn
        ? rows[i][nameColumn]?.toString().trim() ?? ''
        : '';
    if (name.isEmpty) {
      issues.add('第 ${i + 1} 行缺少姓名');
      continue;
    }
    if (!seen.add(name)) {
      issues.add('第 ${i + 1} 行“$name”重名，跳过');
      continue;
    }
    names.add(name);
    genders[name] = genderColumn >= 0 && rows[i].length > genderColumn ? rows[i][genderColumn].toString().trim() : '';
    employeeIds[name] = idColumn >= 0 && rows[i].length > idColumn ? rows[i][idColumn].toString().trim() : '';
  }
  return ImportPreview(names, issues, gender: genders, employeeIds: employeeIds);
}

Future<ImportPreview?> pickPeople(Workspace store) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'csv'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final List<List<dynamic>> rows;
  if (file.name.toLowerCase().endsWith('.csv')) {
    final text = utf8
        .decode(bytes)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(text);
  } else {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) throw const FormatException('工作簿没有表格');
    rows = book.tables.values.first.rows
        .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
        .toList();
  }
  return parsePeople(rows, store.visiblePeople.map((p) => p.name));
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
    ['应用', '青鸾考勤 1.0.0'],
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
