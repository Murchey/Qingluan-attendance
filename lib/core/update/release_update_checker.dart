import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'update_config.dart';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    this.size = 0,
    this.sha256,
  });
  final String name;
  final Uri url;
  final int size;
  final String? sha256;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.source,
    required this.assets,
    this.body = '',
    this.title = '',
  });
  final String version, source, body, title;
  final Map<String, ReleaseAsset> assets;

  static AppRelease? parse(Map<String, dynamic> json, String source) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final version = (json['tag_name'] ?? json['version'] ?? '')
        .toString()
        .replaceFirst(RegExp(r'^[vV]'), '');
    if (!RegExp(r'^\d+\.\d+\.\d+(\+\d+)?$').hasMatch(version)) return null;
    final raw = json['assets'] ?? json['attach_files'];
    final list = raw is List
        ? raw
        : raw is Map
        ? raw['links'] ?? []
        : [];
    final assets = <String, ReleaseAsset>{};
    if (list is List) {
      for (final entry in list.whereType<Map>()) {
        final name = (entry['name'] ?? '').toString();
        final url = Uri.tryParse(
          (entry['browser_download_url'] ??
                  entry['download_url'] ??
                  entry['url'] ??
                  '')
              .toString(),
        );
        if (url == null ||
            url.scheme != 'https' ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty) {
          continue;
        }
        for (final abi in UpdateDefaults.architectures) {
          if (name != UpdateDefaults.apkName(version.split('+').first, abi)) {
            continue;
          }
          final digest = (entry['digest'] ?? entry['sha256'] ?? '')
              .toString()
              .replaceFirst('sha256:', '');
          assets[abi] = ReleaseAsset(
            name: name,
            url: url,
            size: int.tryParse('${entry['size']}') ?? 0,
            sha256: RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(digest)
                ? digest.toLowerCase()
                : null,
          );
        }
      }
    }
    return AppRelease(
      version: version,
      source: source,
      assets: assets,
      body: (json['body'] ?? json['description'] ?? '').toString(),
      title: (json['name'] ?? '').toString(),
    );
  }
}

int compareVersions(String a, String b) {
  List<int> parts(String value) => value
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final left = parts(a), right = parts(b);
  for (var i = 0; i < 3; i++) {
    final result = (i < left.length ? left[i] : 0).compareTo(
      i < right.length ? right[i] : 0,
    );
    if (result != 0) return result;
  }
  return 0;
}

typedef UpdateJsonLoader = Future<Object?> Function(Uri uri);

class UpdateCatalog {
  const UpdateCatalog({required this.releases, required this.errors});
  final List<AppRelease> releases;
  final Map<String, String> errors;
  AppRelease? get latest => releases.isEmpty ? null : releases.first;
  Map<String, AppRelease> mirrors(String version) => {
    for (final release in releases)
      if (compareVersions(release.version, version) == 0)
        release.source: release,
  };
}

class ReleaseUpdateChecker {
  ReleaseUpdateChecker({UpdateJsonLoader? load}) : _load = load ?? loadJson;
  final UpdateJsonLoader _load;

  static Uri endpoint(String source, String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('更新地址必须是完整 HTTPS 地址');
    }
    if (source == '自建服务') return uri;
    final host = source == 'Gitee' ? 'gitee.com' : 'github.com';
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.host != host || parts.length < 2) {
      throw FormatException('请输入 $source 仓库主页地址');
    }
    return Uri.https(
      source == 'Gitee' ? 'gitee.com' : 'api.github.com',
      '${source == 'Gitee' ? '/api/v5/repos' : '/repos'}/${parts[0]}/${parts[1].replaceFirst(RegExp(r"\.git$"), "")}/releases',
      {'per_page': '20'},
    );
  }

  Future<UpdateCatalog> check(Map<String, dynamic> settings) async {
    // Each configured repository is queried independently. A failure in the
    // first source must not hide a release from the second, and querying both
    // keeps same-version mirrors available in the update panel. The catalog
    // records per-source errors so the caller can tell "no release" apart from
    // "every repository was unreachable".
    final errors = <String, String>{};
    final results = await Future.wait([
      for (final source in ['Gitee', 'GitHub', '自建服务'])
        if (UpdateDefaults.repository(settings, source).isNotEmpty)
          () async {
            try {
              final json = await _load(
                endpoint(source, UpdateDefaults.repository(settings, source)),
              );
              final rows = json is List
                  ? json
                  : json is Map
                  ? [json]
                  : throw const FormatException('版本信息格式无效');
              return [
                for (final row in rows.whereType<Map>())
                  ?AppRelease.parse(Map<String, dynamic>.from(row), source),
              ];
            } catch (e) {
              errors[source] = e is FormatException
                  ? e.message.toString()
                  : e is TimeoutException
                  ? '连接超时，请稍后重试'
                  : '无法连接版本服务，请检查网络或仓库地址';
              return <AppRelease>[];
            }
          }(),
    ]);
    final releases = results.expand((r) => r).toList()
      ..sort((a, b) {
        final order = compareVersions(b.version, a.version);
        return order != 0
            ? order
            : ['Gitee', 'GitHub', '自建服务']
                  .indexOf(a.source)
                  .compareTo(['Gitee', 'GitHub', '自建服务'].indexOf(b.source));
      });
    return UpdateCatalog(releases: releases, errors: errors);
  }

  static Future<Object?> loadJson(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, 'Qingluan-Attendance');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const FormatException('版本信息文件过大');
        }
      }
      return jsonDecode(utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}
