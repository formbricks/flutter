import 'dart:developer' as developer;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// Log verbosity. `error` (default) logs only errors; `debug` logs everything.
enum LogLevel {
  /// Verbose: logs debug and error messages.
  debug,

  /// Quiet: logs only error messages.
  error,
}

/// Static logging facade over a hidden singleton.
///
/// Mirrors the RN SDK's `Logger` (same `🧱 Formbricks - <ts> [LEVEL] - msg`
/// format) but is configured once in `setup()` for deterministic behavior.
/// Routes through `dart:developer`'s `log()` rather than `print()` (the
/// `avoid_print` lint is on) and never logs attribute values or other PII.
class Logger {
  Logger._();

  static final Logger _instance = Logger._();

  LogLevel _level = LogLevel.error;

  /// Sets the log [level]. Called from `setup()`.
  static void configure({LogLevel? level}) {
    if (level != null) _instance._level = level;
  }

  /// The current log level. Exposed for tests (e.g. to assert `setup()`
  /// configured it from the build mode).
  @visibleForTesting
  static LogLevel get level => _instance._level;

  /// Logs a debug message (suppressed unless level is [LogLevel.debug]).
  static void debug(String message) => _instance._log(message, LogLevel.debug);

  /// Logs an error message (always emitted).
  static void error(String message) => _instance._log(message, LogLevel.error);

  void _log(String message, LogLevel level) {
    if (level == LogLevel.debug && _level != LogLevel.debug) return;
    final timestamp = clock.now().toIso8601String();
    developer.log(
      '🧱 Formbricks - $timestamp [${level.name.toUpperCase()}] - $message',
      name: 'Formbricks',
      level: level == LogLevel.error ? 1000 : 500,
    );
  }

  /// Resets the singleton level to the default. Test-only.
  @visibleForTesting
  static void resetInstance() => _instance._level = LogLevel.error;
}
