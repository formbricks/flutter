import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/api_client.dart';
import 'package:formbricks/src/common/config.dart';
import 'package:formbricks/src/common/logger.dart';
import 'package:formbricks/src/user/attribute.dart';
import 'package:formbricks/src/user/update_queue.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stub API client so a debounced flush never performs real network I/O.
ApiClient _noopApi() => ApiClient(
      appUrl: 'https://app.formbricks.com',
      workspaceId: 'wsp_1',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'state': {'expiresAt': null, 'data': <String, dynamic>{}},
            },
          }),
          200,
        ),
      ),
    );

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
      'user': {
        'expiresAt': null,
        'data': {'userId': 'u1'},
      },
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormbricksConfig config;
  late UpdateQueue queue;

  setUp(() async {
    Logger.resetInstance();
    UpdateQueue.resetInstance();
    config = await _seed();
    queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = _noopApi();
  });

  tearDown(UpdateQueue.resetInstance);

  test('DateTime normalized to UTC ISO-8601 before queueing', () async {
    final date = DateTime.utc(2026, 6, 9, 10, 30);
    await setAttributes({'signupDate': date}, queue: queue);

    expect(queue.pendingAttributes!['signupDate'], date.toIso8601String());
    expect(queue.pendingAttributes!['signupDate'], isA<String>());
  });

  test('num preserved as number, String preserved', () async {
    await setAttributes({'mrr': 99, 'plan': 'pro'}, queue: queue);

    expect(queue.pendingAttributes!['mrr'], 99);
    expect(queue.pendingAttributes!['mrr'], isA<num>());
    expect(queue.pendingAttributes!['plan'], 'pro');
  });

  test('setLanguage delegates to setAttributes({language})', () async {
    await setLanguage('de', queue: queue);

    expect(queue.pendingAttributes!['language'], 'de');
  });
}
