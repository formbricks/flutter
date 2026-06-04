import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/api_client.dart';
import 'package:formbricks_flutter/src/common/result.dart';
import 'package:formbricks_flutter/src/types/config.dart';
import 'package:formbricks_flutter/src/types/errors.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _appUrl = 'https://app.formbricks.com';
const _workspaceId = 'wsp_1';

String _envBody(Map<String, dynamic> data) => jsonEncode({
      'data': {'expiresAt': '2100-01-01T00:00:00.000', 'data': data},
    });

String _userBody() => jsonEncode({
      'data': {
        'state': {
          'expiresAt': null,
          'data': {
            'userId': 'u1',
            'contactId': null,
            'segments': <dynamic>[],
            'displays': <dynamic>[],
            'responses': <dynamic>[],
            'lastDisplayAt': null,
          },
        },
      },
    });

ApiClient _client(MockClient mock, {bool isDebug = false}) => ApiClient(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      client: mock,
      isDebug: isDebug,
    );

TWorkspaceState _okWorkspace(Result<TWorkspaceState, ApiErrorResponse> r) =>
    switch (r) {
      Ok(:final value) => value,
      Err(:final error) => fail('expected Ok, got $error'),
    };

ApiErrorResponse _errOf(Result<Object?, ApiErrorResponse> r) => switch (r) {
      Ok() => fail('expected Err'),
      Err(:final error) => error,
    };

void main() {
  group('getWorkspaceState', () {
    test('parses a happy response', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          _envBody({
            'surveys': <dynamic>[],
            'actionClasses': <dynamic>[],
            'settings': {'recontactDays': 5},
          }),
          200,
        );
      });

      final result = await _client(mock).getWorkspaceState();
      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v2/client/$_workspaceId/environment');
      expect(_okWorkspace(result).data.settings, {'recontactDays': 5});
    });

    test('maps legacy data.workspace to settings', () async {
      final mock = MockClient(
        (req) async => http.Response(
          _envBody({
            'surveys': <dynamic>[],
            'actionClasses': <dynamic>[],
            'workspace': {'placement': 'bottomRight'},
          }),
          200,
        ),
      );

      final result = await _client(mock).getWorkspaceState();
      expect(_okWorkspace(result).data.settings, {'placement': 'bottomRight'});
    });

    test('maps legacy data.project to settings', () async {
      final mock = MockClient(
        (req) async => http.Response(
          _envBody({
            'surveys': <dynamic>[],
            'actionClasses': <dynamic>[],
            'project': {'placement': 'center'},
          }),
          200,
        ),
      );

      final result = await _client(mock).getWorkspaceState();
      expect(_okWorkspace(result).data.settings, {'placement': 'center'});
    });

    test('maps a 4xx response to forbidden', () async {
      final mock = MockClient(
        (req) async => http.Response('{"message":"nope"}', 403),
      );
      final error = _errOf(await _client(mock).getWorkspaceState());
      expect(error.code, 'forbidden');
      expect(error.status, 403);
    });

    test('maps a 404 to forbidden', () async {
      final mock = MockClient((req) async => http.Response('{}', 404));
      expect(_errOf(await _client(mock).getWorkspaceState()).code, 'forbidden');
    });

    test('maps a 5xx response to network_error', () async {
      final mock = MockClient((req) async => http.Response('{}', 500));
      final error = _errOf(await _client(mock).getWorkspaceState());
      expect(error.code, 'network_error');
      expect(error.status, 500);
    });

    test('catches a thrown SocketException as network_error', () async {
      final mock = MockClient(
        (req) async => throw const SocketException('offline'),
      );
      expect(
        _errOf(await _client(mock).getWorkspaceState()).code,
        'network_error',
      );
    });

    test('catches a thrown ClientException as network_error', () async {
      final mock = MockClient(
        (req) async => throw http.ClientException('boom'),
      );
      expect(
        _errOf(await _client(mock).getWorkspaceState()).code,
        'network_error',
      );
    });

    test('maps a 200 with a malformed body to network_error', () async {
      // 2xx, but data.expiresAt is missing → TWorkspaceState.fromJson throws.
      // Must normalize to Err(network_error), not leak a raw TypeError.
      final mock = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'data': {
              'data': {'surveys': <dynamic>[], 'actionClasses': <dynamic>[]},
            },
          }),
          200,
        ),
      );
      final error = _errOf(await _client(mock).getWorkspaceState());
      expect(error.code, 'network_error');
      expect(error.status, 200);
      expect(error.message, 'Malformed response');
    });

    test('maps a 200 with an empty body to network_error', () async {
      final mock = MockClient((req) async => http.Response('', 200));
      final error = _errOf(await _client(mock).getWorkspaceState());
      expect(error.code, 'network_error');
      expect(error.status, 200);
    });
  });

  group('createOrUpdateUser', () {
    test(
      'preserves number types and sends the right URL/method/body',
      () async {
        late http.Request captured;
        final mock = MockClient((req) async {
          captured = req;
          return http.Response(_userBody(), 200);
        });

        final result = await _client(mock).createOrUpdateUser(
          userId: 'u1',
          attributes: {'plan': 'pro', 'mrr': 99},
        );

        expect(result.isOk, isTrue);
        expect(captured.method, 'POST');
        expect(captured.url.path, '/api/v2/client/$_workspaceId/user');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['userId'], 'u1');
        expect(body['attributes']['plan'], 'pro');
        expect(body['attributes']['mrr'], 99);
        expect(body['attributes']['mrr'], isA<num>());
      },
    );

    test('omits attributes when none are given', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_userBody(), 200);
      });

      await _client(mock).createOrUpdateUser(userId: 'u1');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('attributes'), isFalse);
    });
  });

  group('headers', () {
    test('isDebug adds Cache-Control: no-cache', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_envBody({'settings': <String, dynamic>{}}), 200);
      });

      await _client(mock, isDebug: true).getWorkspaceState();
      expect(captured.headers['cache-control'], 'no-cache');
    });

    test('default does not set Cache-Control', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_envBody({'settings': <String, dynamic>{}}), 200);
      });

      await _client(mock).getWorkspaceState();
      expect(captured.headers.containsKey('cache-control'), isFalse);
    });
  });
}
