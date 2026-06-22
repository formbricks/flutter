/// Contact attributes: `setAttributes` and `setLanguage`.
///
/// The backend infers each attribute's type from the JSON value type, so values cross the wire with their natural
/// type: `String` stays a string, `num` stays a number, and `DateTime` is
/// converted to an ISO-8601 string at this one boundary (plan §7 #4).
library;

import 'dart:async';

import '../common/logger.dart';
import '../common/result.dart';
import '../types/errors.dart';
import 'update_queue.dart';

/// Sets [attributes] on the current user/contact.
///
/// `DateTime` values become UTC ISO-8601 strings; `num` and `String` values are
/// passed through unchanged. Any other value (`null`, `bool`, `List`, `Map`,
/// and anything else) is rejected synchronously with an
/// [UnsupportedAttributeValueError] before anything is queued. Otherwise queues
/// the change through the debounced [UpdateQueue] and returns `Ok` immediately
/// (the network call, and any no-userId error, surface from the queue's flush).
Future<Result<void, FormbricksError>> setAttributes(
  Map<String, Object?> attributes, {
  UpdateQueue? queue,
}) async {
  final normalized = <String, Object?>{};
  for (final entry in attributes.entries) {
    final key = entry.key;
    final value = entry.value;
    // Reject anything that isn't a `String`, `num`, or `DateTime` (`null`,
    // `bool`, `List`, `Map`, and anything else) before queueing, so the caller
    // gets a synchronous, clear error instead of silently bad data on the wire.
    // The backend infers the attribute type from the JSON value and has no
    // type for these.
    if (value is! String && value is! num && value is! DateTime) {
      final error = UnsupportedAttributeValueError(
        key,
        value.runtimeType.toString(),
      );
      Logger.error(error.message);
      return Result.err(error);
    }
    normalized[key] =
        value is DateTime ? value.toUtc().toIso8601String() : value;
  }

  final q = queue ?? UpdateQueue.instance;
  q.updateAttributes(normalized);
  // Fire-and-forget: the flush already logs and recovers from failures (e.g.
  // MissingFieldError), so swallow here to keep it off the host's unhandled-
  // error path. Tests await processUpdates() directly and still see the error.
  unawaited(q.processUpdates().catchError((_) {}));
  return const Result.ok(null);
}

/// Sets the contact's preferred [language].
///
/// Routes through [setAttributes] — this is what makes the "language without a
/// userId updates local config only" path reachable.
Future<Result<void, FormbricksError>> setLanguage(
  String language, {
  UpdateQueue? queue,
}) =>
    setAttributes({'language': language}, queue: queue);
