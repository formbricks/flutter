/// Builds the survey WebView HTML.
///
/// The runtime contract is `window.formbricksSurveys.renderSurvey({...})`. The
/// Flutter-specific additions are:
///   * a `postFormbricksMessage` helper that forwards lifecycle payloads to the
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
    this.hiddenFieldsRecord = const <String, Object>{},
    this.appearance = 'light',
    this.customCss,
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

  /// The Embedded Data bag, snapshotted when the survey is displayed and frozen
  /// for its life. Passed raw and unfiltered: the ingest contract (allow-list,
  /// coercion, `locked`, size caps) lives in the renderer, so all four mobile
  /// SDKs inherit the same rules without each shipping a copy, and the server
  /// re-runs all of it on ingest.
  final Map<String, Object> hiddenFieldsRecord;

  /// What the survey opens with: `'light'` or `'dark'`. It is part of the page,
  /// so a later change goes through `runJavaScript` instead of loading again,
  /// which would lose the respondent's answers.
  final String appearance;

  /// The compiled `{workspace?, survey?}` custom CSS, or null to omit the key.
  final Map<String, Map<String, String>>? customCss;

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
        'hiddenFieldsRecord': hiddenFieldsRecord,
        'appearance': appearance,
        if (customCss != null) 'customCss': customCss,
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
      function postFormbricksMessage(payload) {
        try {
          Formbricks.postMessage(JSON.stringify(payload));
        } catch (e) {}
      }
      window.open = function (u) { postFormbricksMessage({ onOpenExternalURL: true, onOpenExternalURLParams: { url: String(u) } }); return null; };
      const stringifyLog = (value) => {
        if (value instanceof Error) return value.message;
        if (typeof value === 'object') {
          try {
            return JSON.stringify(value);
          } catch (e) {
            return String(value);
          }
        }
        return String(value);
      };
      const consoleLog = (type, logs) => postFormbricksMessage({'type': 'Console', 'data': {'type': type, 'log': logs.map(stringifyLog).join(' ')}});
      console = {
        log: (...logs) => consoleLog('log', logs),
        debug: (...logs) => consoleLog('debug', logs),
        info: (...logs) => consoleLog('info', logs),
        warn: (...logs) => consoleLog('warn', logs),
        error: (...logs) => consoleLog('error', logs),
      };

      function onClose() {
        postFormbricksMessage({ onClose: true });
      };

      function onDisplayCreated() {
        postFormbricksMessage({ onDisplayCreated: true });
      };

      function onResponseCreated() {
        postFormbricksMessage({ onResponseCreated: true });
      };

      // Fires once the finished response has been accepted by the backend — the
      // runtime gates this on isResponseSendingFinished, and passing
      // getSetIsResponseSendingFinished below flips that initial state to false.
      function onFinished() {
        postFormbricksMessage({ onFinished: true });
      };

      function getSetIsResponseSendingFinished() { /* noop */ };
      function getSetIsError() { /* noop */ };

      // Where the survey card is, so the host can pass pointers outside it through
      // to the app. The renderer measures and calls this (ENG-3155); `rect` is
      // null when no card is on screen.
      //
      // This used to be scraped out of the DOM here. A correct a11y fix upstream
      // moved the attribute that probe matched on, the rect went null forever and
      // the card became untappable — with nothing to catch it, because a selector
      // in a string has no compile step and the renderer is fetched at runtime.
      //
      // Only a renderer from Formbricks 6.0+ calls this. Against an older
      // self-hosted server it never fires, and the mask stays at
      // SurveyTouchRegion.everything — exactly how the SDK behaved before.
      function onCardRectChange(rect) {
        postFormbricksMessage({ type: 'Geometry', data: rect });
      };

      let closedForError = false;
      function closeOnError(message, error) {
        if (closedForError) return;
        closedForError = true;
        console.error(message, error || '');
        postFormbricksMessage({ onClose: true });
      }

      function loadSurvey() {
        try {
          const options = $optionsJson;
          const surveyProps = {
            ...options,
            onDisplayCreated,
            onResponseCreated,
            onFinished,
            onClose,
            onCardRectChange,
            getSetIsResponseSendingFinished,
            getSetIsError,
          };

          const runtime = window.formbricksSurveys;
          if (!runtime || typeof runtime.renderSurvey !== 'function') {
            closeOnError('Formbricks Surveys library is unavailable.');
            return;
          }
          runtime.renderSurvey(surveyProps);
          postFormbricksMessage({ onSurveyRendered: true });
        } catch (error) {
          closeOnError('Failed to render Formbricks survey:', error);
        }
      }

      const script = document.createElement("script");
      script.src = $scriptUrlJson;
      script.async = true;
      const scriptLoadTimeout = window.setTimeout(
        () => closeOnError('Timed out loading Formbricks Surveys library.'),
        15000,
      );
      script.onload = () => {
        window.clearTimeout(scriptLoadTimeout);
        if (!closedForError) loadSurvey();
      };
      script.onerror = (error) => {
        window.clearTimeout(scriptLoadTimeout);
        closeOnError('Failed to load Formbricks Surveys library:', error);
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
