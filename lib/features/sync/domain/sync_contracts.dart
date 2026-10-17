import '../../../core/result/app_result.dart';

enum SyncStatus { idle, checking, downloading, conflict, uploading, failed }

class SyncManifest {
  const SyncManifest({required this.date, required this.sha256});
  final DateTime date;
  final String sha256;
}

abstract interface class SyncRepository {
  Future<AppResult<List<SyncManifest>>> compareWithRemote();
  Future<AppResult<void>> pull(DateTime date);
  Future<AppResult<void>> push(DateTime date);
}
