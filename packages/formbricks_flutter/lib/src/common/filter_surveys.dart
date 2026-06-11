/// Survey eligibility filtering. Ports RN's `filterSurveys` and helpers
/// (`lib/common/utils.ts:11–143`).
///
/// The eligible set is recomputed at every state-change point and persisted
/// as `TConfig.filteredSurveys`; the trigger path reads only that set.
library;

import 'package:clock/clock.dart';

import '../types/config.dart';
import '../types/survey.dart';
import 'logger.dart';
import 'utils.dart';

/// Whole days between [date1] and [date2], direction-agnostic.
int diffInDays(DateTime date1, DateTime date2) =>
    date1.difference(date2).inMilliseconds.abs() ~/ Duration.millisecondsPerDay;

/// Whether [survey] targets a segment that carries filter rules.
bool surveyHasSegmentFilters(TSurvey survey) =>
    survey.segment?.hasFilters ?? false;

/// Returns the surveys in [workspace] that [user] is eligible to see, in
/// three stages: displayOption, recontactDays, segment targeting. Malformed
/// entries are skipped. [now] is the recontact-stage test seam.
List<TSurvey> filterSurveys(
  TWorkspaceState workspace,
  TUserState user, {
  DateTime Function()? now,
}) {
  final resolveNow = now ?? clock.now;
  final settings = workspace.data.settings;
  final userData = user.data;

  final filtered = workspace.data.surveys
      .map((entry) => tryParseSurvey(entry, source: 'workspace state'))
      .whereType<TSurvey>()
      .where((survey) => _passesDisplayOption(survey, userData))
      .where(
        (survey) =>
            _passesRecontactDays(survey, userData, settings, resolveNow),
      )
      .toList();

  // Like RN's `!userId`, an empty string counts as anonymous.
  final userId = userData.userId;
  if (userId == null || userId.isEmpty) return _filterAnonymous(filtered);
  if (userData.segments.isEmpty) return _filterIdentifiedWithoutSegments();

  return filtered
      .where(
        (survey) =>
            survey.segment?.id != null &&
            userData.segments.contains(survey.segment!.id),
      )
      .toList();
}

/// Stage 1 — displayOption (`utils.ts:65–98`).
bool _passesDisplayOption(TSurvey survey, TUserData user) {
  switch (survey.displayOption) {
    case 'respondMultiple':
      return true;
    case 'displayOnce':
      return user.displays.every((d) => d.surveyId != survey.id);
    case 'displayMultiple':
      return !user.responses.contains(survey.id);
    case 'displaySome':
      final limit = survey.displayLimit;
      if (limit == null) return true;
      if (user.responses.contains(survey.id)) return false;
      return user.displays.where((d) => d.surveyId == survey.id).length < limit;
    default:
      // Diverges from RN, which throws here: exclude just this survey
      // instead of killing the whole filter run.
      Logger.debug(
        'Excluding survey "${survey.id}" with unknown displayOption '
        '"${survey.displayOption}"',
      );
      return false;
  }
}

/// Stage 2 — recontactDays (`utils.ts:101–126`).
bool _passesRecontactDays(
  TSurvey survey,
  TUserData user,
  Map<String, dynamic> settings,
  DateTime Function() now,
) {
  final lastDisplayAt = user.lastDisplayAt;
  if (lastDisplayAt == null) return true;

  // lastDisplayAt is shared across surveys; per-survey history only feeds
  // the displayOption stage.
  final surveyRecontactDays = survey.recontactDays;
  if (surveyRecontactDays != null) {
    return diffInDays(now(), lastDisplayAt) >= surveyRecontactDays;
  }

  // Type check, not cast: non-num garbage from the backend behaves as unset.
  final workspaceRecontactDays = settings['recontactDays'];
  if (workspaceRecontactDays is num) {
    return diffInDays(now(), lastDisplayAt) >= workspaceRecontactDays.toInt();
  }

  return true;
}

/// Stage 3a — anonymous (`utils.ts:128–133`): segment-filtered surveys are
/// hidden.
List<TSurvey> _filterAnonymous(List<TSurvey> surveys) =>
    surveys.where((survey) => !surveyHasSegmentFilters(survey)).toList();

/// Stage 3b — identified with no matched segments (`utils.ts:135–137`):
/// nothing is eligible.
List<TSurvey> _filterIdentifiedWithoutSegments() => const [];
