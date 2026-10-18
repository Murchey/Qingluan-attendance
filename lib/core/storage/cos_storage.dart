import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../config/bucket_address.dart';
import '../result/app_result.dart';
import 'object_storage.dart';

/// Tencent COS XML/REST compatible object client using q-signature v5.
class CosObjectStorage implements ObjectStorage {
  CosObjectStorage({
    required this.bucketUrl,
    required String secretId,
    required String secretKey,
    this.securityToken = '',
    this.timeout = const Duration(seconds: 20),
  }) : secretId = secretId.trim(),
       secretKey = secretKey.trim();

  final Uri bucketUrl;
  final String secretId;
  final String secretKey;
  final String securityToken;
  final Duration timeout;

  Uri _uri(String key) => Uri.parse(
    '${bucketUrl.toString().replaceAll(RegExp(r'/+$'), '')}/${key.split('/').map(Uri.encodeComponent).join('/')}',
  );

  String _sha1(String value) => sha1.convert(utf8.encode(value)).toString();
  String _hmac(String key, String value) =>
      Hmac(sha1, utf8.encode(key)).convert(utf8.encode(value)).toString();

  String _encode(String value) =>
      Uri.encodeQueryComponent(value).replaceAll('+', '%20');

  String _responseError(List<int> bytes, int statusCode) {
    final body = utf8.decode(bytes, allowMalformed: true);
    final code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(body)?.group(1);
    final detail = RegExp(
      r'<Message>([^<]+)</Message>',
    ).firstMatch(body)?.group(1);
    if (code != null || detail != null) {
      return 'COS HTTP $statusCode${code == null ? '' : ' [$code]'}${detail == null ? '' : ': $detail'}';
    }
    return 'COS HTTP $statusCode';
  }

  String _authorization(String method, Uri uri, String bodyHash, DateTime now) {
    final start = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final end = start + timeout.inSeconds.clamp(60, 600);
    final signTime = '$start;$end';
    final keyTime = signTime;
    final signKey = _hmac(secretKey, keyTime);
    final headerList = securityToken.isEmpty
        ? 'host'
        : 'host;x-cos-security-token';
    final headers = securityToken.isEmpty
        ? 'host=${_encode(uri.host)}'
        : 'host=${_encode(uri.host)}&x-cos-security-token=${_encode(securityToken)}';
    final httpString = [
      method.toLowerCase(),
      uri.path,
      '',
      headers,
      '',
    ].join('\n');
    final stringToSign = 'sha1\n$keyTime\n${_sha1(httpString)}\n';
    final signature = _hmac(signKey, stringToSign);
    return 'q-sign-algorithm=sha1&q-ak=$secretId&q-sign-time=$signTime&'
        'q-key-time=$keyTime&q-header-list=$headerList&q-url-param-list=&'
        'q-signature=$signature';
  }

  Future<AppResult<RemoteObject?>> _request(
    String method,
    String key, [
    List<int>? body,
  ]) async {
    if (secretId.trim().isEmpty || secretKey.trim().isEmpty) {
      return const Failure('未配置 COS 密钥');
    }
    final uri = _uri(key);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      final bytes = body ?? const <int>[];
      request.headers.set(HttpHeaders.hostHeader, uri.host);
      if (securityToken.isNotEmpty) {
        request.headers.set('x-cos-security-token', securityToken);
      }
      request.headers.set(
        'Authorization',
        _authorization(method, uri, _sha1(utf8.decode(bytes)), DateTime.now()),
      );
      if (method == 'PUT') {
        request.headers.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      final responseBytes = await response.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Failure(_responseError(responseBytes, response.statusCode));
      }
      if (method == 'GET') {
        return Success(
          RemoteObject(
            key: key,
            sha256: sha256.convert(responseBytes).toString(),
            bytes: responseBytes,
          ),
        );
      }
      return const Success(null);
    } on Object catch (e) {
      return Failure('COS 请求失败', cause: e);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<AppResult<RemoteObject?>> get(String key) => _request('GET', key);

  @override
  Future<AppResult<void>> put(
    String key,
    List<int> bytes, {
    required String sha256,
  }) async {
    final result = await _request('PUT', key, bytes);
    return switch (result) {
      Success() => const Success(null),
      Failure(:final message, :final cause) => Failure(message, cause: cause),
    };
  }

  Future<AppResult<int>> probe() async {
    // A new bucket commonly has no index.json yet. A signed 404 proves the
    // endpoint was reached, so only auth/network failures are errors.
    final result = await _request('GET', 'index.json');
    return switch (result) {
      Success() => const Success(200),
      Failure(:final message) when message.contains('HTTP 404') =>
        const Success(404),
      Failure(:final message, :final cause) => Failure(message, cause: cause),
    };
  }

  static CosObjectStorage? fromSettings(
    Map<String, dynamic> settings,
    String id,
    String key, {
    String token = '',
  }) {
    final provider = settings['provider']?.toString() ?? 'COS';
    if (provider != 'COS') return null;
    final value = BucketAddress.configuredUrl(settings, provider);
    final uri = Uri.tryParse(value);
    if (uri == null || value.isEmpty) return null;
    return CosObjectStorage(
      bucketUrl: uri,
      secretId: id,
      secretKey: key,
      securityToken: token,
    );
  }
}
