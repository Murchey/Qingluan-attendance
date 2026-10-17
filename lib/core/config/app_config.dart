enum StorageProvider { oss, cos, s3 }

enum UpdateSource { gitee, github, selfHosted }

class ObjectStorageProfile {
  const ObjectStorageProfile({
    required this.provider,
    required this.endpoint,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
  });

  final StorageProvider provider;
  final Uri endpoint;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
}

class LocalIdentity {
  const LocalIdentity({required this.deviceId, required this.displayName});

  final String deviceId;
  final String displayName;
}
