/// Stable error codes used across the SDK. The [wire] value matches the string
/// the backend uses, so logs and tests stay comparable.
enum FormbricksErrorCode {
  /// A required input field was missing or empty.
  missingField('missing_field'),

  /// A network/transport failure or non-2xx server response.
  networkError('network_error'),

  /// The SDK was used before [setup] completed.
  notSetup('not_setup'),

  /// The backend rejected the request (auth / 404 environment).
  forbidden('forbidden'),

  /// `setup()` was called while the SDK is in its post-failure cooldown window.
  setupCooldown('setup_cooldown'),

  /// An invalid code was supplied (reserved for code actions).
  invalidCode('invalid_code'),

  /// An internal SDK failure that is not a network/backend error.
  internalError('internal_error');

  const FormbricksErrorCode(this.wire);

  /// The on-the-wire string representation of this code.
  final String wire;
}

/// Base type for all SDK errors. Sealed so callers can switch exhaustively.
sealed class FormbricksError implements Exception {
  const FormbricksError(this.code, this.message);

  /// The stable error code.
  final FormbricksErrorCode code;

  /// A human-readable description (never contains PII).
  final String message;

  @override
  String toString() => 'FormbricksError(${code.wire}): $message';
}

/// A required field (`appUrl`, `workspaceId`, …) was missing or invalid.
final class MissingFieldError extends FormbricksError {
  /// Creates a missing-field error for [field].
  MissingFieldError(this.field, {String? message})
      : super(
          FormbricksErrorCode.missingField,
          message ?? 'No $field provided',
        );

  /// The name of the offending field.
  final String field;
}

/// The SDK was used before [setup] completed.
final class NotSetupError extends FormbricksError {
  /// Creates a not-setup error.
  NotSetupError([
    String message = 'Formbricks is not set up. Call setup() first.',
  ]) : super(FormbricksErrorCode.notSetup, message);
}

/// A network failure or non-2xx response while talking to the backend.
final class NetworkError extends FormbricksError {
  /// Creates a network error with the HTTP [status] and optional [url].
  ///
  /// A [status] of `0` represents a local/offline non-HTTP failure.
  NetworkError({
    required String message,
    required this.status,
    this.url,
    this.responseMessage,
  }) : super(FormbricksErrorCode.networkError, message);

  /// The HTTP status code, or `0` for local/offline non-HTTP failures.
  final int status;

  /// The endpoint that failed, when known.
  final Uri? url;

  /// The raw message returned by the server, when present.
  final String? responseMessage;
}

/// An invalid code action was supplied. Reserved for the track feature.
final class InvalidCodeError extends FormbricksError {
  /// Creates an invalid-code error.
  InvalidCodeError([String message = 'Invalid code'])
      : super(FormbricksErrorCode.invalidCode, message);
}

/// An internal SDK failure that is not a network/backend error.
final class InternalError extends FormbricksError {
  /// Creates an internal error for [operation], preserving the original [cause].
  InternalError({
    required this.operation,
    required this.cause,
    this.stackTrace,
    String? message,
  }) : super(
          FormbricksErrorCode.internalError,
          message ?? 'Internal error while running $operation.',
        );

  /// The SDK operation that failed.
  final String operation;

  /// The original exception or error.
  final Object cause;

  /// The original stack trace, when available.
  final StackTrace? stackTrace;
}

/// Thrown when the very first [setup] attempt fails and the SDK is placed into
/// the error-cooldown state.
final class FormbricksSetupError extends FormbricksError {
  /// Creates a setup error. Carries the underlying [code] (network/forbidden).
  FormbricksSetupError({
    String message = 'Could not set up Formbricks',
    FormbricksErrorCode code = FormbricksErrorCode.networkError,
  }) : super(code, message);
}

/// Returned by `setup()` when it is called while the SDK is still inside the
/// error cooldown that a previous failed setup opened. The SDK is **not** set up;
/// callers should retry after [retryAt].
final class SetupCooldownError extends FormbricksError {
  /// Creates a cooldown error, optionally carrying the cooldown expiry.
  SetupCooldownError({this.retryAt})
      : super(
          FormbricksErrorCode.setupCooldown,
          'Formbricks is in an error cooldown after a failed setup. '
          'Retry later.',
        );

  /// When the cooldown expires and `setup()` will attempt again, if known.
  final DateTime? retryAt;
}

/// A normalized API error returned by [ApiClient]. Distinct from
/// [FormbricksError] because the API layer preserves the raw server `code`
/// string (which may be wider than [FormbricksErrorCode]).
class ApiErrorResponse {
  /// Creates an API error response.
  const ApiErrorResponse({
    required this.code,
    required this.status,
    required this.message,
    this.url,
    this.details,
    this.responseMessage,
  });

  /// The server-supplied (or normalized) error code, e.g. `forbidden`,
  /// `network_error`.
  final String code;

  /// The HTTP status code (or 500 when unknown).
  final int status;

  /// A human-readable description.
  final String message;

  /// The endpoint that failed, when known.
  final Uri? url;

  /// Optional structured error details from the server.
  final Map<String, Object?>? details;

  /// The raw message returned by the server, when present.
  final String? responseMessage;

  @override
  String toString() =>
      'ApiErrorResponse(code: $code, status: $status, message: $message)';
}
