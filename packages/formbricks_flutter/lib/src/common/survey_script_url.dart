/// Resolves the survey-runtime script URL, ported from the React Native SDK's
/// `components/utils/survey-script-url.ts`.
library;

/// Derives `{appUrl}/js/surveys.umd.cjs` from [appUrl].
///
/// Returns null when [appUrl] is null/empty, unparseable, hostless, or not an
/// `http(s)` URL — the WebView must never load the runtime from a non-http(s)
/// origin. Any existing path is preserved (so `https://x.com/foo` →
/// `https://x.com/foo/js/surveys.umd.cjs`); query and fragment are stripped.
String? getSurveyScriptUrl(String? appUrl) {
  if (appUrl == null || appUrl.isEmpty) return null;

  final uri = Uri.tryParse(appUrl);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;

  final basePath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';

  // Build a fresh Uri rather than `replace(query: '')` (which can leave a
  // trailing `?`); this drops query + fragment cleanly and keeps host/port.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '${basePath}js/surveys.umd.cjs',
  ).toString();
}
