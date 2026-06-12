import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/command_queue.dart';
import 'package:formbricks/src/types/errors.dart';

void main() {
  group('CommandQueue', () {
    test('runs parallel adds in submission order', () async {
      final queue = CommandQueue(isSetup: () => true);
      final order = <int>[];

      // First command has the longest delay; FIFO must still run it first.
      final f1 = queue.add(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add(1);
      });
      final f2 = queue.add(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add(2);
      });
      final f3 = queue.add(() async => order.add(3));

      await Future.wait([f1, f2, f3]);
      expect(order, [1, 2, 3]);
    });

    test(
      'completes with NotSetupError and never runs the body when not set up',
      () async {
        final queue = CommandQueue(isSetup: () => false);
        var ran = false;

        final future = queue.add(() => ran = true);

        await expectLater(future, throwsA(isA<NotSetupError>()));
        expect(ran, isFalse);
      },
    );

    test('a throwing command does not stop the next command', () async {
      final queue = CommandQueue(isSetup: () => true);
      var secondRan = false;

      final failing = queue.add(() => throw const FormatException('bad'));
      final next = queue.add(() => secondRan = true);

      await expectLater(failing, throwsA(isA<FormatException>()));
      await next;
      expect(secondRan, isTrue);
    });

    test(
      'surfaces the original error on the throwing command future',
      () async {
        final queue = CommandQueue(isSetup: () => true);
        final future = queue.add(() => throw StateError('original'));
        await expectLater(
          future,
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'original'),
          ),
        );
      },
    );

    test('runs when checkSetup is false even if not set up', () async {
      final queue = CommandQueue(isSetup: () => false);
      final result = await queue.add(() => 42, checkSetup: false);
      expect(result, 42);
    });

    test('returns the typed command result', () async {
      final queue = CommandQueue(isSetup: () => true);
      final value = await queue.add<String>(() async => 'hi');
      expect(value, 'hi');
    });
  });
}
