import 'dart:async';
import 'dart:collection';

import '../types/errors.dart';
import 'logger.dart';

typedef _Runner = Future<void> Function();

/// A FIFO, single-in-flight command queue.
///
/// Every public SDK method routes through this so calls execute in strict
/// submission order — `setUserId` followed by `setAttribute` can't race, because
/// the attribute call needs the userId already applied. Ported from the RN
/// `CommandQueue`, with one difference: each [add] returns its own `Future<T>`
/// instead of a shared `wait()`.
class CommandQueue {
  /// Creates a queue. [isSetup] reports whether `setup()` has completed; it is
  /// injected so the queue stays decoupled from the setup module (and testable).
  CommandQueue({required this.isSetup});

  /// Reports whether the SDK is set up. Injected for decoupling/testability.
  final bool Function() isSetup;
  final Queue<_Runner> _queue = Queue<_Runner>();
  bool _running = false;

  /// Enqueues [command] and returns a future that completes after it runs.
  ///
  /// - When [checkSetup] is true and the SDK isn't set up, the returned future
  ///   completes with [NotSetupError] and [command] never runs.
  /// - Any error thrown by [command] is caught, logged, and surfaced on *that*
  ///   command's future only — it never breaks the worker loop.
  Future<T> add<T>(FutureOr<T> Function() command, {bool checkSetup = true}) {
    // The completer is created and completed inside this generic method, so the
    // queue can hold type-erased `_Runner` closures while `add<T>` stays
    // type-safe.
    final completer = Completer<T>();

    _queue.add(() async {
      try {
        if (checkSetup && !isSetup()) {
          throw NotSetupError();
        }
        final result = await command();
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stackTrace) {
        Logger.error('Global error: $error');
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }
    });

    unawaited(_drain());
    return completer.future;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final runner = _queue.removeFirst();
        // `runner` swallows its own errors, so this await never throws and the
        // loop is never broken by a failing command.
        await runner();
      }
    } finally {
      _running = false;
    }
  }
}
