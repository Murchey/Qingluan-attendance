/// 东八区业务日期的统一入口，实际网络时间服务在 data 层实现。
abstract interface class BusinessClock {
  Future<DateTime> now();
}

class LocalFallbackClock implements BusinessClock {
  @override
  Future<DateTime> now() async =>
      DateTime.now().toUtc().add(const Duration(hours: 8));
}
