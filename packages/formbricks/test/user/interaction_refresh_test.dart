import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/types/survey.dart';
import 'package:formbricks/src/user/interaction_refresh.dart';
import 'package:formbricks/src/user/update_queue.dart';

TSurvey _survey({
  TInteractionRefresh? interactionRefresh,
  String id = 'survey-a',
}) =>
    TSurvey(
      id: id,
      triggers: const [],
      languages: const [],
      delay: 0,
      interactionRefresh: interactionRefresh,
      raw: {'id': id},
    );

void main() {
  group('refreshSegmentsAfterInteraction', () {
    // The real queue is used so the production call path is exercised. Its
    // `pendingUserId` reports whether `updateUserId` was reached; the debounced
    // flush is cancelled in tearDown so no timer outlives the test.
    setUp(UpdateQueue.resetInstance);
    tearDown(UpdateQueue.resetInstance);

    test('no-ops for an anonymous user even when the gate is open', () {
      refreshSegmentsAfterInteraction(
        null,
        _survey(
          interactionRefresh: const TInteractionRefresh(
            onDisplay: true,
            onResponse: true,
            onFinished: true,
          ),
        ),
        InteractionSource.onDisplay,
      );

      expect(UpdateQueue.instance.isEmpty, isTrue);
    });

    test('no-ops for an empty user id', () {
      refreshSegmentsAfterInteraction(
        '',
        _survey(
          interactionRefresh: const TInteractionRefresh(onDisplay: true),
        ),
        InteractionSource.onDisplay,
      );

      expect(UpdateQueue.instance.isEmpty, isTrue);
    });

    test('no-ops when the gate is absent — no interaction targeting', () {
      refreshSegmentsAfterInteraction(
        'user-1',
        _survey(),
        InteractionSource.onDisplay,
      );

      expect(UpdateQueue.instance.isEmpty, isTrue);
    });

    test('no-ops when every flag is false', () {
      refreshSegmentsAfterInteraction(
        'user-1',
        _survey(interactionRefresh: const TInteractionRefresh()),
        InteractionSource.onDisplay,
      );

      expect(UpdateQueue.instance.isEmpty, isTrue);
    });

    test('no-ops when only a different source is flagged', () {
      refreshSegmentsAfterInteraction(
        'user-1',
        _survey(
          interactionRefresh: const TInteractionRefresh(onDisplay: true),
        ),
        InteractionSource.onResponse,
      );

      expect(UpdateQueue.instance.isEmpty, isTrue);
    });

    test('refreshes when the matching flag is set', () {
      for (final (source, gate) in [
        (
          InteractionSource.onDisplay,
          const TInteractionRefresh(onDisplay: true)
        ),
        (
          InteractionSource.onResponse,
          const TInteractionRefresh(onResponse: true)
        ),
        (
          InteractionSource.onFinished,
          const TInteractionRefresh(onFinished: true)
        ),
      ]) {
        UpdateQueue.resetInstance();
        refreshSegmentsAfterInteraction(
          'user-1',
          _survey(interactionRefresh: gate),
          source,
        );

        expect(UpdateQueue.instance.pendingUserId, 'user-1', reason: '$source');
      }
    });

    /// The flush is fire-and-forget, so an error on the returned future would otherwise
    /// surface as an unhandled async error and, in a test zone, fail the test.
    test('a failing flush does not escape as an unhandled async error',
        () async {
      final failures = <Object>[];

      await runZonedGuarded(
        () async {
          refreshSegmentsAfterInteraction(
            'user-1',
            _survey(
              interactionRefresh: const TInteractionRefresh(onDisplay: true),
            ),
            InteractionSource.onDisplay,
          );

          // Force the queued flush to fail: no appUrl/workspaceId is configured, so
          // `_flush` throws once the debounce elapses.
          await Future<void>.delayed(
            UpdateQueue.debounceDelay + const Duration(milliseconds: 100),
          );
        },
        (error, _) => failures.add(error),
      );

      expect(failures, isEmpty);
    });

    test('routes through the queue so a burst can coalesce', () {
      final survey = _survey(
        interactionRefresh: const TInteractionRefresh(
          onDisplay: true,
          onResponse: true,
          onFinished: true,
        ),
      );

      for (final source in InteractionSource.values) {
        refreshSegmentsAfterInteraction('user-1', survey, source);
      }

      // All three land in one pending batch; the queue's own 500 ms debounce is
      // what collapses them into a single request (covered by
      // update_queue_test.dart).
      expect(UpdateQueue.instance.pendingUserId, 'user-1');
    });
  });

  group('TInteractionRefresh.fromJson', () {
    test('reads all three flags', () {
      final gate = TInteractionRefresh.fromJson(const {
        'onDisplay': true,
        'onResponse': false,
        'onFinished': true,
      });

      expect(gate.shouldRefresh(InteractionSource.onDisplay), isTrue);
      expect(gate.shouldRefresh(InteractionSource.onResponse), isFalse);
      expect(gate.shouldRefresh(InteractionSource.onFinished), isTrue);
    });

    test('treats missing flags as false rather than failing', () {
      final gate = TInteractionRefresh.fromJson(const {'onDisplay': true});

      expect(gate.onDisplay, isTrue);
      expect(gate.onResponse, isFalse);
      expect(gate.onFinished, isFalse);
    });

    test('treats non-boolean flags as false', () {
      final gate = TInteractionRefresh.fromJson(const {
        'onDisplay': 'yes',
        'onResponse': 1,
        'onFinished': null,
      });

      expect(gate.onDisplay, isFalse);
      expect(gate.onResponse, isFalse);
      expect(gate.onFinished, isFalse);
    });

    test('ignores unknown keys', () {
      final gate = TInteractionRefresh.fromJson(const {
        'onDisplay': true,
        'onSomethingNew': true,
      });

      expect(gate.onDisplay, isTrue);
    });
  });

  group('TSurvey.interactionRefresh', () {
    test('is null when the workspace has no interaction targeting', () {
      expect(TSurvey.fromJson(const {'id': 'a'}).interactionRefresh, isNull);
    });

    test('is parsed when present', () {
      final survey = TSurvey.fromJson(const {
        'id': 'a',
        'interactionRefresh': {'onFinished': true},
      });

      expect(survey.interactionRefresh, isNotNull);
      expect(
        survey.interactionRefresh!.shouldRefresh(InteractionSource.onFinished),
        isTrue,
      );
    });

    /// Present-but-all-false is a real payload: the backend attaches it to every
    /// survey in an interaction-targeting workspace.
    test('all-false is present but never refreshes', () {
      final survey = TSurvey.fromJson(const {
        'id': 'a',
        'interactionRefresh': {
          'onDisplay': false,
          'onResponse': false,
          'onFinished': false,
        },
      });

      expect(survey.interactionRefresh, isNotNull);
      for (final source in InteractionSource.values) {
        expect(survey.interactionRefresh!.shouldRefresh(source), isFalse);
      }
    });

    test('a non-object value is ignored rather than throwing', () {
      expect(
        TSurvey.fromJson(const {'id': 'a', 'interactionRefresh': 'nope'})
            .interactionRefresh,
        isNull,
      );
    });

    /// The whole survey map is re-serialized into the WebView payload, so the
    /// gate has to survive the round trip for the runtime to see it.
    test('survives the raw round trip into the runtime payload', () {
      const json = {
        'id': 'a',
        'interactionRefresh': {'onDisplay': true},
      };

      expect(TSurvey.fromJson(json).toJson()['interactionRefresh'], {
        'onDisplay': true,
      });
    });
  });
}
