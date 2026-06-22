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

      function getSetIsResponseSendingFinished() { /* noop */ };
      function getSetIsError() { /* noop */ };

      // Reports the survey card's bounding rect (CSS px, viewport-relative) to
      // the host so it can pass touches outside the card through to the app
      // (box-none). The native WebView hit-tests its whole rectangle and ignores
      // the page's `pointer-events:none`, so the host masks pointers itself and
      // needs the card geometry to know where the card is.
      var fbLastGeometry = '';
      var fbGeometryRaf = null;
      var fbGeometryStable = 0;
      function fbCardRect() {
        // The survey card is the single modal dialog the runtime renders inside
        // its #fbjs container (survey-container.tsx). Scoped + both attributes
        // so we never grab the full-screen #fbjs wrapper (that would defeat
        // box-none) or a future nested dialog. querySelector returns the
        // outermost match in document order, i.e. the card itself.
        var el = document.querySelector('#fbjs [role="dialog"][aria-modal="true"]');
        if (!el) return null;
        var r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) return null;
        return { x: r.left, y: r.top, width: r.width, height: r.height };
      }
      function fbGeometryTick() {
        var rect = fbCardRect();
        var key = rect
          ? [Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height)].join(',')
          : 'null';
        if (key !== fbLastGeometry) {
          fbLastGeometry = key;
          fbGeometryStable = 0;
          postFormbricksMessage({ type: 'Geometry', data: rect });
        } else {
          fbGeometryStable++;
        }
        // Idle once the rect has been stable for ~1.5s (open/step animations
        // settle); observers below restart the loop on any later change.
        if (fbGeometryStable > 90) { fbGeometryRaf = null; return; }
        fbGeometryRaf = window.requestAnimationFrame(fbGeometryTick);
      }
      function fbEnsureGeometryLoop() {
        if (fbGeometryRaf == null) {
          fbGeometryStable = 0;
          fbGeometryRaf = window.requestAnimationFrame(fbGeometryTick);
        }
      }
      function fbObserveGeometry() {
        try {
          var mo = new MutationObserver(fbEnsureGeometryLoop);
          mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
        } catch (e) {}
        window.addEventListener('resize', fbEnsureGeometryLoop);
        window.addEventListener('orientationchange', fbEnsureGeometryLoop);
      }

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
            onClose,
            getSetIsResponseSendingFinished,
            getSetIsError,
          };

          const runtime = window.formbricksSurveys;
          if (!runtime || typeof runtime.renderSurvey !== 'function') {
            closeOnError('Formbricks Surveys library is unavailable.');
            return;
          }
          runtime.renderSurvey(surveyProps);
          fbObserveGeometry();
          fbEnsureGeometryLoop();
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
