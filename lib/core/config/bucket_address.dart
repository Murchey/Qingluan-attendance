/// A provider-native bucket root URL, without object paths or signed queries.
class BucketAddress {
  const BucketAddress(this.url, this.endpoint, this.bucket);
  final Uri url;
  final Uri endpoint;
  final String bucket;

  static String settingKey(String provider) =>
      '${provider.toLowerCase()}BucketUrl';

  factory BucketAddress.parse(String provider, String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('请填写 HTTPS 存储桶根地址，不要包含文件路径、签名参数或端口。');
    }
    final pattern = switch (provider) {
      'OSS' => RegExp(
        r'^([a-z0-9][a-z0-9-]{1,61}[a-z0-9])\.(oss-[a-z0-9-]+\.aliyuncs\.com)$',
      ),
      'COS' => RegExp(
        r'^([a-z0-9][a-z0-9-]*-[0-9]+)\.(cos\.[a-z0-9-]+\.myqcloud\.com)$',
      ),
      _ => throw const FormatException('S3 请分别填写 Endpoint 和 Bucket。'),
    };
    final match = pattern.firstMatch(uri.host);
    if (match == null) {
      throw FormatException(
        provider == 'OSS'
            ? '请使用阿里云桶域名，例如 https://my-bucket.oss-cn-hangzhou.aliyuncs.com'
            : '请使用腾讯云桶域名，例如 https://my-bucket-1250000000.cos.ap-guangzhou.myqcloud.com',
      );
    }
    return BucketAddress(Uri.https(uri.host), Uri.https(match[2]!), match[1]!);
  }

  /// Read earlier Endpoint + Bucket settings without discarding S3 settings.
  static String configuredUrl(Map<String, dynamic> settings, String provider) {
    final saved = settings[settingKey(provider)] as String?;
    if (saved != null) return saved;
    final endpoint = settings['endpoint'] as String? ?? '';
    try {
      return BucketAddress.parse(provider, endpoint).url.toString();
    } on FormatException {
      /* Earlier configs may use the regional endpoint. */
    }
    final uri = Uri.tryParse(endpoint);
    final bucket = settings['bucket'] as String? ?? '';
    if (uri == null ||
        uri.scheme != 'https' ||
        bucket.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return '';
    }
    try {
      return BucketAddress.parse(
        provider,
        'https://$bucket.${uri.host}',
      ).url.toString();
    } on FormatException {
      return '';
    }
  }
}
