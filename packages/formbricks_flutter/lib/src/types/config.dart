/// Persisted SDK configuration models.
///
/// These mirror the React Native SDK's `types/config.ts`. The one rule that
/// matters: **`DateTime` lives in memory, ISO-8601 strings live on the wire and
/// on disk**, and the conversion happens *only* inside the `fromJson` / `toJson`
/// methods here. No `DateTime.parse` anywhere else in the codebase.
///
/// Survey and action-class entries are intentionally loosely typed
/// (`Map<String, dynamic>`) until the track + survey-rendering work lands.
library;

/// Parses an optional ISO-8601 string into a [DateTime]. The single inbound
/// date boundary.
DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// Serializes an optional [DateTime] to an ISO-8601 string. The single outbound
/// date boundary.
String? _dateToIso(DateTime? value) => value?.toIso8601String();

/// A single survey display record.
class TDisplay {
  /// Creates a display record.
  const TDisplay({required this.surveyId, required this.createdAt});

  /// Builds a [TDisplay] from decoded JSON.
  factory TDisplay.fromJson(Map<String, dynamic> json) => TDisplay(
        surveyId: json['surveyId'] as String,
        createdAt: _parseDate(json['createdAt'])!,
      );

  /// The id of the displayed survey.
  final String surveyId;

  /// When the survey was displayed.
  final DateTime createdAt;

  /// Encodes this record to JSON with ISO-8601 dates.
  Map<String, dynamic> toJson() => {
        'surveyId': surveyId,
        'createdAt': _dateToIso(createdAt),
      };
}

/// The user-scoped slice of state (identity, segments, displays, responses).
class TUserData {
  /// Creates user data.
  const TUserData({
    this.userId,
    this.contactId,
    this.segments = const [],
    this.displays = const [],
    this.responses = const [],
    this.lastDisplayAt,
    this.language,
  });

  /// Builds [TUserData] from decoded JSON, tolerating missing keys.
  factory TUserData.fromJson(Map<String, dynamic> json) => TUserData(
        userId: json['userId'] as String?,
        contactId: json['contactId'] as String?,
        segments:
            (json['segments'] as List?)?.cast<String>() ?? const <String>[],
        displays: (json['displays'] as List?)
                ?.map((e) => TDisplay.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const <TDisplay>[],
        responses:
            (json['responses'] as List?)?.cast<String>() ?? const <String>[],
        lastDisplayAt: _parseDate(json['lastDisplayAt']),
        language: json['language'] as String?,
      );

  /// The identified user id, or null when anonymous.
  final String? userId;

  /// The resolved contact id, or null.
  final String? contactId;

  /// Segment keys the user belongs to.
  final List<String> segments;

  /// Recent survey displays.
  final List<TDisplay> displays;

  /// Response ids the user has submitted.
  final List<String> responses;

  /// When the last survey was shown, or null.
  final DateTime? lastDisplayAt;

  /// The active language code, or null.
  final String? language;

  /// Returns a copy with the given fields overridden.
  ///
  /// Sufficient for the survey-event handlers, which only *set* values
  /// (appending displays/responses, stamping `lastDisplayAt`); clearing a field
  /// back to null is not needed here, so the standard `?? this.x` fallback is
  /// safe.
  TUserData copyWith({
    String? userId,
    String? contactId,
    List<String>? segments,
    List<TDisplay>? displays,
    List<String>? responses,
    DateTime? lastDisplayAt,
    String? language,
  }) =>
      TUserData(
        userId: userId ?? this.userId,
        contactId: contactId ?? this.contactId,
        segments: segments ?? this.segments,
        displays: displays ?? this.displays,
        responses: responses ?? this.responses,
        lastDisplayAt: lastDisplayAt ?? this.lastDisplayAt,
        language: language ?? this.language,
      );

  /// Encodes this user data to JSON with ISO-8601 dates.
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'contactId': contactId,
        'segments': segments,
        'displays': displays.map((d) => d.toJson()).toList(),
        'responses': responses,
        'lastDisplayAt': _dateToIso(lastDisplayAt),
        if (language != null) 'language': language,
      };
}

