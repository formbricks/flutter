import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/api_client.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/logger.dart';
import 'package:formbricks_flutter/src/common/setup.dart' as setup;
import 'package:formbricks_flutter/src/types/errors.dart';
import 'package:formbricks_flutter/src/user/update_queue.dart';
import 'package:formbricks_flutter/src/widgets/formbricks_widget.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _configJson() => jsonEncode({
      'workspaceId': 'wsp_1',
      'appUrl': 'https://app.formbricks.com',
      'workspace': {
        'expiresAt': '2100-01-01T00:00:00.000',
        'data': {
          'surveys': <dynamic>[],
          'actionClasses': <dynamic>[],
          'settings': <String, dynamic>{},
        },
      },
      'user': {'expiresAt': null, 'data': <String, dynamic>{}},
      'status': {'value': 'success', 'expiresAt': null},
    });

Future<FormbricksConfig> _seed() async {
  SharedPreferences.setMockInitialValues({
    FormbricksConfig.storageKey: _configJson(),
  });
  FormbricksConfig.resetInstance();
  final config = FormbricksConfig.instance;
  await config.init();
  return config;
}

ApiClient _neverCalledApi(void Function() onCall) => ApiClient(
      appUrl: 'https://app.formbricks.com',
      workspaceId: 'wsp_1',
      client: MockClient((req) async {
        onCall();
        return http.Response('{}', 200);
      }),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Logger.resetInstance();
    UpdateQueue.resetInstance();
    setup.resetSetupForTest();
  });

  tearDown(() {
    UpdateQueue.resetInstance();
    setup.resetSetupForTest();
  });

  group('not set up', () {
    test('setUserId → NotSetupError, no API call', () async {
      var apiCalls = 0;
      final config = await _seed();
      UpdateQueue.instance
        ..configOverride = config
        ..apiClientOverride = _neverCalledApi(() => apiCalls++);
      setup.setIsSetup(value: false);

      await expectLater(
        Formbricks.setUserId('u1'),
        throwsA(isA<NotSetupError>()),
      );
      expect(UpdateQueue.instance.isEmpty, isTrue);
      expect(apiCalls, 0);
    });

    test('setAttribute / setLanguage / logout all throw NotSetupError',
        () async {
      setup.setIsSetup(value: false);

      await expectLater(
        Formbricks.setAttribute('plan', 'pro'),
        throwsA(isA<NotSetupError>()),
      );
      await expectLater(
        Formbricks.setLanguage('de'),
        throwsA(isA<NotSetupError>()),
      );
      await expectLater(
        Formbricks.logout(),
        throwsA(isA<NotSetupError>()),
      );
    });
  });

  group('set up', () {
    test('setUserId then setAttributes route through the queue in order',
        () async {
      final config = await _seed();
      UpdateQueue.instance
        ..configOverride = config
        ..apiClientOverride = _neverCalledApi(() {});
      setup.setIsSetup(value: true);

      final r1 = await Formbricks.setUserId('u1');
      final r2 = await Formbricks.setAttributes({'plan': 'pro'});

      expect(r1.isOk, isTrue);
      expect(r2.isOk, isTrue);
      // setUserId ran first, so the attribute write resolved against userId u1.
      expect(UpdateQueue.instance.pendingUserId, 'u1');
      expect(UpdateQueue.instance.pendingAttributes!['plan'], 'pro');
    });

    test('setAttribute queues a single key', () async {
      final config = await _seed();
      UpdateQueue.instance
        ..configOverride = config
        ..apiClientOverride = _neverCalledApi(() {});
      setup.setIsSetup(value: true);

      final result = await Formbricks.setAttribute('mrr', 99);

      expect(result.isOk, isTrue);
      expect(UpdateQueue.instance.pendingAttributes!['mrr'], 99);
    });
  });
}
