abstract final class UpdateDefaults {
  static const gitee = 'https://gitee.com/Murchey/qingluan-attendance';
  static const github = 'https://github.com/Murchey/Qingluan-attendance';
  static const proxies = [
    'https://gh.acmsz.top/',
    'https://gg.z321.cc.cd/',
    'https://gh.my-website.ccwu.cc/',
  ];
  static const architectures = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  static const settings = <String, dynamic>{
    'update_Gitee': gitee,
    'update_GitHub': github,
    'updateProxy0': 'https://gh.acmsz.top/',
    'updateProxy1': 'https://gg.z321.cc.cd/',
    'updateProxy2': 'https://gh.my-website.ccwu.cc/',
    'updateProxyIndex': 0,
    'updateUseProxy': true,
  };

  static void apply(Map<String, dynamic> settings) {
    for (final entry in UpdateDefaults.settings.entries) {
      final old = settings[entry.key];
      if (old == null || old is String && old.trim().isEmpty) {
        settings[entry.key] = entry.value;
      }
    }
  }

  static String repository(Map<String, dynamic> settings, String source) =>
      (settings['update_$source'] ??
              (source == 'Gitee'
                  ? gitee
                  : source == 'GitHub'
                  ? github
                  : ''))
          .toString()
          .trim();

  static int proxyIndex(Map<String, dynamic> settings) =>
      (int.tryParse('${settings['updateProxyIndex']}') ?? 0).clamp(0, 2);

  static String proxy(Map<String, dynamic> settings, [int? index]) {
    final i = index ?? proxyIndex(settings);
    return normalizeProxy((settings['updateProxy$i'] ?? proxies[i]).toString());
  }

  static String normalizeProxy(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.contains('https:') ||
        uri.path.contains('http:')) {
      throw const FormatException(
        '请输入代理的 HTTPS 前缀，例如 https://gh.acmsz.top/，不要粘贴完整下载链接。',
      );
    }
    return uri.toString().endsWith('/') ? uri.toString() : '${uri.toString()}/';
  }

  static Uri downloadUri(
    Uri original, {
    required String source,
    required bool useProxy,
    required Map<String, dynamic> settings,
  }) {
    if (source != 'GitHub' || !useProxy) return original;
    return Uri.parse('${proxy(settings)}$original');
  }

  static String apkName(String version, String architecture) =>
      'Qingluan-attendanceV${version.replaceFirst(RegExp(r"^[vV]"), "")}-$architecture.apk';
}
