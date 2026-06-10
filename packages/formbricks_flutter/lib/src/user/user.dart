/// User identity: `setUserId` and `logout`.
///
/// Ports the RN `lib/user/user.ts`. Queues identity changes through the
/// [UpdateQueue] (fire-and-forget) and resets prior state via [tearDown] when
/// switching to a different user.
library;

import 'dart:async';

import '../common/config.dart';
import '../common/logger.dart';
import '../common/result.dart';
import '../common/setup.dart';
import '../types/errors.dart';
import 'update_queue.dart';

/// Identifies the current contact as [userId].
///
/// - Same value already set → idempotent `Ok` no-op.
/// - A *different* userId already set → [tearDown] the previous user state
///   first, then queue the new id.
/// - Anonymous → queue the id directly (no teardown).
///
/// Returns immediately with `Ok`; the backend `createOrUpdateUser` fires from
/// the debounced [UpdateQueue].
Future<Result<void, FormbricksError>> setUserId(
  String userId, {
  FormbricksConfig? config,
  UpdateQueue? queue,
}) async {
  final cfg = config ?? FormbricksConfig.instance;
  final q = queue ?? UpdateQueue.instance;

  final currentUserId = cfg.get().user.data.userId;

  if (currentUserId == userId) {
    Logger.debug('UserId is already set to the same value, skipping');
    return const Result.ok(null);
  }

  if (currentUserId != null) {
    Logger.debug(
      'Different userId is being set, cleaning up previous user state',
    );
    // Drop anything queued for the previous identity so it can't be adopted by
    // the new user. Diverges from RN, which leaves the buffer intact.
    q.clear();
    await tearDown(config: cfg);
  }

  q.updateUserId(userId);
  // Fire-and-forget: the flush already logs and recovers from failures (e.g.
  // MissingFieldError), so swallow here to keep it off the host's unhandled-
  // error path. Tests await processUpdates() directly and still see the error.
  unawaited(q.processUpdates().catchError((_) {}));
  return const Result.ok(null);
}

/// Logs the current user out, resetting user state to anonymous.
Future<Result<void, FormbricksError>> logout({
  FormbricksConfig? config,
  UpdateQueue? queue,
}) async {
  Logger.debug('Logging out and cleaning user state');
  // Drop any queued update so a debounced flush can't re-identify the user
  // after logout. Diverges from RN, which leaves the buffer intact.
  (queue ?? UpdateQueue.instance).clear();
  await tearDown(config: config ?? FormbricksConfig.instance);
  return const Result.ok(null);
}
