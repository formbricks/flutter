/// Typed survey models.
///
/// Raw-preserving by design. The full survey object is JSON-serialized into
/// the WebView HTML and handed to `window.formbricksSurveys.renderSurvey(...)`,
/// so it must round-trip losslessly, including every field Dart never reads
/// (questions, endings, variables, etc.). Each model therefore keeps the original
/// decoded map and parses typed getters off it; [TSurvey.toJson] returns that
/// original map verbatim.
library;

/// A single Formbricks survey.
class TSurvey {
  /// Creates a survey from already-parsed fields plus the original [raw] map.
  const TSurvey({
    required this.id,
    required this.triggers,
    required this.languages,
    required this.delay,
    this.styling,
    this.projectOverwrites,
    required Map<String, dynamic> raw,
  }) : _raw = raw;

  /// Builds a [TSurvey] from decoded JSON, retaining [json] for lossless
  /// re-serialization into the survey runtime.
  factory TSurvey.fromJson(Map<String, dynamic> json) => TSurvey(
        id: json['id'] as String,
        triggers: (json['triggers'] as List?)
                ?.map(
                  (e) => TSurveyTrigger.fromJson(
                    (e as Map).cast<String, dynamic>(),
                  ),
                )
                .toList() ??
            const [],
        languages: (json['languages'] as List?)
                ?.map(
                  (e) => TSurveyLanguage.fromJson(
                    (e as Map).cast<String, dynamic>(),
                  ),
                )
                .toList() ??
            const [],
        delay: (json['delay'] as num?)?.toInt() ?? 0,
        styling: (json['styling'] as Map?)?.cast<String, dynamic>(),
        projectOverwrites: json['projectOverwrites'] == null
            ? null
            : TProjectOverwrites.fromJson(
                (json['projectOverwrites'] as Map).cast<String, dynamic>(),
              ),
        raw: json,
      );

  /// The survey id.
  final String id;

  /// The triggers that can show this survey.
  final List<TSurveyTrigger> triggers;

  /// The survey's languages.
  final List<TSurveyLanguage> languages;

  /// Seconds to wait before presenting the survey.
  final int delay;

  /// Survey-level styling overrides (raw map; read `overwriteThemeStyling`,
  /// forwarded to the runtime). Null when the survey carries no styling.
  final Map<String, dynamic>? styling;

  /// Per-project overrides for placement / click-outside / overlay.
  final TProjectOverwrites? projectOverwrites;

  final Map<String, dynamic> _raw;

  /// Whether the survey is available in more than one language.
  bool get isMultiLanguage => languages.length > 1;

  /// The original decoded JSON, returned verbatim for the survey runtime.
  Map<String, dynamic> toJson() => _raw;
}

/// A survey trigger. Only the action-class name is read by the SDK.
class TSurveyTrigger {
  /// Creates a trigger.
  const TSurveyTrigger({required this.actionClass});

  /// Builds a trigger from decoded JSON.
  factory TSurveyTrigger.fromJson(Map<String, dynamic> json) => TSurveyTrigger(
        actionClass: TTriggerActionClass.fromJson(
          (json['actionClass'] as Map).cast<String, dynamic>(),
        ),
      );

  /// The action class this trigger fires on.
  final TTriggerActionClass actionClass;
}

/// The minimal action-class shape referenced by a trigger.
class TTriggerActionClass {
  /// Creates a trigger action class.
  const TTriggerActionClass({required this.name});

  /// Builds it from decoded JSON.
  factory TTriggerActionClass.fromJson(Map<String, dynamic> json) =>
      TTriggerActionClass(name: json['name'] as String);

  /// The action-class name a tracked action is matched against.
  final String name;
}

/// A survey language entry: `{ default, enabled, language }`.
class TSurveyLanguage {
  /// Creates a survey language.
  const TSurveyLanguage({
    required this.isDefault,
    required this.enabled,
    required this.language,
  });

  /// Builds it from decoded JSON.
  factory TSurveyLanguage.fromJson(Map<String, dynamic> json) =>
      TSurveyLanguage(
        isDefault: json['default'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? false,
        language: TLanguage.fromJson(
          (json['language'] as Map).cast<String, dynamic>(),
        ),
      );

  /// Whether this is the survey's default language.
  final bool isDefault;

  /// Whether this language is enabled.
  final bool enabled;

  /// The language descriptor.
  final TLanguage language;
}

/// A language descriptor: `{ code, alias }`.
class TLanguage {
  /// Creates a language.
  const TLanguage({required this.code, this.alias});

  /// Builds it from decoded JSON.
  factory TLanguage.fromJson(Map<String, dynamic> json) => TLanguage(
        code: json['code'] as String,
        alias: json['alias'] as String?,
      );

  /// The ISO language code.
  final String code;

  /// An optional human alias for the language.
  final String? alias;
}

/// Per-project survey overrides used when resolving render options.
class TProjectOverwrites {
  /// Creates project overrides.
  const TProjectOverwrites({
    this.placement,
    this.clickOutsideClose,
    this.overlay,
  });

  /// Builds it from decoded JSON.
  factory TProjectOverwrites.fromJson(Map<String, dynamic> json) =>
      TProjectOverwrites(
        placement: json['placement'] as String?,
        clickOutsideClose: json['clickOutsideClose'] as bool?,
        overlay: json['overlay'] as String?,
      );

  /// Overridden placement, or null to fall back to workspace settings.
  final String? placement;

  /// Overridden click-outside-to-close, or null to fall back.
  final bool? clickOutsideClose;

  /// Overridden overlay mode, or null to fall back.
  final String? overlay;
}
