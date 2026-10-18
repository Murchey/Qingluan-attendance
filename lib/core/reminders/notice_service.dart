import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/object_layout.dart';
import '../data/workspace.dart';

/// One notification channel entry inside `index.json`.
class NoticeRef {
  const NoticeRef({
    required this.channel,
    required this.version,
    required this.path,
    this.title = '',
    this.updatedAt = '',
  });

  /// `admin` or `dev`.
  final String channel;

  /// Monotonic token (commit-hash style). Compared against the locally read
  /// version to decide whether the body must be fetched again.
  final String version;
  final String path;
  final String title;
  final String updatedAt;

  String get label => channel == 'dev' ? '开发者通知' : '管理员通知';
}

class NoticeIndex {
  const NoticeIndex({
    this.schema = 1,
    this.dataHash = '',
    this.dataUpdatedAt = '',
    this.admin,
    this.dev,
  });
  final int schema;
  final String dataHash;
  final String dataUpdatedAt;
  final NoticeRef? admin;
  final NoticeRef? dev;

  /// Tolerant parser: accepts `adminNote` / `admin` / `note` spellings and
  /// falls back to `hash` / `updatedAt` when no explicit version is present.
  static NoticeIndex? parse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    NoticeRef? ref(String channel, List<String> keys, String defaultPath) {
      for (final key in keys) {
        final value = json[key];
        if (value is! Map) continue;
        final map = Map<String, dynamic>.from(value);
        final token = [
          map['version'],
          map['hash'],
          map['updatedAt'],
        ].map((v) => v?.toString() ?? '').firstWhere(
          (v) => v.trim().isNotEmpty,
          orElse: () => '',
        );
        if (token.isEmpty) return null;
        return NoticeRef(
          channel: channel,
          version: token,
          path: (map['path']?.toString().trim().isNotEmpty ?? false)
              ? map['path'].toString().trim()
              : defaultPath,
          title: map['title']?.toString() ?? '',
          updatedAt: map['updatedAt']?.toString() ?? '',
        );
      }
      return null;
    }

    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : const <String, dynamic>{};
    return NoticeIndex(
      schema: int.tryParse('${json['schema'] ?? 1}') ?? 1,
      dataHash: (data['hash'] ?? json['dataHash'] ?? '').toString(),
      dataUpdatedAt: (data['updatedAt'] ?? '').toString(),
      admin: ref('admin', ['adminNote', 'admin', 'note'], ObjectLayout.adminNote),
      dev: ref('dev', ['devNote', 'dev', 'developerNote'], ObjectLayout.devNote),
    );
  }
}

/// Reads the manifest and notice bodies. Injectable so tests never touch the
/// network.
abstract interface class NoticeSource {
  Future<NoticeIndex?> index();
  Future<String?> text(String key);
}

class HttpNoticeSource implements NoticeSource {
  HttpNoticeSource(this.base, {this.timeout = const Duration(seconds: 12)});
  final Uri base;
  final Duration timeout;

  Future<String?> _get(String key) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = ObjectLayout.resolve(base, key);
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(timeout);
      final bytes = await consolidateHttpClientResponseBytes(
        response,
      ).timeout(timeout);
      if (response.statusCode != 200) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<NoticeIndex?> index() async {
    final text = await _get(ObjectLayout.index);
    if (text == null) return null;
    try {
      return NoticeIndex.parse(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<String?> text(String key) => _get(key);
}

class NoticeSyncResult {
  const NoticeSyncResult({
    this.ok = false,
    this.message = '',
    this.admin,
    this.dev,
    this.adminBody = '',
    this.devBody = '',
    this.dataHash = '',
    this.configured = true,
  });
  final bool ok;
  final String message;

  /// Non-null when the body differs from what this device has already read.
  final NoticeRef? admin;
  final NoticeRef? dev;
  final String adminBody;
  final String devBody;
  final String dataHash;
  final bool configured;

  bool get hasNews => admin != null || dev != null;
}

/// Fetch `index.json`, then only the notice bodies whose version changed.
/// Returns at most one fetch per channel, keeping request counts low.
Future<NoticeSyncResult> syncNotices(
  Workspace store, {
  NoticeSource? source,
}) async {
  final base = ObjectLayout.baseUrl(store.settings);
  if (base == null) {
    await store.setNoticeState(lastResult: '未配置对象存储，通知检查已跳过');
    return const NoticeSyncResult(
      message: '尚未配置对象存储，通知检查已跳过',
      configured: false,
    );
  }
  final client = source ?? HttpNoticeSource(Uri.parse(base));
  NoticeIndex? manifest;
  try {
    manifest = await client.index();
  } on Object {
    manifest = null;
  }
  if (manifest == null) {
    await store.setNoticeState(lastResult: '无法读取 index.json');
    return const NoticeSyncResult(
      message: '无法读取 index.json：可能尚未上传，或存储桶未开启公开只读',
    );
  }

  var admin = manifest.admin;
  var dev = manifest.dev;
  if (admin != null && admin.version == store.noticeVersion('admin')) {
    admin = null;
  }
  if (dev != null && dev.version == store.noticeVersion('dev')) dev = null;

  var adminBody = '';
  var devBody = '';
  if (admin != null) {
    adminBody = (await client.text(admin.path))?.trim() ?? '';
    if (adminBody.isEmpty) admin = null;
  }
  if (dev != null) {
    devBody = (await client.text(dev.path))?.trim() ?? '';
    if (devBody.isEmpty) dev = null;
  }

  final dataChanged =
      manifest.dataHash.isNotEmpty &&
      manifest.dataHash != (store.notices['dataHash']?.toString() ?? '');
  final parts = <String>[
    if (admin != null) '管理员通知有更新',
    if (dev != null) '开发者通知有更新',
    if (dataChanged && admin == null && dev == null) '云端数据版本有更新',
    if (admin == null && dev == null && !dataChanged) '通知已是最新',
  ];
  final message = parts.join('，');
  await store.setNoticeState(lastResult: message, dataHash: manifest.dataHash);
  return NoticeSyncResult(
    ok: true,
    message: message,
    admin: admin,
    dev: dev,
    adminBody: adminBody,
    devBody: devBody,
    dataHash: manifest.dataHash,
  );
}
