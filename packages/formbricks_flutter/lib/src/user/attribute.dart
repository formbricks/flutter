/// Contact attributes: `setAttributes` and `setLanguage`.
///
/// Ports the RN `lib/user/attribute.ts`. The backend infers each attribute's
/// type from the JSON value type, so values cross the wire with their natural
/// type: `String` stays a string, `num` stays a number, and `DateTime` is
/// converted to an ISO-8601 string at this one boundary (plan §7 #4).
library;

import 'dart:async';

import '../common/result.dart';
import '../types/errors.dart';
import 'update_queue.dart';

/// Sets [attributes] on the current user/contact.
///
/// `DateTime` values become UTC ISO-8601 strings; `num` and `String` values are
/// passed through unchanged. Queues the change through the debounced
/// [UpdateQueue] and returns `Ok` immediately (the network call, and any
/// no-userId error, surface from the queue's flush).
Future<Result<void, FormbricksError>> setAttributes(
  Map<String, Object?> attributes, {
  UpdateQueue? queue,
}) async {
  final normalized = <String, Object?>{};
  attributes.forEach((key, value) {
    normalized[key] =
        value is DateTime ? value.toUtc().toIso8601String() : value;
  });

  final q = queue ?? UpdateQueue.instance;
  q.updateAttributes(normalized);
  unawaited(q.processUpdates());
  return const Result.ok(null);
}

/// Sets the contact's preferred [language].
///
/// Routes through [setAttributes] exactly as RN does — this is what makes the
/// "language without a userId updates local config only" path reachable.
Future<Result<void, FormbricksError>> setLanguage(
  String language, {
  UpdateQueue? queue,
}) =>
    setAttributes({'language': language}, queue: queue);
