// coverage:ignore-file
//
// Real `webview_flutter` controller wiring. Excluded from coverage because it
// instantiates a platform `WebViewController` (platform channels) that cannot
// run under `flutter test`; the decision logic it calls (parseWebViewEvents,
// decideNavigation, openExternalUrl) is unit-tested in isolation, and the
// widget state machine is tested with an injected stub host.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../common/logger.dart';
import 'webview_event.dart';
import 'webview_navigation.dart';

/// Builds the widget that hosts the survey WebView. Injectable so widget tests
/// can substitute a stub that never touches a platform channel.
typedef WebViewHostBuilder = Widget Function(
  BuildContext context, {
  required String html,
  required String appUrl,
  required void Function(WebViewEvent event) onEvent,
  LaunchUrlFn? launch,
  VoidCallback? onLoadError,
});

/// The production [WebViewHostBuilder] backed by `webview_flutter`.
///
/// Returns a [StatefulWidget] so the [WebViewController] is created once and
/// survives rebuilds of the surrounding modal (e.g. when the soft keyboard
/// changes `MediaQuery.viewInsets` and the keyboard-avoiding padding rebuilds).
/// Creating the controller per build would reload the survey on every keystroke
/// and make it appear to close.
Widget defaultWebViewHost(
  BuildContext context, {
  required String html,
  required String appUrl,
  required void Function(WebViewEvent event) onEvent,
  LaunchUrlFn? launch,
  VoidCallback? onLoadError,
}) {
  return _DefaultWebViewHost(
    html: html,
    appUrl: appUrl,
    onEvent: onEvent,
    launch: launch,
    onLoadError: onLoadError,
  );
}

class _DefaultWebViewHost extends StatefulWidget {
  const _DefaultWebViewHost({
    required this.html,
    required this.appUrl,
    required this.onEvent,
    this.launch,
    this.onLoadError,
  });

  final String html;
  final String appUrl;
  final void Function(WebViewEvent event) onEvent;
  final LaunchUrlFn? launch;
  final VoidCallback? onLoadError;

  @override
  State<_DefaultWebViewHost> createState() => _DefaultWebViewHostState();
}

class _DefaultWebViewHostState extends State<_DefaultWebViewHost> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    // Created once. Callbacks read widget.* so they always see current values.
    //
    // Security hardening:
    //   * JavaScript enabled per-controller only (this survey HTML).
    //   * Same-origin top-level navigation; cross-origin main-frame nav opens in
    //     the external browser via [openExternalUrl]; cross-origin sub-frame nav
    //     is blocked in place.
    //   * Android file/content access explicitly disabled (platform default is
    //     `true` on API < 30).
    //   * Cache + local storage cleared before load so nothing persists beyond
    //     the survey lifetime.
    //   * No `baseUrl`: the injected document gets an opaque origin and is not
    //     granted the workspace's first-party storage/cookies.
    // The Formbricks bridge only receives lifecycle JSON parsed by
    // parseWebViewEvents; navigation and external URL handling stay allowlisted.
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'Formbricks',
        onMessageReceived: (JavaScriptMessage message) {
          for (final event in parseWebViewEvents(message.message)) {
            widget.onEvent(event);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            switch (decideNavigation(
              request.url,
              widget.appUrl,
              isMainFrame: request.isMainFrame,
            )) {
              case NavAction.allow:
                return NavigationDecision.navigate;
              case NavAction.openExternally:
                unawaited(
                  openExternalUrl(request.url, launch: widget.launch),
                );
                return NavigationDecision.prevent;
              case NavAction.block:
                return NavigationDecision.prevent;
            }
          },
        ),
      );

    unawaited(
      _hardenAndLoad(
        _controller,
        widget.html,
        onError: widget.onLoadError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

Future<void> _hardenAndLoad(
  WebViewController controller,
  String html, {
  VoidCallback? onError,
}) async {
  try {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setAllowFileAccess(false);
      await platform.setAllowContentAccess(false);
    }
    await controller.clearCache();
    await controller.clearLocalStorage();
    await controller.loadHtmlString(html);
  } catch (e, stackTrace) {
    Logger.error('Failed to initialize survey WebView: $e\n$stackTrace');
    onError?.call();
  }
}
