/// The survey WebView host.
///
/// The lifecycle is driven by a single state machine inside the `State`.
/// `build()` always returns a zero-size box; the survey is shown in a
/// transparent modal route held by this State so teardown paths never need a
/// deactivated `BuildContext`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../common/config.dart';
import '../common/filter_surveys.dart';
import '../common/logger.dart';
import '../common/utils.dart';
import '../survey/survey_store.dart';
import '../types/config.dart';
import '../types/survey.dart';
import '../user/interaction_refresh.dart';
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

  // Non-overlay (box-none) placements present in a barrier-less [OverlayEntry]
  // instead of a modal route, so touches outside the survey card reach the host
  // app. [_cardRect] is the card's bounding rect (WebView-local logical px)
  // reported over the bridge; pointers outside it fall through. Overlay/backdrop
  // placements keep the full-screen modal route (the backdrop *should* block).
  OverlayEntry? _overlayEntry;
  bool _hasOverlay = false;
  final ValueNotifier<Rect?> _cardRect = ValueNotifier<Rect?>(null);

  // Serializes config read-modify-writes so back-to-back events (e.g. response
  // then close) can't clobber each other.
  Future<void> _configOps = Future<void>.value();

  // Interaction sources already refreshed during this showing.
  final Set<InteractionSource> _refreshedSources = <InteractionSource>{};

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
    final overlay = overwrites?.overlay ?? _asString(settings['overlay']);
    // A backdrop ("dark"/"light") is a real modal: it should block the host. No
    // overlay (or "none") is a corner/inline card and must be box-none.
    _hasOverlay = overlay != null && overlay != 'none';
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
        overlay: overlay,
      ),
    );

    _phase = _SurveyPhase.presenting;
    final builder = widget.webViewHostBuilder ?? defaultWebViewHost;
    if (_hasOverlay) {
      _presentModalRoute(builder, html, appUrl);
    } else {
      _presentOverlayEntry(builder, html, appUrl);
    }
  }

  /// Overlay/backdrop placements: a full-screen modal route whose transparent
  /// barrier blocks the host (correct for a backdrop). The web runtime draws the
  /// dim and handles `clickOutside` via its own `onClose` bridge call.
  void _presentModalRoute(
    WebViewHostBuilder builder,
    String html,
    String appUrl,
  ) {
    _navigator = Navigator.of(context, rootNavigator: true);
    final route = RawDialogRoute<void>(
      barrierColor: const Color(0x00000000),
      barrierDismissible: false,
      barrierLabel: '',
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) => _surveyContent(builder, html, appUrl),
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

  /// Non-overlay placements: a barrier-less root [OverlayEntry]. Only the card
  /// rect ([_cardRect], reported over the bridge) hit-tests; everything outside
  /// falls through to the host app (box-none parity with RN).
  void _presentOverlayEntry(
    WebViewHostBuilder builder,
    String html,
    String appUrl,
  ) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => _surveyContent(builder, html, appUrl),
    );
    _overlayEntry = entry;
    overlay.insert(entry);
  }

  Widget _surveyContent(
    WebViewHostBuilder builder,
    String html,
    String appUrl,
  ) {
    // Builder so the keyboard inset is read in a context that rebuilds on
    // keyboard show/hide.
    return Builder(
      builder: (ctx) {
        final webView = Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: builder(
            ctx,
            html: html,
            appUrl: appUrl,
            onEvent: _onEvent,
            launch: widget.launch,
            onLoadError: _handleWebViewLoadError,
          ),
        );
        // Backdrop placements fill and block the screen. Non-overlay placements
        // only accept pointers within the reported card rect; the WebView paints
        // full-bleed (so shadows show) but rejects hits elsewhere. Passing the
        // WebView as `child` keeps its controller alive across geometry updates.
        if (_hasOverlay) return webView;
        return ValueListenableBuilder<Rect?>(
          valueListenable: _cardRect,
          builder: (_, rect, child) => _PointerMask(rect: rect, child: child!),
          child: webView,
        );
      },
    );
  }

  void _onEvent(WebViewEvent event) {
    if (!mounted) return;
    switch (event) {
      case DisplayCreatedEvent():
        _enqueueConfigOp(_recordDisplay);
        _refreshSegmentsOnce(InteractionSource.onDisplay);
      case ResponseCreatedEvent():
        _enqueueConfigOp(_recordResponse);
        _refreshSegmentsOnce(InteractionSource.onResponse);
      case FinishedEvent():
        _refreshSegmentsOnce(InteractionSource.onFinished);
      case OpenExternalUrlEvent(:final url):
        unawaited(openExternalUrl(url, launch: widget.launch));
      case CloseEvent():
        _closeSurvey();
      case GeometryEvent(:final rect):
        _cardRect.value = rect;
      case ConsoleEvent(:final log):
        Logger.debug('[Console] $log');
    }
  }

  /// Forwards an interaction to the segment refresh at most once per source.
  ///
  /// One `State` lives per survey showing, so this is scoped to that showing.
  /// The survey runtime guards `onResponseCreated` itself, but `onFinished` is
  /// not guarded there, and a self-hosted server may serve an older bundle — so
  /// the refresh is gated here too. Only the refresh is gated; the local
  /// displays/responses bookkeeping keeps its existing behaviour.
  void _refreshSegmentsOnce(InteractionSource source) {
    if (!_refreshedSources.add(source)) return;
    refreshSegmentsAfterInteraction(
      _config.getOrNull()?.user.data.userId,
      widget.survey,
      source,
    );
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
    final user = current.user.copyWith(
      data: current.user.data.copyWith(
        displays: displays,
        lastDisplayAt: now,
      ),
    );
    await _config.update(
      current.copyWith(user: user, filteredSurveys: _refilter(current, user)),
    );
  }

  Future<void> _recordResponse() async {
    final current = _config.getOrNull();
    if (current == null) return;
    final responses = [...current.user.data.responses, widget.survey.id];
    final user = current.user.copyWith(
      data: current.user.data.copyWith(responses: responses),
    );
    await _config.update(
      current.copyWith(user: user, filteredSurveys: _refilter(current, user)),
    );
  }

  /// Refilters the eligible set against the just-updated [user], so e.g. a
  /// shown `displayOnce` survey stops triggering immediately.
  List<dynamic> _refilter(TConfig config, TUserState user) {
    final workspace = config.workspace;
    if (workspace == null) return const [];
    return filterSurveys(workspace, user).map((s) => s.toJson()).toList();
  }

  void _closeSurvey({bool alreadyDismissed = false}) {
    if (_closing) return;
    _closing = true;
    _phase = _SurveyPhase.closing;

    _dismissPresentation(alreadyDismissed: alreadyDismissed);

    // Queue the close write after display/response updates so bridge events
    // cannot overtake each other. The close refilters too.
    _enqueueConfigOp(() async {
      final current = _config.getOrNull();
      if (current == null) return;
      await _config.update(
        current.copyWith(filteredSurveys: _refilter(current, current.user)),
      );
    });

    _store.resetSurvey();
  }

  /// Tears down whichever presentation is active (modal route or overlay
  /// entry). Idempotent: the active-route guard and null overlay entry make
  /// repeat calls (close then dispose) safe. [alreadyDismissed] skips the route
  /// removal when the route popped itself (e.g. Android back).
  void _dismissPresentation({bool alreadyDismissed = false}) {
    if (!alreadyDismissed && _routeOpen && _route != null && _route!.isActive) {
      _navigator?.removeRoute(_route!);
    }
    _routeOpen = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
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
    // External store reset can unmount us without a close; tear down the active
    // presentation via captured handles (no live BuildContext required). The
    // guards make removal idempotent if it was already dismissed.
    _dismissPresentation();
    _cardRect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

String? _asString(Object? value) => value is String ? value : null;
bool? _asBool(Object? value) => value is bool ? value : null;

/// A render box that paints its child normally but only forwards pointer hits
/// within [rect] (local logical px). Hits outside [rect] — or all hits when
/// [rect] is `null` — are rejected so they fall through to whatever is behind
/// (the host app). This is how the SDK achieves RN's `pointerEvents="box-none"`
/// for a full-bleed platform WebView, which otherwise hit-tests its whole area.
class _PointerMask extends SingleChildRenderObjectWidget {
  const _PointerMask({required this.rect, required super.child});

  final Rect? rect;

  @override
  _RenderPointerMask createRenderObject(BuildContext context) =>
      _RenderPointerMask(rect);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPointerMask renderObject,
  ) {
    renderObject.rect = rect;
  }
}

class _RenderPointerMask extends RenderProxyBox {
  _RenderPointerMask(this._rect);

  Rect? _rect;
  set rect(Rect? value) {
    if (value == _rect) return;
    _rect = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final rect = _rect;
    if (rect == null || !rect.contains(position)) return false;
    return super.hitTest(result, position: position);
  }
}
