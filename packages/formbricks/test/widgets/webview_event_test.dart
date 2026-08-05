import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/widgets/webview_event.dart';

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

    test('a multi-flag payload fires multiple events in declaration order', () {
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
      expect(parseWebViewEvents('{}'), isEmpty);
      expect(parseWebViewEvents('{"onFinished":false}'), isEmpty);
    });

    test('onFinished maps to a FinishedEvent', () {
      expect(
        parseWebViewEvents('{"onFinished":true}'),
        [isA<FinishedEvent>()],
      );
    });

    test('finished is emitted after response, in handler order', () {
      expect(
        parseWebViewEvents(
          '{"onResponseCreated":true,"onFinished":true,"onClose":true}',
        ),
        [
          isA<ResponseCreatedEvent>(),
          isA<FinishedEvent>(),
          isA<CloseEvent>(),
        ],
      );
    });

    test('file-pick payload is ignored by the Flutter bridge', () {
      final events = parseWebViewEvents('{"onFilePick":"handled-by-runtime"}');

      expect(events, isEmpty);
    });

    test('geometry carries the card rect', () {
      final event = parseWebViewEvents(
        '{"type":"Geometry","data":{"x":1.5,"y":2,"width":300,"height":120}}',
      ).single;
      expect(event, isA<GeometryEvent>());
      final rect = (event as GeometryEvent).rect!;
      expect(rect.left, 1.5);
      expect(rect.top, 2);
      expect(rect.width, 300);
      expect(rect.height, 120);
    });

    test('geometry with null data → GeometryEvent(null) (card not laid out)',
        () {
      final event =
          parseWebViewEvents('{"type":"Geometry","data":null}').single;
      expect(event, isA<GeometryEvent>());
      expect((event as GeometryEvent).rect, isNull);
    });

    test('geometry missing data → GeometryEvent(null)', () {
      final event = parseWebViewEvents('{"type":"Geometry"}').single;
      expect((event as GeometryEvent).rect, isNull);
    });

    test('geometry with a malformed field → empty (dropped)', () {
      expect(
        parseWebViewEvents(
          '{"type":"Geometry","data":{"x":"nope","y":2,"width":3,"height":4}}',
        ),
        isEmpty,
      );
    });
  });
}
