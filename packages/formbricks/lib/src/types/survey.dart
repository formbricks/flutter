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
    this.displayOption,
    this.displayLimit,
    this.recontactDays,
    this.displayPercentage,
    this.segment,
    this.interactionRefresh,
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
        displayOption: json['displayOption'] as String?,
        displayLimit: (json['displayLimit'] as num?)?.toInt(),
        recontactDays: (json['recontactDays'] as num?)?.toInt(),
        displayPercentage: json['displayPercentage'] as num?,
        segment: json['segment'] == null
            ? null
            : TSurveySegment.fromJson(
                (json['segment'] as Map).cast<String, dynamic>(),
              ),
        interactionRefresh: json['interactionRefresh'] is Map
            ? TInteractionRefresh.fromJson(
                (json['interactionRefresh'] as Map).cast<String, dynamic>(),
              )
            : null,
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

  /// How often the survey may be shown (`respondMultiple` / `displayOnce` /
  /// `displayMultiple` / `displaySome`); unknown values make it ineligible.
  final String? displayOption;

  /// Max number of displays for `'displaySome'`, or null for unlimited.
  final int? displayLimit;

  /// Days since the last display before showing again, or null to fall back
  /// to the workspace `settings.recontactDays`.
  final int? recontactDays;

  /// Percentage of trigger hits that display the survey; null/0 always shows.
  final num? displayPercentage;

  /// The segment targeting this survey, or null when untargeted.
  final TSurveySegment? segment;

  /// Whether interacting with this survey can change some live survey's segment
  /// membership. Null unless the workspace uses survey-interaction targeting.
  final TInteractionRefresh? interactionRefresh;

  final Map<String, dynamic> _raw;

  /// Whether the survey is available in more than one language.
  bool get isMultiLanguage => languages.length > 1;

  /// The original decoded JSON, returned verbatim for the survey runtime.
  Map<String, dynamic> toJson() => _raw;
}

/// The survey-lifecycle moments that can flip interaction-based segment
/// membership. Names match the source names used by the JS SDK.
enum InteractionSource {
  /// A display was created — drives `have seen` / `have not seen`.
  onDisplay,

  /// A response was created — drives `have started responding to`.
  onResponse,

  /// The response was finished — drives `have completed` / `have not completed`.
  onFinished,
}

/// Per-survey gate for the post-interaction segment refresh.
///
/// Each flag says whether interacting with *this* survey via that event can
/// change some live survey's segment membership — so a survey referenced only by
/// a "have seen" filter refreshes on display but not on response or finish, and
/// a survey no interaction filter points at never refreshes at all.
///
/// The client API attaches this only for workspaces that use survey-interaction
/// targeting, so it is absent for everyone else, and present-but-all-false for
/// surveys in such a workspace that no interaction filter references.
class TInteractionRefresh {
  /// Creates a gate. Every flag defaults to "do not refresh".
  const TInteractionRefresh({
    this.onDisplay = false,
    this.onResponse = false,
    this.onFinished = false,
  });

  /// Builds a gate from decoded JSON.
  ///
  /// Deliberately tolerant: a missing or non-boolean flag reads as `false`, so a
  /// partial object from the server can never fail the workspace-state decode
  /// and blank out every survey.
  factory TInteractionRefresh.fromJson(Map<String, dynamic> json) =>
      TInteractionRefresh(
        onDisplay: json['onDisplay'] == true,
        onResponse: json['onResponse'] == true,
        onFinished: json['onFinished'] == true,
      );

  /// Whether a display can flip membership.
  final bool onDisplay;

  /// Whether a created response can flip membership.
  final bool onResponse;

  /// Whether finishing the survey can flip membership.
  final bool onFinished;

  /// Whether an interaction of this kind should trigger a user-state refresh.
  bool shouldRefresh(InteractionSource source) => switch (source) {
        InteractionSource.onDisplay => onDisplay,
        InteractionSource.onResponse => onResponse,
        InteractionSource.onFinished => onFinished,
      };
}

/// The minimal segment shape read for targeting: `{ id, hasFilters }`.
/// Tolerates the legacy cached shape carrying a full `filters` array.
class TSurveySegment {
  /// Creates a segment.
  const TSurveySegment({this.id, required this.hasFilters});

  /// Builds a segment from decoded JSON.
  factory TSurveySegment.fromJson(Map<String, dynamic> json) {
    final hasFilters = json['hasFilters'];
    final filters = json['filters'];
    return TSurveySegment(
      id: json['id'] as String?,
      hasFilters: hasFilters is bool
          ? hasFilters
          : filters is List && filters.isNotEmpty,
    );
  }

  /// The segment id matched against `user.segments`, or null.
  final String? id;

  /// Whether the segment carries filter rules.
  final bool hasFilters;
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
