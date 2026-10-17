sealed class AppResult<T> {
  const AppResult();
}

final class Success<T> extends AppResult<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends AppResult<T> {
  const Failure(this.message, {this.cause});
  final String message;
  final Object? cause;
}
