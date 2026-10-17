import '../result/app_result.dart';

/// 本地持久化抽象；具体 SQLite 驱动在 data 层实现。
abstract interface class LocalStore {
  Future<void> open();
  Future<AppResult<T>> read<T>(
    String query, [
    List<Object?> parameters = const [],
  ]);
  Future<AppResult<void>> write(
    String command, [
    List<Object?> parameters = const [],
  ]);
  Future<void> close();
}
