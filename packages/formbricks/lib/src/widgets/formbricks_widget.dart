/// The public `Formbricks` widget and static SDK facade.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/command_queue.dart';
import '../common/config.dart';
import '../common/logger.dart';
import '../common/result.dart';
import '../common/setup.dart' as setup_internal;
import '../survey/action.dart' as action;
import '../survey/embedded_data.dart';
import '../survey/survey_store.dart';
import '../types/errors.dart';
import '../types/survey.dart';
import '../user/attribute.dart' as attribute;
import '../user/user.dart' as user;
import 'default_webview_host.dart';
import 'survey_webview.dart';
import 'webview_navigation.dart';

/// The Formbricks SDK facade and drop-in host widget.
///
/// Place `Formbricks(appUrl: ..., workspaceId: ...)` in your widget tree: it
/// initializes the SDK on mount (idempotent) and renders any active survey in a
/// modal WebView route. The imperative API (`setup`, `track`) lives as static
/// methods that route through a hidden command queue so calls run in strict
/// submission order.
/// The "no argument" marker for [Formbricks.clearEmbeddedData]. A private const
/// object, so no caller can produce a value `identical` to it by accident.
const Object _clearWholeBag = Object();

class Formbricks extends StatefulWidget {
  /// Creates the host widget for [appUrl] / [workspaceId].
  const Formbricks({
    super.key,
    required this.appUrl,
    required this.workspaceId,
    this.logLevel,
    @visibleForTesting this.webViewHostBuilder,
    @visibleForTesting this.launch,
    @visibleForTesting this.httpClient,
    @visibleForTesting this.startTicker = true,
  });

  /// The Formbricks app URL.
  final String appUrl;

  /// The workspace id.
  final String workspaceId;

  /// Optional log level (defaults from build mode in `setup`).
  final LogLevel? logLevel;

  /// WebView host builder override.
  final WebViewHostBuilder? webViewHostBuilder;

  /// External-URL launcher override.
  final LaunchUrlFn? launch;

  /// HTTP client override for `setup`.
  final http.Client? httpClient;

  /// Whether the expiry ticker is started by `setup`.
  final bool startTicker;

  static final CommandQueue _queue = CommandQueue(
    isSetup: () => setup_internal.isSetup,
  );

  /// Initializes the SDK against [appUrl] / [workspaceId].
  ///
  /// Completes with `Ok` on success or `Err(MissingFieldError)` for invalid
  /// input. Throws [FormbricksSetupError] if the *first* setup attempt fails on
  /// the network (the SDK then enters a 10-minute error cooldown). Runs with
  /// `checkSetup: false` because it is what flips the SDK into the set-up state.
  static Future<Result<void, FormbricksError>> setup({
    required String appUrl,
    required String workspaceId,
    LogLevel? logLevel,
    @visibleForTesting http.Client? httpClient,
    @visibleForTesting bool startTicker = true,
  }) {
    return _queue.add<Result<void, FormbricksError>>(
      () => setup_internal.setup(
        appUrl: appUrl,
        workspaceId: workspaceId,
        logLevel: logLevel,
        httpClient: httpClient,
        startTicker: startTicker,
      ),
      checkSetup: false,
    );
  }

  /// Tracks a code action through the command queue (`checkSetup: true`).
  ///
  /// Returns `Ok` when the action matched (or matched nothing), an
  /// `Err(InvalidCodeError)` for an unknown code, or an `Err(NetworkError)` when
  /// offline. A matching survey is marked for display and rendered by any
  /// mounted [Formbricks] widget.
  static Future<Result<void, FormbricksError>> track(String name) {
    return _queue.add<Result<void, FormbricksError>>(
      () => action.track(name),
      checkSetup: true,
    );
  }

  /// Identifies the current contact as [userId] (`checkSetup: true`).
  ///
  /// Idempotent for the already-set value; switching to a different id resets
  /// the prior user state first. The backend sync runs from the debounced
  /// update queue, so this resolves before the network call completes.
  static Future<Result<void, FormbricksError>> setUserId(String userId) {
    return _queue.add<Result<void, FormbricksError>>(
      () => user.setUserId(userId),
      checkSetup: true,
    );
  }

  /// Sets a single contact attribute [key] = [value] (`checkSetup: true`).
  ///
  /// [value] may be a `String`, `num`, or `DateTime` (dates serialize to
  /// ISO-8601). Requires a userId to have been set; otherwise the queued update
  /// is dropped with an error logged.
  static Future<Result<void, FormbricksError>> setAttribute(
    String key,
    Object value,
  ) {
    return _queue.add<Result<void, FormbricksError>>(
      () => attribute.setAttributes({key: value}),
      checkSetup: true,
    );
  }

  /// Sets multiple contact [attributes] at once (`checkSetup: true`).
  ///
  /// Values may be `String`, `num`, or `DateTime`. See [setAttribute].
  static Future<Result<void, FormbricksError>> setAttributes(
    Map<String, Object> attributes,
  ) {
    return _queue.add<Result<void, FormbricksError>>(
      () => attribute.setAttributes(attributes),
      checkSetup: true,
    );
  }

