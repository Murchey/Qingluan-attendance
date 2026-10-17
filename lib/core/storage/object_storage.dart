import '../result/app_result.dart';

class RemoteObject {
  const RemoteObject({
    required this.key,
    required this.sha256,
    required this.bytes,
  });
  final String key;
  final String sha256;
  final List<int> bytes;
}

/// 对象存储抽象；后续可接 S3/OSS/COS 或自建兼容服务。
abstract interface class ObjectStorage {
  Future<AppResult<RemoteObject?>> get(String key);
  Future<AppResult<void>> put(
    String key,
    List<int> bytes, {
    required String sha256,
  });
}
