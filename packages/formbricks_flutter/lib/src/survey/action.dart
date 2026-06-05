/// Action tracking, ported from the React Native SDK's `lib/survey/action.ts`
/// — **minus** eligibility filtering and the `displayPercentage` gate (those
/// belong to the filtering ticket). For this ticket `track` matches triggers
/// against the full cached survey list and shows any match.
library;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../common/config.dart';
import '../common/logger.dart';
import '../common/result.dart';
import '../types/action_class.dart';
import '../types/errors.dart';
import '../types/survey.dart';
import 'survey_store.dart';

/// Signature for the connectivity check — injectable so tests don't hit the
/// platform channel.
typedef ConnectivityCheck = Future<bool> Function();

/// Default connectivity check via `connectivity_plus`: connected when any
/// transport other than `none` is reported.
Future<bool> _defaultIsConnected() async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
}

/// Marks [survey] for display by handing it to the [SurveyStore].
///
/// No `displayPercentage` gate (excluded from this ticket).
void triggerSurvey(TSurvey survey, {SurveyStore? store}) =>
    (store ?? SurveyStore.instance).setSurvey(survey);

/// Walks the cached surveys and triggers any whose trigger action-class name
/// matches [name]. Returns `Ok` (the only failure modes — bad input / offline —
/// are handled by [track]).
Future<Result<void, FormbricksError>> trackAction(
  String name, {
  String? alias,
  FormbricksConfig? config,
  SurveyStore? store,
}) async {
  final cfg = (config ?? FormbricksConfig.instance).get();
  Logger.debug('Formbricks: Action "${alias ?? name}" tracked');

  final rawSurveys = cfg.workspace?.data.surveys ?? const [];
  if (rawSurveys.isEmpty) {
    Logger.debug('No active surveys to display');
    return const Result.ok(null);
  }

  for (final entry in rawSurveys) {
    final survey = _tryParseSurvey(entry);
    if (survey == null) continue; // malformed cache entry: logged + skipped
    for (final trigger in survey.triggers) {
      if (trigger.actionClass.name == name) {
        triggerSurvey(survey, store: store);
      }
    }
  }
  return const Result.ok(null);
}

/// Tracks a **code** action by [code].
///
/// 1. Read config first (matches RN order).
/// 2. Connectivity guard — if offline (or the check throws), return a detailed
///    `network_error` so we never render a WebView that can't load the runtime.
/// 3. Look up the `code` action class by `key == code`; unknown → `invalid_code`.
/// 4. Delegate to [trackAction] using the action-class name.
Future<Result<void, FormbricksError>> track(
  String code, {
  FormbricksConfig? config,
  SurveyStore? store,
  ConnectivityCheck? isConnected,
}) async {
  final fc = config ?? FormbricksConfig.instance;
  try {
    final cfg = fc.get();

    bool connected;
    try {
      connected = await (isConnected ?? _defaultIsConnected)();
    } catch (_) {
      // A thrown connectivity check counts as offline (not the generic catch),
      // so callers still get the specific offline error.
      connected = false;
    }
    if (!connected) {
      return Result.err(
        NetworkError(
          message: 'No internet connection. Please check your connection and '
              'try again.',
          status: 500,
          url: Uri.tryParse('${cfg.appUrl}/js/surveys.umd.cjs'),
          responseMessage:
              'No internet connection. Please check your connection and try '
              'again.',
        ),
      );
    }

    final rawActionClasses = cfg.workspace?.data.actionClasses ?? const [];
    TActionClass? match;
    for (final entry in rawActionClasses) {
      final actionClass = _tryParseActionClass(entry);
      if (actionClass == null) continue;
      if (actionClass.type == 'code' && actionClass.key == code) {
        match = actionClass;
        break;
      }
    }

    if (match == null) {
      return Result.err(
        InvalidCodeError(
          "Action with identifier '$code' is unknown. Please add this action "
          'in Formbricks in order to use it via the SDK action tracking.',
        ),
      );
    }

    return trackAction(match.name, alias: code, config: fc, store: store);
  } catch (e) {
    Logger.error('Error tracking action $e');
    return Result.err(
      NetworkError(message: 'Error tracking action', status: 500),
    );
  }
}

TSurvey? _tryParseSurvey(Object? entry) {
  try {
    return TSurvey.fromJson((entry as Map).cast<String, dynamic>());
  } catch (e) {
    Logger.error('Skipping malformed cached survey: $e');
    return null;
  }
}

TActionClass? _tryParseActionClass(Object? entry) {
  try {
    return TActionClass.fromJson((entry as Map).cast<String, dynamic>());
  } catch (e) {
    Logger.error('Skipping malformed cached action class: $e');
    return null;
  }
}
