/// WebView navigation and external-URL policy.
///
/// Only same-origin URLs load inside the WebView; cross-origin top-level
/// navigations open in the external browser; only `http`/`https` schemes are
/// ever launched (blocks
/// `javascript:`/`file:`/`data:`/`intent:`).
library;

import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../common/logger.dart';

/// Signature for launching an external URL.
typedef LaunchUrlFn = Future<bool> Function(Uri url, {LaunchMode mode});

/// What to do with a navigation request.
enum NavAction {
  /// Load it inside the WebView.
  allow,

  /// Block it in-WebView and open it in the external browser.
  openExternally,

  /// Block it in-WebView without launching anything.
  block,
}

/// Whether [candidateUrl] may load inside the WebView given [appUrl].
///
/// `about:blank` (the injected HTML's base document) is always allowed; any
/// other URL must share [appUrl]'s origin.
bool isAllowedWebViewNavigation(String candidateUrl, String appUrl) {
  if (candidateUrl == 'about:blank') return true;
  final candidate = Uri.tryParse(candidateUrl);
  final allowed = Uri.tryParse(appUrl);
  if (candidate == null || allowed == null) return false;
  return _origin(candidate) == _origin(allowed);
}

int? _nonDefaultPort(Uri uri) {
  if (!uri.hasPort) return null;
  final port = uri.port;
  if ((uri.scheme == 'http' && port == 80) ||
      (uri.scheme == 'https' && port == 443)) {
    return null;
  }
  return port;
}

String _origin(Uri uri) {
  final port = _nonDefaultPort(uri);
  return '${uri.scheme}://${uri.host}${port == null ? '' : ':$port'}';
}

/// Decides what to do with a navigation request.
///
/// Same-origin requests are allowed. Cross-origin requests open externally only
/// for main-frame navigations; cross-origin sub-frame requests are blocked
/// in-place ([NavAction.block]) rather than
/// ejecting the user to a browser (iOS fires the delegate for sub-frames;
/// Android does not).
NavAction decideNavigation(
  String url,
  String appUrl, {
  required bool isMainFrame,
}) {
  if (isAllowedWebViewNavigation(url, appUrl)) return NavAction.allow;
  return isMainFrame ? NavAction.openExternally : NavAction.block;
}

/// Opens [candidateUrl] in the external browser, enforcing the scheme
/// allow-list (`http`/`https` only).
Future<void> openExternalUrl(
  String candidateUrl, {
  LaunchUrlFn? launch,
}) async {
  final uri = Uri.tryParse(candidateUrl);
  if (uri == null) {
    Logger.error('Failed to open external URL: invalid URL');
    return;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    Logger.error('Blocked unsupported external URL protocol: ${uri.scheme}:');
    return;
  }
  try {
    await (launch ?? _defaultLaunch)(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    Logger.error('Failed to open external URL: $e');
  }
}

// Wrap launchUrl so the arity matches LaunchUrlFn exactly.
Future<bool> _defaultLaunch(
  Uri url, {
  LaunchMode mode = LaunchMode.platformDefault,
}) =>
    url_launcher.launchUrl(url, mode: mode);
