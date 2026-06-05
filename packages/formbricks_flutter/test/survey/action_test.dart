import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/logger.dart';
import 'package:formbricks_flutter/src/common/result.dart';
import 'package:formbricks_flutter/src/survey/action.dart';
import 'package:formbricks_flutter/src/survey/survey_store.dart';
import 'package:formbricks_flutter/src/types/errors.dart';
import 'package:formbricks_flutter/src/types/survey.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _surveyJson(String id, List<String> actionNames) => {
      'id': id,
      'triggers': [
        for (final name in actionNames)
          {
            'actionClass': {'name': name},
          },
      ],
      'languages': <dynamic>[],
    };

String _configJson({
  List<Map<String, dynamic>> surveys = const [],
  List<Map<String, dynamic>> actionClasses = const [],
  String appUrl = 'https://app.formbricks.com',
}) =>
    jsonEncode({
      'workspaceId': 'wsp_1',
      'appUrl': appUrl,
      'workspace': {
        'expiresAt': '2100-01-01T00:00:00.000',
        'data': {
          'surveys': surveys,
          'actionClasses': actionClasses,
          'settings': <String, dynamic>{},
        },
      },
      'user': {'expiresAt': null, 'data': <String, dynamic>{}},
      'status': {'value': 'success', 'expiresAt': null},
    });

Future<FormbricksConfig> _seed(String json) async {
  SharedPreferences.setMockInitialValues({FormbricksConfig.storageKey: json});
  FormbricksConfig.resetInstance();
  final config = FormbricksConfig.instance;
  await config.init();
  return config;
}

E _errOf<T, E>(Result<T, E> result) => switch (result) {
      Ok() => fail('expected Err'),
      Err(:final error) => error,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Logger.resetInstance();
    SurveyStore.resetInstance();
  });

  group('track', () {
    test('unknown code → invalid_code, no survey set', () async {
      final config = await _seed(
        _configJson(
          actionClasses: [
            {'id': 'a', 'name': 'A', 'type': 'code', 'key': 'known'},
          ],
        ),
      );
      final result =
          await track('unknown', config: config, isConnected: () async => true);
      final error = _errOf(result);
      expect(error, isA<InvalidCodeError>());
      expect(error.code, FormbricksErrorCode.invalidCode);
      expect(SurveyStore.instance.survey, isNull);
    });

    test('offline → network_error with url + message, no survey set', () async {
      final config = await _seed(
        _configJson(
          actionClasses: [
            {'id': 'a', 'name': 'A', 'type': 'code', 'key': 'k'},
          ],
        ),
      );
      final result =
          await track('k', config: config, isConnected: () async => false);
      final error = _errOf(result) as NetworkError;
      expect(error.code, FormbricksErrorCode.networkError);
      expect(error.status, 500);
      expect(
        error.url.toString(),
        'https://app.formbricks.com/js/surveys.umd.cjs',
      );
      expect(error.message, contains('No internet connection'));
      expect(SurveyStore.instance.survey, isNull);
    });

    test('a throwing connectivity check is treated as offline', () async {
      final config = await _seed(
        _configJson(
          actionClasses: [
            {'id': 'a', 'name': 'A', 'type': 'code', 'key': 'k'},
          ],
        ),
      );
      final result = await track(
        'k',
        config: config,
        isConnected: () async => throw Exception('boom'),
      );
      expect(_errOf(result), isA<NetworkError>());
      expect(SurveyStore.instance.survey, isNull);
    });

    test('valid code + matching survey → ok, survey set', () async {
      final config = await _seed(
        _configJson(
          actionClasses: [
            {'id': 'a', 'name': 'ActName', 'type': 'code', 'key': 'mycode'},
          ],
          surveys: [
            _surveyJson('s1', ['ActName']),
          ],
        ),
      );
      final result =
          await track('mycode', config: config, isConnected: () async => true);
      expect(result.isOk, isTrue);
      expect(SurveyStore.instance.survey?.id, 's1');
    });

    test('valid code but no matching survey → ok, no survey set', () async {
      final config = await _seed(
        _configJson(
          actionClasses: [
            {'id': 'a', 'name': 'ActName', 'type': 'code', 'key': 'mycode'},
          ],
          surveys: [
            _surveyJson('s1', ['OtherAction']),
          ],
        ),
      );
      final result =
          await track('mycode', config: config, isConnected: () async => true);
      expect(result.isOk, isTrue);
      expect(SurveyStore.instance.survey, isNull);
    });

    test('only code-type action classes are matched', () async {
      final config = await _seed(
        _configJson(
          actionClasses: [
            {'id': 'a', 'name': 'A', 'type': 'noCode', 'key': 'mycode'},
          ],
        ),
      );
      final result =
          await track('mycode', config: config, isConnected: () async => true);
      expect(_errOf(result), isA<InvalidCodeError>());
    });

    test('a malformed action class is skipped; valid ones still match',
        () async {
      final config = await _seed(
        _configJson(
          actionClasses: [
            {'type': 'code', 'name': null},
            {'id': 'a', 'name': 'Good', 'type': 'code', 'key': 'good'},
          ],
        ),
      );
      final result =
          await track('good', config: config, isConnected: () async => true);
      expect(result.isOk, isTrue);
    });

    test('an unexpected internal error → generic network_error', () async {
      // An uninitialized config makes `get()` throw, exercising the outer catch.
      FormbricksConfig.resetInstance();
      final result = await track(
        'x',
        config: FormbricksConfig.instance,
        isConnected: () async => true,
      );
      final error = _errOf(result) as NetworkError;
      expect(error.message, 'Error tracking action');
    });
  });

  group('trackAction', () {
    test('matches across multiple triggers and surveys (last match wins)',
        () async {
      final config = await _seed(
        _configJson(
          surveys: [
            _surveyJson('s1', ['X', 'Target']),
            _surveyJson('s2', ['Target']),
          ],
        ),
      );
      final result = await trackAction('Target', config: config);
      expect(result.isOk, isTrue);
      expect(SurveyStore.instance.survey?.id, 's2');
    });

    test('no surveys → ok, logs, no survey set', () async {
      final config = await _seed(_configJson(surveys: const []));
      final result = await trackAction('Whatever', config: config);
      expect(result.isOk, isTrue);
      expect(SurveyStore.instance.survey, isNull);
    });

    test('a malformed survey entry is skipped; valid ones still match',
        () async {
      final json = jsonEncode({
        'workspaceId': 'wsp_1',
        'appUrl': 'https://app.formbricks.com',
        'workspace': {
          'expiresAt': '2100-01-01T00:00:00.000',
          'data': {
            'surveys': [
              {'noId': true, 'triggers': <dynamic>[]},
              _surveyJson('good', ['Target']),
            ],
            'actionClasses': <dynamic>[],
            'settings': <String, dynamic>{},
          },
        },
        'user': {'expiresAt': null, 'data': <String, dynamic>{}},
        'status': {'value': 'success', 'expiresAt': null},
      });
      final config = await _seed(json);
      final result = await trackAction('Target', config: config);
      expect(result.isOk, isTrue);
      expect(SurveyStore.instance.survey?.id, 'good');
    });
  });

  group('triggerSurvey', () {
    test('sets the survey without a percentage gate', () {
      triggerSurvey(TSurvey.fromJson({'id': 'x'}));
      expect(SurveyStore.instance.survey?.id, 'x');
    });
  });
}
