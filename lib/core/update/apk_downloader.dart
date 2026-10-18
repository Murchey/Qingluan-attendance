import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'release_update_checker.dart';

class UpdateCancelled implements Exception {}

class ApkDownloader {
  HttpClient? _client;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<File> download(
    ReleaseAsset asset,
    Uri uri, {
    required void Function(int received, int total) onProgress,
    Directory? directory,
  }) async {
    _cancelled = false;
    final root =
        directory ??
        Directory('${(await getTemporaryDirectory()).path}/updates');
    await root.create(recursive: true);
    // The name comes from release metadata; never use it as an arbitrary path.
    if (!RegExp(
      r'^Qingluan-attendanceV\d+\.\d+\.\d+-(arm64-v8a|armeabi-v7a|x86_64)\.apk$',
    ).hasMatch(asset.name)) {
      throw const FormatException('安装包名称不符合约定');
    }
    final part = File('${root.path}/${asset.name}.part');
    final target = File('${root.path}/${asset.name}');
    IOSink? sink;
    final client = _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.userAgentHeader, 'Qingluan-Attendance');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (_cancelled) throw UpdateCancelled();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}，请更换下载源或代理');
      }
      final total = asset.size > 0 ? asset.size : response.contentLength;
      if (total > 512 * 1024 * 1024) {
        throw const FormatException('安装包超过 512 MB');
      }
      var received = 0;
      final repaint = Stopwatch()..start();
      sink = part.openWrite();
      onProgress(0, total);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (_cancelled) throw UpdateCancelled();
        received += chunk.length;
        if (received > 512 * 1024 * 1024) {
          throw const FormatException('安装包超过 512 MB');
        }
        sink.add(chunk);
        if (repaint.elapsedMilliseconds >= 100 || received == total) {
          onProgress(received, total);
          repaint.reset();
        }
      }
      await sink.flush();
      onProgress(received, total);
      await sink.close();
      sink = null;
      if (_cancelled) throw UpdateCancelled();
      if (total > 0 && received != total) {
        throw const FormatException('下载不完整，请重试');
      }
      final header = await part.open();
      final magic = await header.read(4);
      await header.close();
      if (magic.length != 4 ||
          magic[0] != 0x50 ||
          magic[1] != 0x4b ||
          magic[2] != 3 ||
          magic[3] != 4) {
        throw const FormatException('下载内容不是 APK，可能是代理返回的网页，请更换下载源');
      }
      if (asset.sha256 != null) {
        final digest = await sha256.bind(part.openRead()).first;
        if (digest.toString() != asset.sha256) {
          throw const FormatException('安装包 SHA-256 校验失败，请更换下载源');
        }
      }
      if (_cancelled) throw UpdateCancelled();
      if (await target.exists()) await target.delete();
      return await part.rename(target.path);
    } catch (e) {
      if (_cancelled) throw UpdateCancelled();
      rethrow;
    } finally {
      if (sink != null) await sink.close();
      if (await part.exists()) await part.delete();
      client.close(force: true);
      _client = null;
    }
  }
}
