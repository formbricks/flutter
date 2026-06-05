import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/widgets/webview_event.dart';

void main() {
  group('parseWebViewEvents', () {
    test('display-created', () {
      expect(
        parseWebViewEvents('{"onDisplayCreated":true}').single,
        isA<DisplayCreatedEvent>(),
      );
    });

    test('response-created', () {
      expect(
        parseWebViewEvents('{"onResponseCreated":true}').single,
        isA<ResponseCreatedEvent>(),
      );
    });

    test('close', () {
      expect(parseWebViewEvents('{"onClose":true}').single, isA<CloseEvent>());
    });

    test('open-external-url carries the url', () {
      final event = parseWebViewEvents(
        '{"onOpenExternalURL":true,"onOpenExternalURLParams":{"url":"https://x.com"}}',
      ).single;
      expect(event, isA<OpenExternalUrlEvent>());
      expect((event as OpenExternalUrlEvent).url, 'https://x.com');
    });

    test('console', () {
      final event = parseWebViewEvents(
        '{"type":"Console","data":{"type":"log","log":"hello"}}',
      ).single;
      expect(event, isA<ConsoleEvent>());
      expect((event as ConsoleEvent).log, contains('hello'));
    });

    test('a multi-flag payload fires multiple events in RN order', () {
      final events =
          parseWebViewEvents('{"onResponseCreated":true,"onClose":true}');
      expect(events.length, 2);
      expect(events[0], isA<ResponseCreatedEvent>());
      expect(events[1], isA<CloseEvent>());
    });

    test('malformed JSON → empty (not thrown)', () {
      expect(parseWebViewEvents('{not json'), isEmpty);
    });

    test('non-object JSON → empty', () {
      expect(parseWebViewEvents('"just a string"'), isEmpty);
    });

    test('wrong-typed flag → empty', () {
      expect(parseWebViewEvents('{"onClose":"yes"}'), isEmpty);
    });

    test('open-external-url missing url → empty', () {
      expect(parseWebViewEvents('{"onOpenExternalURL":true}'), isEmpty);
    });

    test('well-formed but non-actionable payload → empty (quiet)', () {
      expect(parseWebViewEvents('{"onFinished":true}'), isEmpty);
    });
  });
}
