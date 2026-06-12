import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/api_client.dart';
import 'package:formbricks/src/common/config.dart';
import 'package:formbricks/src/common/logger.dart';
import 'package:formbricks/src/user/update_queue.dart';
import 'package:formbricks/src/user/user.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stub API client so the debounced flush never performs real network I/O.
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

String _configJson({
  String? userId,
  List<Map<String, dynamic>> surveys = const [],
  List<Map<String, dynamic>> filteredSurveys = const [],
}) =>
    jsonEncode({
      'workspaceId': 'wsp_1',
      'appUrl': 'https://app.formbricks.com',
      'workspace': {
        'expiresAt': '2100-01-01T00:00:00.000',
        'data': {
          'surveys': surveys,
          'actionClasses': <dynamic>[],
          'settings': <String, dynamic>{},
        },
      },
      'user': {
        'expiresAt': null,
        'data': {
          'userId': userId,
          'segments': ['seg_1'],
        },
      },
      'filteredSurveys': filteredSurveys,
      'status': {'value': 'success', 'expiresAt': null},
    });

Future<FormbricksConfig> _seed({
  String? userId,
  List<Map<String, dynamic>> surveys = const [],
  List<Map<String, dynamic>> filteredSurveys = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    FormbricksConfig.storageKey: _configJson(
      userId: userId,
      surveys: surveys,
      filteredSurveys: filteredSurveys,
    ),
  });
  FormbricksConfig.resetInstance();
  final config = FormbricksConfig.instance;
  await config.init();
  return config;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Logger.resetInstance();
    UpdateQueue.resetInstance();
  });

  tearDown(UpdateQueue.resetInstance);

  group('setUserId', () {
    test('same value → Ok no-op, nothing queued, state untouched', () async {
      final config = await _seed(userId: 'u1');
      final queue = UpdateQueue.instance..configOverride = config;

      final result = await setUserId('u1', config: config, queue: queue);

      expect(result.isOk, isTrue);
      expect(queue.isEmpty, isTrue);
      expect(config.get().user.data.userId, 'u1');
      // No teardown ran, so segments survive.
      expect(config.get().user.data.segments, ['seg_1']);
    });

    test('different value when one set → tearDown then queue new id', () async {
      final config = await _seed(userId: 'old');
      final queue = UpdateQueue.instance
        ..configOverride = config
        ..apiClientOverride = _noopApi();

      final result = await setUserId('new', config: config, queue: queue);

      expect(result.isOk, isTrue);
      // tearDown reset user state to anonymous (userId null, segments cleared).
      expect(config.get().user.data.userId, isNull);
      expect(config.get().user.data.segments, isEmpty);
      // New id queued for the next flush.
      expect(queue.pendingUserId, 'new');
    });

    test('from anonymous → no tearDown, id queued', () async {
      final config = await _seed();
      final queue = UpdateQueue.instance
        ..configOverride = config
        ..apiClientOverride = _noopApi();

      final result = await setUserId('u1', config: config, queue: queue);

      expect(result.isOk, isTrue);
      expect(queue.pendingUserId, 'u1');
    });
  });

  group('logout', () {
    test('resets user state to anonymous and persists', () async {
      final config = await _seed(userId: 'u1');

      final result = await logout(config: config);

      expect(result.isOk, isTrue);
      expect(config.get().user.data.userId, isNull);
      expect(config.get().user.data.segments, isEmpty);

      // Persisted to disk: a fresh load sees the reset.
      final raw = (await SharedPreferences.getInstance()).getString(
        FormbricksConfig.storageKey,
      );
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect((decoded['user'] as Map)['data']['userId'], isNull);
    });

    test('refilters surveys against the anonymous user', () async {
      final gated = {
        'id': 'gated',
        'displayOption': 'respondMultiple',
        'triggers': <dynamic>[],
        'languages': <dynamic>[],
        'segment': {'id': 'seg_1', 'hasFilters': true},
      };
      final plain = {
        'id': 'plain',
        'displayOption': 'respondMultiple',
        'triggers': <dynamic>[],
        'languages': <dynamic>[],
      };
      final config = await _seed(
        userId: 'u1',
        surveys: [gated, plain],
        filteredSurveys: [gated],
      );

      final result = await logout(config: config);

      expect(result.isOk, isTrue);
      expect(
        config.get().filteredSurveys.map((e) => (e as Map)['id']).toList(),
        ['plain'],
        reason: 'segment-filtered surveys drop after logout',
      );
    });
  });
}