  /// Sets the contact's preferred [language] (`checkSetup: true`).
  ///
  /// With no userId set, this updates only the local config (no network call).
  static Future<Result<void, FormbricksError>> setLanguage(String language) {
    return _queue.add<Result<void, FormbricksError>>(
      () => attribute.setLanguage(language),
      checkSetup: true,
    );
  }

  /// Attaches Embedded Data to future responses without tying it to a trigger.
  ///
  /// Merges into an in-memory bag — last write wins per key, and an explicit
  /// `null` removes a key. Values land only on the survey's declared *ingested*
  /// fields; anything else is dropped and logged by the survey renderer, never
  /// fatal. Values must be a `String`, `num`, `bool` or `DateTime`.
  ///
  /// Deliberately synchronous and **not** routed through the command queue,
  /// unlike the methods above: a host that pushes context at launch must not
  /// have that value silently dropped because `setup` had not finished. The bag
  /// is pure memory — nothing here needs the SDK to be running, and calling it
  /// on every screen change is free.
  ///
  /// The bag is snapshotted when a survey is displayed and frozen for its
  /// lifetime, so a value set while a survey is on screen reaches the *next*
  /// response, not that one. It is never persisted: a cold app start begins
  /// empty and the host re-pushes.
  ///
  /// ```dart
  /// Formbricks.setEmbeddedData({'plan': 'pro', 'seats': 25});
  /// Formbricks.setEmbeddedData({'screen': null}); // removes the key
  /// ```
  static void setEmbeddedData(Map<String, Object?> data) {
    EmbeddedDataStore.instance.set(data);
  }

  /// Removes one Embedded Data key, or the whole bag when called with no
  /// argument — logout, or a hard context switch.
  ///
  /// ```dart
  /// Formbricks.clearEmbeddedData('plan'); // one key
  /// Formbricks.clearEmbeddedData();       // everything
  /// ```
  ///
  /// The [key] is typed `Object?` around a private sentinel rather than as a
  /// plain `String?`, so that "called with no argument" and "called with a key
  /// that evaluated to null" stay different things — the same distinction the
  /// JS SDK draws by argument count. A host that reads the key from its own
  /// state (`clearEmbeddedData(prefs['fieldToClear'])`) must not wipe the whole
  /// bag when that state is empty; that call is a logged no-op.
  static void clearEmbeddedData([Object? key = _clearWholeBag]) {
    if (identical(key, _clearWholeBag)) {
      EmbeddedDataStore.instance.clear();
      return;
    }
    if (key is! String) {
      Logger.error(
        'clearEmbeddedData: expected a field name — nothing was cleared '
        '(call with no argument to clear everything)',
      );
      return;
    }
    EmbeddedDataStore.instance.remove(key);
  }

  /// Logs the current user out, resetting user state to anonymous
  /// (`checkSetup: true`).
  static Future<Result<void, FormbricksError>> logout() {
    return _queue.add<Result<void, FormbricksError>>(
      () => user.logout(),
      checkSetup: true,
    );
  }

  /// Returns the raw JSON the SDK has persisted in `SharedPreferences` (under
  /// the `formbricks-flutter` key), or `null` if nothing is stored yet.
  static Future<String?> debugStoredConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FormbricksConfig.storageKey);
  }

  /// Clears the persisted config (the `formbricks-flutter` key) and the
  /// in-memory copy. Debug helper — the SDK stays "set up" for this process, so
  /// the next workspace/user sync will repopulate storage.
  static Future<void> debugClearStoredConfig() =>
      FormbricksConfig.instance.reset();

  @override
  State<Formbricks> createState() => _FormbricksState();
}

class _FormbricksState extends State<Formbricks> {
  @override
  void initState() {
    super.initState();
    unawaited(_setup());
  }

  Future<void> _setup() async {
    try {
      final result = await Formbricks.setup(
        appUrl: widget.appUrl,
        workspaceId: widget.workspaceId,
        logLevel: widget.logLevel,
        httpClient: widget.httpClient,
        startTicker: widget.startTicker,
      );
      if (result case Err(:final error)) {
        Logger.error(
          'Initialization failed: ${error.code.wire}: ${error.message}',
        );
      }
    } on FormbricksError catch (error) {
      Logger.error(
        'Initialization failed: ${error.code.wire}: ${error.message}',
      );
    } catch (e, stackTrace) {
      Logger.error('Initialization failed: $e\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TSurvey?>(
      valueListenable: SurveyStore.instance.listenable,
      builder: (context, survey, _) => survey == null
          ? const SizedBox.shrink()
          : SurveyWebView(
              // A different survey id forces a fresh State and route teardown.
              key: ValueKey<String>(survey.id),
              survey: survey,
              webViewHostBuilder: widget.webViewHostBuilder,
              launch: widget.launch,
            ),
    );
  }
}
