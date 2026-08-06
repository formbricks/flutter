/// Post-interaction segment refresh.
///
/// A `surveyInteraction` segment filter ("have seen X", "have completed X", ...)
/// can change who a contact is the moment they interact with a survey. Segment
/// membership is only ever computed by the backend, so the local bookkeeping in
/// the WebView host (displays / responses) is not enough — the user state has to
/// be refetched.
library;

import 'dart:async';

import '../common/logger.dart';
import '../types/survey.dart';
import 'update_queue.dart';

/// Pulls fresh server-computed `segments` after an interaction that can flip
/// segment membership, instead of waiting for the user state to expire.
///
/// The refresh is deliberately gated twice, because a `/user` sync is not cheap:
///  * no-op for anonymous users, who never receive segments in the first place;
///  * no-op unless the backend set the bit for this survey and this event.
///
/// It is routed through the [UpdateQueue] rather than sending directly, so a
/// display -> response -> finish burst coalesces into a single request.
void refreshSegmentsAfterInteraction(
  String? userId,
  TSurvey survey,
  InteractionSource source,
) {
  if (userId == null || userId.isEmpty) return;
  if (!(survey.interactionRefresh?.shouldRefresh(source) ?? false)) return;

  Logger.debug(
    'Refreshing segments after ${source.name} on survey ${survey.id}',
  );

  final queue = UpdateQueue.instance;
  queue.updateUserId(userId);
  // `processUpdates` completes with an error when the flush throws, and this is
  // fire-and-forget — `unawaited` marks the future as intentionally not awaited but
  // does not handle its errors, so one would surface as an unhandled async error.
  // The queue already logs the real cause, so swallow it rather than report twice.
  unawaited(
    queue.processUpdates().catchError((Object _) {
      // Intentionally empty. The queue already logged the real cause; this handler
      // exists only so the error does not escape an unawaited future.
    }),
  );
}
