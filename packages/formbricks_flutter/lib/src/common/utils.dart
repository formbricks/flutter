/// Survey rendering helpers ported from the React Native SDK's
/// `lib/common/utils.ts` — **only** `getLanguageCode`, `getDefaultLanguageCode`,
/// and `getStyling`. `filterSurveys` and `shouldDisplayBasedOnPercentage` are
/// intentionally **not** ported here; they belong to the eligibility-filtering
/// ticket.
library;

import '../types/survey.dart';

/// Returns the code of the survey's default language, or null when none is
/// marked default.
String? getDefaultLanguageCode(TSurvey survey) {
  for (final l in survey.languages) {
    if (l.isDefault) return l.language.code;
  }
  return null;
}

/// Resolves the language code to render the survey in.
///
/// Returns `'default'` when no [language] is requested or the requested one is
/// the survey's default; the matched code when it is an enabled, available
/// non-default language; and null when the survey is **not available** in the
/// requested language (the caller must then not present and reset the store).
///
/// Branch order matches RN exactly: the default-language short-circuit happens
/// *before* the enabled/availability check.
String? getLanguageCode(TSurvey survey, [String? language]) {
  if (language == null) return 'default';
  final lower = language.toLowerCase();

  TSurveyLanguage? selected;
  for (final l in survey.languages) {
    if (l.language.code == lower || l.language.alias?.toLowerCase() == lower) {
      selected = l;
      break;
    }
  }

  if (selected == null) return null;
  if (selected.isDefault) return 'default';

  final codes = survey.languages.map((l) => l.language.code).toSet();
  if (!selected.enabled || !codes.contains(selected.language.code)) return null;
  return selected.language.code;
}

/// Resolves the styling object to hand the survey runtime.
///
/// Workspace vs survey-level resolution, ported from RN `getStyling`. Operates
/// on raw maps so the result round-trips losslessly into the render options.
/// Returns null only in the (rare) overwrite-enabled branch where the survey
/// itself carries no styling — the HTML builder then omits the key, matching
/// JS `JSON.stringify` dropping `undefined`.
Map<String, dynamic>? getStyling(
  Map<String, dynamic> settings,
  TSurvey survey,
) {
  final workspaceStyling =
      (settings['styling'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};

  // Workspace allows survey-level overrides.
  if (workspaceStyling['allowStyleOverwrite'] == true) {
    // Survey opts out of overriding the theme: use workspace styling.
    if (survey.styling?['overwriteThemeStyling'] != true) {
      return workspaceStyling;
    }
    // Survey overrides the theme: use survey styling (may be null).
    return survey.styling;
  }

  // Workspace disallows overrides: always use workspace styling.
  return workspaceStyling;
}
