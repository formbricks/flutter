/// A Rust-style result type: either an [Ok] value or an [Err] error.
///
/// Ported from the React Native SDK's `Result<T, E>` (`types/error.ts`). Using a
/// `sealed` class lets callers `switch` exhaustively without a `default` arm:
///
/// ```dart
/// switch (result) {
///   case Ok(:final value):
///     useValue(value);
///   case Err(:final error):
///     handle(error);
/// }
/// ```
///
/// [Ok] and [Err] must stay in this library for the exhaustiveness guarantee to
/// hold.
sealed class Result<T, E> {
  const Result();

  /// Wraps a success [value].
  const factory Result.ok(T value) = Ok<T, E>;

  /// Wraps an error [error].
  const factory Result.err(E error) = Err<T, E>;

  /// Whether this result is an [Ok].
  bool get isOk => this is Ok<T, E>;

  /// Whether this result is an [Err].
  bool get isErr => this is Err<T, E>;
}

/// The success variant of [Result], holding a [value].
final class Ok<T, E> extends Result<T, E> {
  /// Creates a success result wrapping [value].
  const Ok(this.value);

  /// The wrapped success value.
  final T value;
}

/// The error variant of [Result], holding an [error].
final class Err<T, E> extends Result<T, E> {
  /// Creates an error result wrapping [error].
  const Err(this.error);

  /// The wrapped error.
  final E error;
}
