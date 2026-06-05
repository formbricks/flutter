/// Builds the survey WebView HTML.
///
/// The runtime contract is `window.formbricksSurveys.renderSurvey({...})`. The
/// Flutter-specific additions are:
///   * a `window.ReactNativeWebView` shim that forwards `postMessage` to the
///     `Formbricks` JavaScript channel, and
///   * a `window.open` override that routes pop-ups through `onOpenExternalURL`
///     (Android enables multi-window by default with no public API to disable
///     it, and `window.open` bypasses the navigation delegate).
library;

import 'dart:convert';

import '../common/survey_script_url.dart';
import '../types/survey.dart';

/// Inputs for [buildSurveyHtml], resolved by the widget from config + survey.
class SurveyHtmlOptions {
  /// Creates render options.
  const SurveyHtmlOptions({
    required this.survey,
    required this.appUrl,
    required this.workspaceId,
    required this.isBrandingEnabled,
    required this.languageCode,
    this.styling,
    this.contactId,
    this.placement,
    this.clickOutside,
    this.overlay,
  });

  /// The survey to render.
  final TSurvey survey;

  /// The workspace app URL.
  final String appUrl;

  /// The workspace id.
  final String workspaceId;

  /// Whether in-app survey branding is shown.
  final bool isBrandingEnabled;

  /// The resolved language code (`'default'` or a specific code).
  final String languageCode;

  /// The resolved styling map, or null to omit the key.
  final Map<String, dynamic>? styling;

  /// The contact id, when known.
  final String? contactId;

  /// Survey placement, when set.
  final String? placement;

  /// Whether tapping outside closes the survey, when set.
  final bool? clickOutside;

  /// Overlay mode, when set.
  final String? overlay;

  /// The `renderSurvey` options object.
  Map<String, dynamic> toRenderOptions() => {
        'workspaceId': workspaceId,
        if (contactId != null) 'contactId': contactId,
        'survey': survey.toJson(),
        'isBrandingEnabled': isBrandingEnabled,
        if (styling != null) 'styling': styling,
        'languageCode': languageCode,
        if (placement != null) 'placement': placement,
        'appUrl': appUrl,
        if (clickOutside != null) 'clickOutside': clickOutside,
        if (overlay != null) 'overlay': overlay,
        'isWebEnvironment': false,
      };
}

/// Builds the full HTML document that loads `surveys.umd.cjs` and renders the
/// survey. Returns an empty doc when the script URL can't be resolved.
String buildSurveyHtml(SurveyHtmlOptions options) {
  final scriptUrl = getSurveyScriptUrl(options.appUrl);
  if (scriptUrl == null) return _emptyHtml;

  final optionsJson = scriptSafeJson(jsonEncode(options.toRenderOptions()));
  final scriptUrlJson = scriptSafeJson(jsonEncode(scriptUrl));

  return '''
  <!doctype html>
  <html>
    <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0">
    <head>
      <title>Formbricks WebView Survey</title>
    </head>
    <body style="overflow: hidden; height: 100vh; margin: 0;">
    </body>

    <script type="text/javascript">
    window.ReactNativeWebView = { postMessage: function (m) { Formbricks.postMessage(m); } };
    window.open = function (u) { try { window.ReactNativeWebView.postMessage(JSON.stringify({ onOpenExternalURL: true, onOpenExternalURLParams: { url: String(u) } })); } catch (e) {} return null; };
    const consoleLog = (type, log) => window.ReactNativeWebView.postMessage(JSON.stringify({'type': 'Console', 'data': {'type': type, 'log': log}}));
    console = {
        log: (log) => consoleLog('log', log),
        debug: (log) => consoleLog('debug', log),
        info: (log) => consoleLog('info', log),
        warn: (log) => consoleLog('warn', log),
        error: (log) => consoleLog('error', log),
      };

      function onClose() {
        window.ReactNativeWebView.postMessage(JSON.stringify({ onClose: true }));
      };

      function onDisplayCreated() {
        window.ReactNativeWebView.postMessage(JSON.stringify({ onDisplayCreated: true }));
      };

      function onResponseCreated() {
        window.ReactNativeWebView.postMessage(JSON.stringify({ onResponseCreated: true }));
      };

      function getSetIsResponseSendingFinished() { /* noop */ };
      function getSetIsError() { /* noop */ };

      function loadSurvey() {
        const options = $optionsJson;
        const surveyProps = {
          ...options,
          onDisplayCreated,
          onResponseCreated,
          onClose,
          getSetIsResponseSendingFinished,
          getSetIsError,
        };

        window.formbricksSurveys.renderSurvey(surveyProps);
      }

      const script = document.createElement("script");
      script.src = $scriptUrlJson;
      script.async = true;
      script.onload = () => loadSurvey();
      script.onerror = (error) => {
        console.error("Failed to load Formbricks Surveys library:", error);
      };

      document.head.appendChild(script);
    </script>
  </html>
  ''';
}

// JS unicode-escape prefix: a backslash (0x5C) followed by 'u'. Built from a
// char code so the literal "backslash-u" sequence never appears in source.
final String _u = '${String.fromCharCode(0x5c)}u';

/// Escapes a JSON string for safe inlining inside a `<script>` element.
///
/// Dart's `jsonEncode` does not escape `</script>` or the JS line separators
/// (U+2028 / U+2029), so a survey field containing the literal `</script>`
/// would terminate the inline script early and allow markup/JS injection. Each
/// replacement emits a JS unicode escape that the engine decodes back to the
/// original character inside the JSON string literal.
///
/// Exposed so tests can assert the neutralization.
String scriptSafeJson(String json) => json
    .replaceAll('<', '${_u}003c')
    .replaceAll('>', '${_u}003e')
    .replaceAll(String.fromCharCode(0x2028), '${_u}2028')
    .replaceAll(String.fromCharCode(0x2029), '${_u}2029');

const String _emptyHtml = '''
  <!doctype html>
  <html>
    <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0">
    <head>
      <title>Formbricks WebView Survey</title>
    </head>
    <body style="overflow: hidden; height: 100vh; margin: 0;">
    </body>
  </html>
  ''';
