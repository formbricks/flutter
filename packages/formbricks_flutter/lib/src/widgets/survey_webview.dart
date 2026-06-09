/// The survey WebView host.
///
/// The lifecycle is driven by a single state machine inside the `State`.
/// `build()` always returns a zero-size box; the survey is shown in a
/// transparent modal route held by this State so teardown paths never need a
/// deactivated `BuildContext`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import '../common/config.dart';
import '../common/logger.dart';
import '../common/utils.dart';
import '../survey/survey_store.dart';
import '../types/config.dart';
import '../types/survey.dart';
import 'default_webview_host.dart';
import 'survey_html.dart';
import 'webview_event.dart';
import 'webview_navigation.dart';

enum _SurveyPhase { idle, loading, presenting, closing }

/// Hosts a single survey in a transparent modal WebView route.
class SurveyWebView extends StatefulWidget {
  /// Creates a survey WebView for [survey].
  const SurveyWebView({
    super.key,
    required this.survey,
    this.config,
    this.store,
    this.webViewHostBuilder,
    this.launch,
  });

  /// The survey to present.
  final TSurvey survey;

  /// Config singleton override (defaults to [FormbricksConfig.instance]).
  final FormbricksConfig? config;

  /// Store override (defaults to [SurveyStore.instance]).
  final SurveyStore? store;

  /// WebView host builder override.
  final WebViewHostBuilder? webViewHostBuilder;

  /// External-URL launcher override.
  final LaunchUrlFn? launch;

  @override
  State<SurveyWebView> createState() => _SurveyWebViewState();
}

class _SurveyWebViewState extends State<SurveyWebView> {
  _SurveyPhase _phase = _SurveyPhase.idle;
  String _languageCode = 'default';
  Timer? _delayTimer;
  bool _routeOpen = false;
  bool _closing = false;
  NavigatorState? _navigator;
  RawDialogRoute<void>? _route;

  // Serializes config read-modify-writes so back-to-back events (e.g. response
  // then close) can't clobber each other.
  Future<void> _configOps = Future<void>.value();

  FormbricksConfig get _config => widget.config ?? FormbricksConfig.instance;
  SurveyStore get _store => widget.store ?? SurveyStore.instance;

  @override
  void initState() {
    super.initState();
    // All store mutations / route pushes happen post-frame, never during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted) return;
    final current = _config.getOrNull();
    if (current == null) {
      _reset();
      return;
    }
    _phase = _SurveyPhase.loading;

    if (widget.survey.isMultiLanguage) {
      final displayLanguage =
          getLanguageCode(widget.survey, current.user.data.language);
      if (displayLanguage == null) {
        Logger.debug(
          'Survey "${widget.survey.id}" is not available in specified language.',
        );
        _reset();
        return;
      }
      _languageCode = displayLanguage;
    }

    if (widget.survey.delay > 0) {
      Logger.debug(
        'Delaying survey "${widget.survey.id}" by ${widget.survey.delay} '
        'seconds',
      );
      _delayTimer = Timer(Duration(seconds: widget.survey.delay), () {
        if (mounted) _present();
      });
    } else {
      _present();
    }
  }

