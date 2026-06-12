import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/result.dart';

void main() {
  group('Result', () {
    test('Ok holds its value and reports isOk', () {
      const Result<int, String> result = Result.ok(5);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect((result as Ok<int, String>).value, 5);
    });

    test('Err holds its error and reports isErr', () {
      const Result<int, String> result = Result.err('boom');
      expect(result.isErr, isTrue);
      expect(result.isOk, isFalse);
      expect((result as Err<int, String>).error, 'boom');
    });

    test('can be matched exhaustively with a switch', () {
      String describe(Result<int, String> r) => switch (r) {
            Ok(:final value) => 'ok:$value',
            Err(:final error) => 'err:$error',
          };

      expect(describe(const Result.ok(1)), 'ok:1');
      expect(describe(const Result.err('x')), 'err:x');
    });
  });
}
