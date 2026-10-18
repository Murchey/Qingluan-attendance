import 'bucket_address.dart';

/// Object-storage layout shared by every client and by the future self-hosted
/// backend. Everything lives in one bucket; `index.json` is the only file that
/// must be fetched on start-up.
///
/// ```
/// /index.json            manifest: data hash + notification versions
/// /note.md               admin notice body (rendered in the bottom panel)
/// /dev-note.md           developer notice body (same mechanism)
/// /data/people.json      personnel list (stable ids, tombstones)
/// /data/records/2026-10-17.json   one file per business day
/// /data/leaves/2026-10.json       leave records per month
/// /data/archive/…        optional cold storage for closed months
/// ```
abstract final class ObjectLayout {
  static const index = 'index.json';
  static const adminNote = 'note.md';
  static const devNote = 'dev-note.md';
  static const people = 'data/people.json';
  static const recordsRoot = 'data/records';
  static const leavesRoot = 'data/leaves';
  static const archiveRoot = 'data/archive';

  static String record(String day) => '$recordsRoot/$day.json';
  static String leaveMonth(String month) => '$leavesRoot/$month.json';
  static String archive(String key) => '$archiveRoot/$key';

  /// Resolve an object key against a bucket root such as
  /// `https://bucket.oss-cn-hangzhou.aliyuncs.com`.
  static Uri resolve(Uri base, String key) {
    final root = Uri.parse(
      '${base.toString().replaceAll(RegExp(r'/+$'), '')}/',
    );
    return root.resolve(key);
  }

  /// Bucket root derived from settings, or null when nothing is configured.
  static String? baseUrl(Map<String, dynamic> settings) {
    final provider = settings['provider']?.toString() ?? 'COS';
    if (provider == 'OSS' || provider == 'COS') {
      final url = BucketAddress.configuredUrl(settings, provider);
      return url.isEmpty ? null : url;
    }
    final endpoint = settings['endpoint']?.toString() ?? '';
    final bucket = settings['bucket']?.toString() ?? '';
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        bucket.isEmpty) {
      return null;
    }
    return 'https://${uri.host}/$bucket';
  }
}