/// The user state envelope: an expiry plus the user [data].
class TUserState {
  /// Creates a user state.
  const TUserState({required this.expiresAt, required this.data});

  /// Builds [TUserState] from decoded JSON.
  factory TUserState.fromJson(Map<String, dynamic> json) => TUserState(
        expiresAt: _parseDate(json['expiresAt']),
        data: TUserData.fromJson(
          (json['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        ),
      );

  /// When this user state expires, or null for anonymous (never expires).
  final DateTime? expiresAt;

  /// The user data slice.
  final TUserData data;

  /// The default anonymous user state (no user id, never expires). Mirrors RN's
  /// `DEFAULT_USER_STATE_NO_USER_ID`.
  static const TUserState defaultNoUserId = TUserState(
    expiresAt: null,
    data: TUserData(),
  );

  /// Returns a copy with the given fields overridden.
  TUserState copyWith({DateTime? expiresAt, TUserData? data}) => TUserState(
        expiresAt: expiresAt ?? this.expiresAt,
        data: data ?? this.data,
      );

  /// Encodes this user state to JSON with ISO-8601 dates.
  Map<String, dynamic> toJson() => {
        'expiresAt': _dateToIso(expiresAt),
        'data': data.toJson(),
      };
}

/// The workspace-scoped data: surveys, action classes, and settings.
///
/// Surveys and action classes stay loosely typed until track + rendering land.
class TWorkspaceData {
  /// Creates workspace data.
  const TWorkspaceData({
    this.surveys = const [],
    this.actionClasses = const [],
    this.settings = const {},
  });

  /// Builds [TWorkspaceData] from decoded JSON.
  factory TWorkspaceData.fromJson(Map<String, dynamic> json) => TWorkspaceData(
        surveys: (json['surveys'] as List?) ?? const [],
        actionClasses: (json['actionClasses'] as List?) ?? const [],
        settings: (json['settings'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  /// The workspace's surveys.
  final List<dynamic> surveys;

  /// The workspace's action classes.
  final List<dynamic> actionClasses;

  /// Workspace settings (recontactDays, placement, styling, …).
  final Map<String, dynamic> settings;

  /// Encodes this workspace data to JSON.
  Map<String, dynamic> toJson() => {
        'surveys': surveys,
        'actionClasses': actionClasses,
        'settings': settings,
      };
}

/// The workspace state envelope: an expiry plus the workspace [data].
class TWorkspaceState {
  /// Creates a workspace state.
  const TWorkspaceState({required this.expiresAt, required this.data});

  /// Builds [TWorkspaceState] from decoded JSON.
  factory TWorkspaceState.fromJson(Map<String, dynamic> json) =>
      TWorkspaceState(
        expiresAt: _parseDate(json['expiresAt'])!,
        data: TWorkspaceData.fromJson(
          (json['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        ),
      );

  /// When this workspace state expires.
  final DateTime expiresAt;

  /// The workspace data slice.
  final TWorkspaceData data;

  /// Encodes this workspace state to JSON with ISO-8601 dates.
  Map<String, dynamic> toJson() => {
        'expiresAt': _dateToIso(expiresAt),
        'data': data.toJson(),
      };
}

/// The success/error status envelope, with an optional cooldown expiry.
class TStatus {
  /// Creates a status.
  const TStatus({required this.value, this.expiresAt});

  /// Builds [TStatus] from decoded JSON.
  factory TStatus.fromJson(Map<String, dynamic> json) => TStatus(
        value: json['value'] as String? ?? 'success',
        expiresAt: _parseDate(json['expiresAt']),
      );

  /// The success default status.
  static const TStatus success = TStatus(value: 'success');

  /// Either `'success'` or `'error'`.
  final String value;

  /// When an error cooldown expires, or null.
  final DateTime? expiresAt;

  /// Whether this status represents an error state.
  bool get isError => value == 'error';

  /// Encodes this status to JSON with ISO-8601 dates.
  Map<String, dynamic> toJson() => {
        'value': value,
        'expiresAt': _dateToIso(expiresAt),
      };
}

/// The full persisted SDK config.
///
/// [workspace] is nullable: a first-setup failure persists a config that only
/// carries an error [status] (no workspace yet), and [fromJson] must round-trip
/// that shape so the error cooldown survives a reload.
class TConfig {
  /// Creates a config.
  const TConfig({
    this.workspaceId,
    this.appUrl,
    this.workspace,
    this.user = TUserState.defaultNoUserId,
    this.filteredSurveys = const [],
    this.status = TStatus.success,
  });

  /// Builds [TConfig] from decoded JSON, tolerating missing `workspace`/`user`.
  factory TConfig.fromJson(Map<String, dynamic> json) => TConfig(
        workspaceId: json['workspaceId'] as String?,
        appUrl: json['appUrl'] as String?,
        workspace: json['workspace'] == null
            ? null
            : TWorkspaceState.fromJson(
                (json['workspace'] as Map).cast<String, dynamic>(),
              ),
        user: json['user'] == null
            ? TUserState.defaultNoUserId
            : TUserState.fromJson(
                (json['user'] as Map).cast<String, dynamic>(),
              ),
        filteredSurveys: (json['filteredSurveys'] as List?) ?? const [],
        status: json['status'] == null
            ? TStatus.success
            : TStatus.fromJson((json['status'] as Map).cast<String, dynamic>()),
      );

  /// The workspace id this config belongs to.
  final String? workspaceId;

  /// The app URL the SDK talks to.
  final String? appUrl;

  /// The cached workspace state, or null in an error-only config.
  final TWorkspaceState? workspace;

  /// The cached user state (anonymous by default).
  final TUserState user;

  /// Surveys eligible to show. Populated by the filter logic in a later ticket;
  /// left empty here.
  final List<dynamic> filteredSurveys;

  /// The success/error status.
  final TStatus status;

  /// Returns a copy with the given fields overridden.
  TConfig copyWith({
    String? workspaceId,
    String? appUrl,
    TWorkspaceState? workspace,
    TUserState? user,
    List<dynamic>? filteredSurveys,
    TStatus? status,
  }) =>
      TConfig(
        workspaceId: workspaceId ?? this.workspaceId,
        appUrl: appUrl ?? this.appUrl,
        workspace: workspace ?? this.workspace,
        user: user ?? this.user,
        filteredSurveys: filteredSurveys ?? this.filteredSurveys,
        status: status ?? this.status,
      );

  /// Encodes this config to JSON with ISO-8601 dates.
  Map<String, dynamic> toJson() => {
        'workspaceId': workspaceId,
        'appUrl': appUrl,
        'workspace': workspace?.toJson(),
        'user': user.toJson(),
        'filteredSurveys': filteredSurveys,
        'status': status.toJson(),
      };
}

/// Input for a user create/update call.
class TUpdates {
  /// Creates an update payload.
  const TUpdates({required this.userId, this.attributes});

  /// The user id to identify.
  final String userId;

  /// Optional attributes to set (numbers preserved as numbers).
  final Map<String, Object?>? attributes;
}

/// Response body of `POST /api/v2/client/{workspaceId}/user`.
class CreateOrUpdateUserResponse {
  /// Creates a response.
  const CreateOrUpdateUserResponse({
    required this.state,
    this.messages,
    this.errors,
  });

  /// Builds the response from decoded JSON.
  factory CreateOrUpdateUserResponse.fromJson(Map<String, dynamic> json) =>
      CreateOrUpdateUserResponse(
        state: TUserState.fromJson(
          (json['state'] as Map).cast<String, dynamic>(),
        ),
        messages: (json['messages'] as List?)?.cast<String>(),
        errors: (json['errors'] as List?)?.cast<String>(),
      );

  /// The synced user state.
  final TUserState state;

  /// Optional informational messages.
  final List<String>? messages;

  /// Optional error messages.
  final List<String>? errors;
}
