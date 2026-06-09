/// Typed model for messages the survey runtime posts back to Dart.
///
/// A posted payload can carry several lifecycle flags, so the parser returns a
/// list of events in handler order instead of collapsing to one.
library;

import 'dart:convert';

import '../common/logger.dart';

const String _parseErrorMessage = 'Error parsing message from WebView.';
const String _consoleType = 'Console';

/// Base type for messages bridged from the survey WebView.
sealed class WebViewEvent {
  const WebViewEvent();
}

/// The runtime created a display (the survey was shown).
final class DisplayCreatedEvent extends WebViewEvent {
  /// Creates a display-created event.
  const DisplayCreatedEvent();
}

/// The runtime recorded a response.
final class ResponseCreatedEvent extends WebViewEvent {
  /// Creates a response-created event.
  const ResponseCreatedEvent();
}

/// The runtime asked to close the survey.
final class CloseEvent extends WebViewEvent {
  /// Creates a close event.
  const CloseEvent();
}

/// The runtime asked to open an external URL.
final class OpenExternalUrlEvent extends WebViewEvent {
  /// Creates an open-external-URL event for [url].
  const OpenExternalUrlEvent(this.url);

  /// The URL to open externally.
  final String url;
}

/// A `console.*` line forwarded from the WebView (dev-only logging).
final class ConsoleEvent extends WebViewEvent {
  /// Creates a console event carrying [log].
  const ConsoleEvent(this.log);

  /// The serialized console payload.
  final String log;
}

/// Parses one JS-to-Dart payload into zero or more [WebViewEvent]s.
///
/// - Malformed input (not JSON / not an object / a flag with a non-bool value /
///   a non-object `onOpenExternalURLParams` / an external-URL event missing a
///   string `url`) is logged and dropped, never thrown.
/// - A `Console` payload maps to a single [ConsoleEvent] (mutually exclusive,
///   like the runtime handler).
/// - Otherwise one event is emitted per truthy flag, in handler order
///   (display, response, open-external-url, close). A well-formed but
///   non-actionable payload (e.g. `{onFinished:true}`) yields `const []`
///   quietly.
List<WebViewEvent> parseWebViewEvents(String raw) {
  final map = _decodeMessage(raw);
  if (map == null) return const [];

  // Dev-only console bridge (mutually exclusive with lifecycle events).
  final consoleEvent = _consoleEvent(map);
  if (consoleEvent != null) return [consoleEvent];

  if (!_hasValidShape(map)) return const [];

  final events = <WebViewEvent>[];
  if (map['onDisplayCreated'] == true) events.add(const DisplayCreatedEvent());
  if (map['onResponseCreated'] == true) {
    events.add(const ResponseCreatedEvent());
  }
  if (map['onOpenExternalURL'] == true) {
    events.add(OpenExternalUrlEvent(_externalUrl(map)!));
  }
  if (map['onClose'] == true) events.add(const CloseEvent());
  return events;
}

Map<String, dynamic>? _decodeMessage(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    _logParseError();
    return null;
  }
  if (decoded is! Map) {
    _logParseError();
    return null;
  }
  return decoded.cast<String, dynamic>();
}

ConsoleEvent? _consoleEvent(Map<String, dynamic> map) {
  if (map['type'] != _consoleType) return null;
  final data = map['data'];
  return ConsoleEvent(data is Map ? jsonEncode(data) : '${data ?? ''}');
}

bool _hasValidShape(Map<String, dynamic> map) {
  const boolFlags = [
    'onClose',
    'onDisplayCreated',
    'onResponseCreated',
    'onOpenExternalURL',
    'onFinished',
  ];
  for (final key in boolFlags) {
    final value = map[key];
    if (value != null && value is! bool) {
      _logParseError();
      return false;
    }
  }
  final params = map['onOpenExternalURLParams'];
  if (params != null && params is! Map) {
    _logParseError();
    return false;
  }
  if (map['onOpenExternalURL'] == true && _externalUrl(map) == null) {
    _logParseError();
    return false;
  }
  return true;
}

String? _externalUrl(Map<String, dynamic> map) {
  final params = map['onOpenExternalURLParams'];
  final url = params is Map ? params['url'] : null;
  return url is String ? url : null;
}

void _logParseError() => Logger.error(_parseErrorMessage);
