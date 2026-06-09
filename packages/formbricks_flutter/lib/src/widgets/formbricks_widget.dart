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
import '../survey/survey_store.dart';
import '../types/errors.dart';
import '../types/survey.dart';
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

  /// Returns the raw JSON the SDK has persisted in `SharedPreferences` (under
  /// the `formbricks-flutter` key), or `null` if nothing is stored yet.
  static Future<String?> debugStoredConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FormbricksConfig.storageKey);
  }

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
