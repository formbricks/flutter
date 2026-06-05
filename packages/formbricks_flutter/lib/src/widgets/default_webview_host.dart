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
});

/// The production [WebViewHostBuilder] backed by `webview_flutter`.
///
/// Security hardening (`docs/FLUTTER_SDK_PLAN.md` §6):
///   * JavaScript enabled per-controller only (this survey HTML).
///   * Same-origin top-level navigation; cross-origin main-frame nav opens in
///     the external browser via [openExternalUrl]; cross-origin sub-frame nav
///     is blocked in place.
///   * Android file/content access explicitly disabled (platform default is
///     `true` on API < 30).
///   * Cache + local storage cleared before each load so nothing persists
///     beyond the survey lifetime.
///   * No `baseUrl` (RN parity): the injected document gets an opaque origin and
///     is not granted the workspace's first-party storage/cookies.
Widget defaultWebViewHost(
  BuildContext context, {
  required String html,
  required String appUrl,
  required void Function(WebViewEvent event) onEvent,
  LaunchUrlFn? launch,
}) {
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(const Color(0x00000000))
    ..addJavaScriptChannel(
      'Formbricks',
      onMessageReceived: (JavaScriptMessage message) {
        for (final event in parseWebViewEvents(message.message)) {
          onEvent(event);
        }
      },
    )
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          switch (decideNavigation(
            request.url,
            appUrl,
            isMainFrame: request.isMainFrame,
          )) {
            case NavAction.allow:
              return NavigationDecision.navigate;
            case NavAction.openExternally:
              unawaited(openExternalUrl(request.url, launch: launch));
              return NavigationDecision.prevent;
            case NavAction.block:
              return NavigationDecision.prevent;
          }
        },
      ),
    );

  unawaited(_hardenAndLoad(controller, html));
  return WebViewWidget(controller: controller);
}

Future<void> _hardenAndLoad(WebViewController controller, String html) async {
  final platform = controller.platform;
  if (platform is AndroidWebViewController) {
    await platform.setAllowFileAccess(false);
    await platform.setAllowContentAccess(false);
  }
  await controller.clearCache();
  await controller.clearLocalStorage();
  await controller.loadHtmlString(html);
}
