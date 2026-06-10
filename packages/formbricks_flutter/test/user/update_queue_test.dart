import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/api_client.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/logger.dart';
import 'package:formbricks_flutter/src/types/errors.dart';
import 'package:formbricks_flutter/src/user/update_queue.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appUrl = 'https://app.formbricks.com';
const _workspaceId = 'wsp_1';

String _configJson({
  String? userId,
  String? language,
  bool omitWorkspaceId = false,
}) =>
    jsonEncode({
      'workspaceId': omitWorkspaceId ? null : _workspaceId,
      'appUrl': _appUrl,
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
        'data': {
          'userId': userId,
          if (language != null) 'language': language,
        },
      },
      'status': {'value': 'success', 'expiresAt': null},
    });

Future<FormbricksConfig> _seed({
  String? userId,
  String? language,
  bool omitWorkspaceId = false,
}) async {
  SharedPreferences.setMockInitialValues({
    FormbricksConfig.storageKey: _configJson(
      userId: userId,
      language: language,
      omitWorkspaceId: omitWorkspaceId,
    ),
  });
  FormbricksConfig.resetInstance();
  final config = FormbricksConfig.instance;
  await config.init();
  return config;
}

/// A user-state response body that echoes [userId].
String _userResponse(String userId, {List<String>? errors}) => jsonEncode({
      'data': {
        'state': {
          'expiresAt': null,
          'data': {
            'userId': userId,
            'contactId': 'c1',
            'segments': <dynamic>[],
            'displays': <dynamic>[],
            'responses': <dynamic>[],
            'lastDisplayAt': null,
          },
        },
        if (errors != null) 'errors': errors,
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Logger.resetInstance();
    UpdateQueue.resetInstance();
  });

  tearDown(UpdateQueue.resetInstance);

  test('coalesces rapid updates into one createOrUpdateUser call', () async {
    final config = await _seed();
    final requests = <http.Request>[];
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        requests.add(req);
        return http.Response(_userResponse('u1'), 200);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateUserId('u1')
        ..processUpdates();
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates();
      queue
        ..updateAttributes({'mrr': 99})
        ..processUpdates();

      async.elapse(const Duration(milliseconds: 500));

      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['userId'], 'u1');
      expect(body['attributes'], {'plan': 'pro', 'mrr': 99});
    });
  });

  test('flush fires 500ms after the last call, not the first', () async {
    final config = await _seed();
    var calls = 0;
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        calls++;
        return http.Response(_userResponse('u1'), 200);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateUserId('u1')
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 400));
      expect(calls, 0);

      // A second call within the window resets the debounce.
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 400));
      expect(calls, 0, reason: 'only 400ms since the last call');

      async.elapse(const Duration(milliseconds: 100));
      expect(calls, 1, reason: '500ms since the last call');
    });
  });

  test('later attribute keys overwrite earlier ones', () async {
    final config = await _seed();
    late http.Request request;
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        request = req;
        return http.Response(_userResponse('u1'), 200);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateUserId('u1')
        ..updateAttributes({'plan': 'free'})
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 500));

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect((body['attributes'] as Map)['plan'], 'pro');
    });
  });

  test('userId falls back to config when not in pending updates', () async {
    final config = await _seed(userId: 'u_cfg');
    late http.Request request;
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        request = req;
        return http.Response(_userResponse('u_cfg'), 200);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 500));

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['userId'], 'u_cfg');
    });
  });

  test('language without a userId updates local config, no API call', () async {
    final config = await _seed();
    var calls = 0;
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        calls++;
        return http.Response(_userResponse('x'), 200);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateAttributes({'language': 'de'})
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 500));

      expect(calls, 0);
      expect(config.get().user.data.language, 'de');
      expect(queue.isEmpty, isTrue);
    });
  });

  test(
      'attributes without a userId → MissingFieldError, buffer cleared, no API',
      () async {
    final config = await _seed();
    var calls = 0;
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        calls++;
        return http.Response(_userResponse('x'), 200);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      Object? caught;
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates().catchError((Object e) => caught = e);
      async.elapse(const Duration(milliseconds: 500));

      expect(caught, isA<MissingFieldError>());
      expect(calls, 0);
      expect(queue.isEmpty, isTrue);
    });
  });

  test('API error → no retry, batch dropped, config user unchanged', () async {
    final config = await _seed(userId: 'u1');
    final before = config.get().user.data.contactId;
    var calls = 0;
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        calls++;
        return http.Response('{"message":"boom"}', 500);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 1500));

      expect(calls, 1, reason: 'no retry');
      expect(queue.isEmpty, isTrue);
      expect(config.get().user.data.contactId, before, reason: 'state intact');
    });
  });

  test('buffer is cleared even when _sendUpdates throws (no retry)', () async {
    // A null workspaceId makes _sendUpdates throw on `cfg.workspaceId!` before
    // any network call — the finally must still drop the batch.
    final config = await _seed(userId: 'u1', omitWorkspaceId: true);
    final queue = UpdateQueue.instance..configOverride = config;

    fakeAsync((async) {
      Object? caught;
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates().catchError((Object e) => caught = e);
      async.elapse(const Duration(milliseconds: 500));

      expect(caught, isNotNull, reason: 'the throw propagates to the caller');
      expect(queue.isEmpty, isTrue, reason: 'batch dropped, not retained');
    });
  });

  test('response warnings suppress success log but persist state', () async {
    final config = await _seed(userId: 'u1');
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        return http.Response(
          _userResponse('u1', errors: ['invalid attribute key']),
          200,
        );
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 500));

      // State persisted from the response (contactId came back as c1).
      expect(config.get().user.data.contactId, 'c1');
      expect(queue.isEmpty, isTrue);
    });
  });

  test('clear cancels the pending timer — no flush afterwards', () async {
    final config = await _seed(userId: 'u1');
    var calls = 0;
    final api = ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: MockClient((req) async {
        calls++;
        return http.Response(_userResponse('u1'), 200);
      }),
    );
    final queue = UpdateQueue.instance
      ..configOverride = config
      ..apiClientOverride = api;

    fakeAsync((async) {
      queue
        ..updateAttributes({'plan': 'pro'})
        ..processUpdates();
      async.elapse(const Duration(milliseconds: 200));
      queue.clear();
      async.elapse(const Duration(milliseconds: 500));

      expect(calls, 0);
    });
  });
}