  void _present() {
    if (!mounted) return;
    if (_phase == _SurveyPhase.presenting || _phase == _SurveyPhase.closing) {
      return;
    }
    // A delayed present must not fire if the store has moved on to another
    // survey (or none) in the meantime.
    if (_store.survey?.id != widget.survey.id) return;

    final current = _config.getOrNull();
    if (current == null) {
      _reset();
      return;
    }

    final settings =
        current.workspace?.data.settings ?? const <String, dynamic>{};
    final appUrl = current.appUrl ?? '';
    final overwrites = widget.survey.projectOverwrites;
    final html = buildSurveyHtml(
      SurveyHtmlOptions(
        survey: widget.survey,
        appUrl: appUrl,
        workspaceId: current.workspaceId ?? '',
        isBrandingEnabled: settings['inAppSurveyBranding'] == true,
        languageCode: _languageCode,
        styling: getStyling(settings, widget.survey),
        contactId: current.user.data.contactId,
        placement: overwrites?.placement ?? _asString(settings['placement']),
        clickOutside: overwrites?.clickOutsideClose ??
            _asBool(settings['clickOutsideClose']),
        overlay: overwrites?.overlay ?? _asString(settings['overlay']),
      ),
    );

    _phase = _SurveyPhase.presenting;
    final builder = widget.webViewHostBuilder ?? defaultWebViewHost;
    _navigator = Navigator.of(context, rootNavigator: true);
    final route = RawDialogRoute<void>(
      barrierColor: const Color(0x00000000),
      barrierDismissible: false,
      barrierLabel: '',
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) => _modalContent(builder, html, appUrl),
    );
    _route = route;
    _routeOpen = true;
    _navigator!.push(route).then((_) {
      if (!mounted) return;
      _routeOpen = false;
      // Route dismissed without a bridge close (e.g. Android back): close now.
      if (!_closing) _closeSurvey(alreadyDismissed: true);
    });
  }

  Widget _modalContent(
    WebViewHostBuilder builder,
    String html,
    String appUrl,
  ) {
    // Builder so the keyboard inset is read in a context that rebuilds on
    // show/hide (RN's KeyboardAvoidingView equivalent).
    return Builder(
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: builder(
          ctx,
          html: html,
          appUrl: appUrl,
          onEvent: _onEvent,
          launch: widget.launch,
          onLoadError: _handleWebViewLoadError,
        ),
      ),
    );
  }

  void _onEvent(WebViewEvent event) {
    if (!mounted) return;
    switch (event) {
      case DisplayCreatedEvent():
        _enqueueConfigOp(_recordDisplay);
      case ResponseCreatedEvent():
        _enqueueConfigOp(_recordResponse);
      case OpenExternalUrlEvent(:final url):
        unawaited(openExternalUrl(url, launch: widget.launch));
      case CloseEvent():
        _closeSurvey();
      case ConsoleEvent(:final log):
        Logger.debug('[Console] $log');
    }
  }

  void _handleWebViewLoadError() {
    if (!mounted) return;
    Logger.error('Survey WebView failed to load. Closing survey.');
    _closeSurvey();
  }

  Future<void> _recordDisplay() async {
    final current = _config.getOrNull();
    if (current == null) return;
    final now = clock.now();
    final displays = [
      ...current.user.data.displays,
      TDisplay(surveyId: widget.survey.id, createdAt: now),
    ];
    await _config.update(
      current.copyWith(
        user: current.user.copyWith(
          data: current.user.data.copyWith(
            displays: displays,
            lastDisplayAt: now,
          ),
        ),
      ),
    );
  }

  Future<void> _recordResponse() async {
    final current = _config.getOrNull();
    if (current == null) return;
    final responses = [...current.user.data.responses, widget.survey.id];
    await _config.update(
      current.copyWith(
        user: current.user.copyWith(
          data: current.user.data.copyWith(responses: responses),
        ),
      ),
    );
  }

  void _closeSurvey({bool alreadyDismissed = false}) {
    if (_closing) return;
    _closing = true;
    _phase = _SurveyPhase.closing;

    if (!alreadyDismissed && _routeOpen && _route != null && _route!.isActive) {
      _navigator?.removeRoute(_route!);
    }
    _routeOpen = false;

    // Queue the close write after display/response updates so bridge events
    // cannot overtake each other.
    _enqueueConfigOp(() async {
      final current = _config.getOrNull();
      if (current != null) await _config.update(current);
    });

    _store.resetSurvey();
  }

  void _reset() => _store.resetSurvey();

  void _enqueueConfigOp(Future<void> Function() op) {
    _configOps = _configOps.then((_) => op()).catchError((Object e) {
      Logger.error('Error persisting survey state: $e');
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    // External store reset can unmount us without a close; remove the route
    // via the captured NavigatorState (no live BuildContext required). The
    // isActive guard makes removal idempotent if the route was already popped.
    if (_routeOpen && _route != null && _route!.isActive) {
      _navigator?.removeRoute(_route!);
    }
    _routeOpen = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

String? _asString(Object? value) => value is String ? value : null;
bool? _asBool(Object? value) => value is bool ? value : null;
