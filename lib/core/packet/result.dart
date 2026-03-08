sealed class ParseResult<T> {
  const ParseResult();
}

final class Ok<T> extends ParseResult<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends ParseResult<T> {
  final String message;
  const Err(this.message);
}
