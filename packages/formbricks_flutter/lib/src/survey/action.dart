/// Tracks code actions against cached workspace surveys.
///
/// This layer only matches action classes and leaves eligibility filtering to
/// the survey selection pipeline.
library;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../common/config.dart';
import '../common/logger.dart';
import '../common/result.dart';
import '../types/action_class.dart';
import '../types/errors.dart';
import '../types/survey.dart';
import 'survey_store.dart';

/// Connectivity check used by [track].
typedef ConnectivityCheck = Future<bool> Function();

Future<bool> _defaultIsConnected() async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
}

/// Marks [survey] for display.
void triggerSurvey(TSurvey survey, {SurveyStore? store}) =>
    (store ?? SurveyStore.instance).setSurvey(survey);

/// Triggers cached surveys whose action-class name matches [name].
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
    if (survey == null) continue;
    for (final trigger in survey.triggers) {
      if (trigger.actionClass.name == name) {
        triggerSurvey(survey, store: store);
      }
    }
  }
  return const Result.ok(null);
}

/// Tracks a code action by [code].
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
      connected = false;
    }
    if (!connected) {
      return Result.err(
        NetworkError(
          message: 'No internet connection. Please check your connection and '
              'try again.',
          status: 0,
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
  } on FormbricksError catch (e, stackTrace) {
    Logger.error('Error tracking action: $e\n$stackTrace');
    return Result.err(e);
  } catch (e, stackTrace) {
    Logger.error('Error tracking action: $e\n$stackTrace');
    return Result.err(
      InternalError(operation: 'track', cause: e, stackTrace: stackTrace),
    );
  }
}

TSurvey? _tryParseSurvey(Object? entry) {
  try {
    return TSurvey.fromJson((entry as Map).cast<String, dynamic>());
  } catch (e) {
    Logger.error('Skipping malformed survey in workspace state: $e');
    return null;
  }
}

TActionClass? _tryParseActionClass(Object? entry) {
  try {
    return TActionClass.fromJson((entry as Map).cast<String, dynamic>());
  } catch (e) {
    Logger.error('Skipping malformed action class in workspace state: $e');
    return null;
  }
}
