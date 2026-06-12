/// Survey rendering helpers.
library;

import 'dart:math';

import '../types/survey.dart';
import 'logger.dart';

/// Parses a raw survey entry, returning null (and logging [source]) when
/// malformed.
TSurvey? tryParseSurvey(Object? entry, {required String source}) {
  try {
    return TSurvey.fromJson((entry as Map).cast<String, dynamic>());
  } catch (e) {
    Logger.error('Skipping malformed survey in $source: $e');
    return null;
  }
}

/// Shared RNG for the display-percentage roll (not a security context, so
/// plain [Random] over `Random.secure()`).
final Random _sharedRandom = Random();

/// Rolls whether a survey should display given its [displayPercentage]
/// (0–100). [random] is the test seam.
bool shouldDisplayBasedOnPercentage(num displayPercentage, {Random? random}) =>
    (random ?? _sharedRandom).nextDouble() * 100 < displayPercentage;

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
/// The default-language match is accepted before the enabled check.
String? getLanguageCode(TSurvey survey, [String? language]) {
  if (language == null) return 'default';
  final lower = language.toLowerCase();

  TSurveyLanguage? selected;
  for (final l in survey.languages) {
    if (l.language.code.toLowerCase() == lower ||
        l.language.alias?.toLowerCase() == lower) {
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
Map<String, dynamic> getStyling(
  Map<String, dynamic> settings,
  TSurvey survey,
) {
  final workspaceStyling =
      (settings['styling'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};

  if (workspaceStyling['allowStyleOverwrite'] == true) {
    final surveyStyling = survey.styling;
    if (surveyStyling == null ||
        surveyStyling['overwriteThemeStyling'] != true) {
      return workspaceStyling;
    }
    return surveyStyling;
  }

  return workspaceStyling;
}
