/// Typed model for messages the survey runtime posts back to Dart.
///
/// A posted payload can carry several lifecycle flags, so the parser returns a
/// list of events in handler order instead of collapsing to one.
library;

import 'dart:convert';
import 'dart:ui' show Rect;

import '../common/logger.dart';

const String _parseErrorMessage = 'Error parsing message from WebView.';
const String _consoleType = 'Console';
const String _geometryType = 'Geometry';

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

/// The survey was completed and the finished response was accepted by the
/// backend (the runtime gates this on `isResponseSendingFinished`).
final class FinishedEvent extends WebViewEvent {
  /// Creates a finished event.
  const FinishedEvent();
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

/// The runtime reported the survey card's bounding rectangle (CSS pixels,
/// relative to the WebView's top-left), so the host can let touches outside the
/// card fall through to the app (box-none). [rect] is `null` when no card is
/// currently laid out (e.g. before render), meaning "nothing is interactive".
final class GeometryEvent extends WebViewEvent {
  /// Creates a geometry event carrying the card [rect] (or `null`).
  const GeometryEvent(this.rect);

  /// The card's bounding rect in WebView-local logical pixels, or `null`.
  final Rect? rect;
}

/// Parses one JS-to-Dart payload into zero or more [WebViewEvent]s.
///
/// - Malformed input (not JSON / not an object / a flag with a non-bool value /
///   a non-object `onOpenExternalURLParams` / an external-URL event missing a
///   string `url`) is logged and dropped, never thrown.
/// - A `Console` payload maps to a single [ConsoleEvent] (mutually exclusive,
///   like the runtime handler).
/// - Otherwise one event is emitted per truthy flag, in handler order
///   (display, response, finished, open-external-url, close). A well-formed but
///   non-actionable payload (e.g. `{}`) yields `const []` quietly.
List<WebViewEvent> parseWebViewEvents(String raw) {
  final map = _decodeMessage(raw);
  if (map == null) return const [];

  // Dev-only console bridge (mutually exclusive with lifecycle events).
  final consoleEvent = _consoleEvent(map);
  if (consoleEvent != null) return [consoleEvent];

  // Card geometry bridge (mutually exclusive with lifecycle events).
  if (map['type'] == _geometryType) {
    final geometryEvent = _geometryEvent(map);
    return geometryEvent != null ? [geometryEvent] : const [];
  }

  if (!_hasValidShape(map)) return const [];

  final events = <WebViewEvent>[];
  if (map['onDisplayCreated'] == true) events.add(const DisplayCreatedEvent());
  if (map['onResponseCreated'] == true) {
    events.add(const ResponseCreatedEvent());
  }
  if (map['onFinished'] == true) events.add(const FinishedEvent());
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

/// Parses a `{type:'Geometry', data:{x,y,width,height}|null}` payload.
///
/// A `null`/absent `data` means the card is not laid out and maps to
/// `GeometryEvent(null)`. A present-but-malformed `data` is logged and dropped.
GeometryEvent? _geometryEvent(Map<String, dynamic> map) {
  final data = map['data'];
  if (data == null) return const GeometryEvent(null);
  if (data is! Map) {
    _logParseError();
    return null;
  }
  final x = _toDouble(data['x']);
  final y = _toDouble(data['y']);
  final width = _toDouble(data['width']);
  final height = _toDouble(data['height']);
  if (x == null || y == null || width == null || height == null) {
    _logParseError();
    return null;
  }
  return GeometryEvent(Rect.fromLTWH(x, y, width, height));
}

double? _toDouble(Object? value) => value is num ? value.toDouble() : null;

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
