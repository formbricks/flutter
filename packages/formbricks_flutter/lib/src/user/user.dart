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
    await tearDown(config: cfg);
  }

  q.updateUserId(userId);
  unawaited(q.processUpdates());
  return const Result.ok(null);
}

/// Logs the current user out, resetting user state to anonymous.
Future<Result<void, FormbricksError>> logout({FormbricksConfig? config}) async {
  Logger.debug('Logging out and cleaning user state');
  await tearDown(config: config ?? FormbricksConfig.instance);
  return const Result.ok(null);
}
