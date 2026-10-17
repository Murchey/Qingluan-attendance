import '../result/app_result.dart';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.downloadUrl,
    this.sha256,
  });
  final String version;
  final Uri downloadUrl;
  final String? sha256;
}

abstract interface class UpdateChecker {
  Future<AppResult<ReleaseInfo?>> check();
}
