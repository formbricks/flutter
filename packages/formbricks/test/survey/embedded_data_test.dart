import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/formbricks.dart';
import 'package:formbricks/src/common/logger.dart';
import 'package:formbricks/src/survey/embedded_data.dart';

/// Captures the lines `Logger` writes while [body] runs. `Logger` routes through
/// `debugPrint`, which `flutter_test` lets us swap for the duration of a test.
List<String> _captureLogs(void Function() body) {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    body();
  } finally {
    debugPrint = original;
  }
  return lines;
}

/// The Embedded Data bag (ENG-1844 / ENG-2472): host-supplied context attached
/// to future responses without tying it to a trigger. These pin the contract all
/// four SDKs share, so a divergence here is a divergence from the JS SDK too.
void main() {
  final store = EmbeddedDataStore.instance;

  setUp(() {
    Logger.resetInstance();
    store.clear();
  });

  tearDown(store.clear);

  group('merge semantics', () {
    test('merges instead of replacing: setting one key keeps the others', () {
      Formbricks.setEmbeddedData({'plan': 'pro', 'screen': 'product'});
      Formbricks.setEmbeddedData({'screen': 'checkout'});

      expect(store.snapshot(), {'plan': 'pro', 'screen': 'checkout'});
    });

    test('null drops the key', () {
      Formbricks.setEmbeddedData({'plan': 'pro', 'screen': 'product'});
      Formbricks.setEmbeddedData({'screen': null});

      expect(store.snapshot(), {'plan': 'pro'});
    });

    test('last write wins per key', () {
      Formbricks.setEmbeddedData({'plan': 'free'});
      Formbricks.setEmbeddedData({'plan': 'pro'});

      expect(store.snapshot(), {'plan': 'pro'});
    });

    test('omitted keys are untouched', () {
      // Dart has no `undefined`, so "skip this field" is spelled by leaving the
      // key out — and that must not disturb what an earlier call set. `null` is
      // the explicit "remove" spelling.
      Formbricks.setEmbeddedData({'plan': 'pro'});
      Formbricks.setEmbeddedData({'seats': 4});

      expect(store.snapshot(), {'plan': 'pro', 'seats': 4});
    });
  });

  group('clearing', () {
    test('clearEmbeddedData(key) removes one key', () {
      Formbricks.setEmbeddedData({'plan': 'pro', 'screen': 'product'});

      Formbricks.clearEmbeddedData('screen');

      expect(store.snapshot(), {'plan': 'pro'});
    });

    test('clearing an unset key is a no-op', () {
      Formbricks.setEmbeddedData({'plan': 'pro'});

      Formbricks.clearEmbeddedData('neverSet');

      expect(store.snapshot(), {'plan': 'pro'});
    });

    test('clearEmbeddedData() with no argument removes everything', () {
      Formbricks.setEmbeddedData({'plan': 'pro', 'screen': 'product'});

      Formbricks.clearEmbeddedData();

      expect(store.snapshot(), isEmpty);
    });

    test('clearEmbeddedData(null) is a no-op, NOT a full clear', () {
      // One keystroke from the no-argument form and the opposite behaviour. A
      // host reading the key from its own state must not wipe the whole bag
      // when that state is empty — the sentinel default is what keeps the two
      // apart, the same distinction the JS SDK draws by argument count.
      Formbricks.setEmbeddedData({'plan': 'pro', 'screen': 'product'});

      Formbricks.clearEmbeddedData(null);

      expect(store.snapshot(), {'plan': 'pro', 'screen': 'product'});
    });

    test('clearEmbeddedData with a non-string key is a no-op', () {
      Formbricks.setEmbeddedData({'plan': 'pro'});

      Formbricks.clearEmbeddedData(42);

      expect(store.snapshot(), {'plan': 'pro'});
    });
  });

  group('value types', () {
    test('every scalar survives, with DateTime as ISO 8601', () {
      final signedUpAt = DateTime.utc(2026, 8, 20, 10);

      Formbricks.setEmbeddedData({
        'plan': 'pro',
        'seats': 25,
        'score': 9.5,
        'isTrial': false,
        'signedUpAt': signedUpAt,
      });

      expect(store.snapshot(), {
        'plan': 'pro',
        'seats': 25,
        'score': 9.5,
        'isTrial': false,
        // ISO 8601 is what the renderer's ingest contract accepts for a `date`.
        'signedUpAt': '2026-08-20T10:00:00.000Z',
      });
    });

    test('a local DateTime is normalized to UTC, not left ambiguous', () {
      final local = DateTime.utc(2026, 8, 20, 10).toLocal();

      Formbricks.setEmbeddedData({'signedUpAt': local});

      expect(store.snapshot()['signedUpAt'], '2026-08-20T10:00:00.000Z');
    });

    test('a snapshot is always JSON-encodable', () {
      // The snapshot is embedded in the survey WebView's render options. If
      // jsonEncode ever threw, the failure would not be a missing field — it
      // would be no survey at all.
      Formbricks.setEmbeddedData({
        'plan': 'pro',
        'seats': 25,
        'isTrial': true,
        'signedUpAt': DateTime.now(),
      });

      expect(() => jsonEncode(store.snapshot()), returnsNormally);
    });

    test('a non-finite number is skipped rather than costing the survey', () {
      // THE guard: jsonEncode throws on NaN/Infinity, and the payload it would
      // refuse is the whole survey's render options.
      Formbricks.setEmbeddedData({'plan': 'pro'});

      Formbricks.setEmbeddedData({
        'broken': double.nan,
        'alsoBroken': double.infinity,
      });

      expect(store.snapshot(), {'plan': 'pro'});
      expect(() => jsonEncode(store.snapshot()), returnsNormally);
    });

    test('an unsupported value type is skipped, never thrown', () {
      Formbricks.setEmbeddedData({'plan': 'pro'});

      expect(
        () => Formbricks.setEmbeddedData({
          'items': ['a', 'b'],
          'nested': {'a': 1},
        }),
        returnsNormally,
      );
      expect(store.snapshot(), {'plan': 'pro'});
    });
  });

  group('lifetime', () {
    test('snapshot is detached: later writes do not reach an earlier one', () {
      // What "a value set after a survey is displayed does not change that
      // response" rests on — the render options hold this map for the life of
      // the survey.
      Formbricks.setEmbeddedData({'plan': 'pro'});
      final snapshot = store.snapshot();

      Formbricks.setEmbeddedData({'plan': 'enterprise', 'extra': 'later'});

      expect(snapshot, {'plan': 'pro'});
    });

    test('works before setup', () {
      // Deliberately unlike the queued methods: a host that pushes context at
      // launch must not have the value dropped because setup had not finished.
      Formbricks.setEmbeddedData({'plan': 'pro'});

      expect(store.snapshot(), {'plan': 'pro'});
    });
  });

  group('the debug success trace — the bag\'s only success feedback', () {
    setUp(() => Logger.configure(level: LogLevel.debug));

    test('a successful set logs the keys — keys only, never values', () {
      final lines = _captureLogs(
        () => Formbricks.setEmbeddedData({
          'plan': 'pro',
          'hashed_email': 's3cret-hash',
        }),
      );

      expect(lines, hasLength(1));
      expect(lines.single, contains('set [plan, hashed_email]'));
      expect(lines.single, contains('the bag now holds [plan, hashed_email]'));
      // The bag's documented use includes hashed identity fields; a value must
      // never reach a log line.
      expect(lines.single, isNot(contains('pro')));
      expect(lines.single, isNot(contains('s3cret-hash')));
    });

    test('a null removal shows up as removed, not set', () {
      Formbricks.setEmbeddedData({'plan': 'pro'});

      final lines = _captureLogs(
        () => Formbricks.setEmbeddedData({'plan': null, 'screen': 'checkout'}),
      );

      expect(lines.single, contains('set [screen]'));
      expect(lines.single, contains('removed [plan]'));
      expect(lines.single, contains('the bag now holds [screen]'));
    });

    test('a skipped value appears in neither list', () {
      final lines = _captureLogs(
        () => Formbricks.setEmbeddedData({'plan': 'pro', 'x': double.nan}),
      );

      // The refusal logs its own error line; the trace is the second.
      expect(lines, hasLength(2));
      expect(lines.last, contains('set [plan]'));
      expect(lines.last, isNot(contains('[plan, x]')));
    });

    test('clearEmbeddedData traces both forms', () {
      Formbricks.setEmbeddedData({'plan': 'pro', 'screen': 'product'});

      final removedLines =
          _captureLogs(() => Formbricks.clearEmbeddedData('plan'));
      expect(removedLines.single, contains('removed "plan"'));
      expect(removedLines.single, contains('the bag now holds [screen]'));

      final clearedLines = _captureLogs(Formbricks.clearEmbeddedData);
      expect(clearedLines.single, contains('cleared the whole bag (1 keys)'));
    });

    test('the trace is silent at the default error level', () {
      Logger.resetInstance();

      final lines = _captureLogs(
        () => Formbricks.setEmbeddedData({'plan': 'pro'}),
      );

      expect(lines, isEmpty);
    });
  });

  group('the clear-everything sentinel', () {
    test('an outside const Object() cannot forge it', () {
      // Dart canonicalizes const instances, so a `const Object()` sentinel would
      // be identical to every `const Object()` in the program and this call
      // would wipe the bag. The sentinel is a const instance of a private class
      // instead, which host code cannot name.
      Formbricks.setEmbeddedData({'plan': 'pro', 'screen': 'product'});

      Formbricks.clearEmbeddedData(const Object());

      expect(store.snapshot(), {'plan': 'pro', 'screen': 'product'});
    });

    test('a non-const Object() cannot forge it either', () {
      Formbricks.setEmbeddedData({'plan': 'pro'});

      Formbricks.clearEmbeddedData(Object());

      expect(store.snapshot(), {'plan': 'pro'});
    });
  });
}
