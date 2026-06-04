import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/logger.dart';
import 'package:formbricks_flutter/src/common/result.dart';
import 'package:formbricks_flutter/src/common/setup.dart';
import 'package:formbricks_flutter/src/types/config.dart';
import 'package:formbricks_flutter/src/types/errors.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appUrl = 'https://app.formbricks.com';
const _workspaceId = 'wsp_1';

String _envBody() => jsonEncode({
      'data': {
        'expiresAt': '2100-01-01T00:00:00.000',
        'data': {
          'surveys': <dynamic>[],
          'actionClasses': <dynamic>[],
          'settings': <String, dynamic>{},
        },
      },
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

FormbricksError _errOf(Result<void, FormbricksError> r) => switch (r) {
      Ok() => fail('expected Err'),
      Err(:final error) => error,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormbricksConfig.resetInstance();
    Logger.resetInstance();
    resetSetupForTest();
  });

  test(
    'happy path returns Ok and persists config with empty filteredSurveys',
    () async {
      final mock = MockClient((_) async => http.Response(_envBody(), 200));

      final result = await setup(
        appUrl: _appUrl,
        workspaceId: _workspaceId,
        httpClient: mock,
        startTicker: false,
      );

      expect(result.isOk, isTrue);
      final config = FormbricksConfig.instance.get();
      expect(config.workspaceId, _workspaceId);
      expect(config.appUrl, _appUrl);
      expect(config.workspace, isNotNull);
      expect(config.filteredSurveys, isEmpty);
    },
  );

  test('missing workspaceId returns Err(MissingFieldError)', () async {
    final mock = MockClient((_) async => http.Response(_envBody(), 200));
    final result = await setup(
      appUrl: _appUrl,
      workspaceId: '',
      httpClient: mock,
      startTicker: false,
    );
    final error = _errOf(result);
    expect(error, isA<MissingFieldError>());
    expect((error as MissingFieldError).field, 'workspaceId');
  });

  test('missing appUrl returns Err(MissingFieldError)', () async {
    final mock = MockClient((_) async => http.Response(_envBody(), 200));
    final result = await setup(
      appUrl: '',
      workspaceId: _workspaceId,
      httpClient: mock,
      startTicker: false,
    );
    expect((_errOf(result) as MissingFieldError).field, 'appUrl');
  });

  test('non-http(s) appUrl is rejected', () async {
    final mock = MockClient((_) async => http.Response(_envBody(), 200));
    final result = await setup(
      appUrl: 'ftp://app.x',
      workspaceId: _workspaceId,
      httpClient: mock,
      startTicker: false,
    );
    expect((_errOf(result) as MissingFieldError).field, 'appUrl');
  });

  test('hostless appUrl is rejected', () async {
    final mock = MockClient((_) async => http.Response(_envBody(), 200));
    final result = await setup(
      appUrl: 'http://',
      workspaceId: _workspaceId,
      httpClient: mock,
      startTicker: false,
    );
    expect((_errOf(result) as MissingFieldError).field, 'appUrl');
  });

  test('a trailing slash in appUrl is stripped before requesting', () async {
    late Uri requested;
    final mock = MockClient((req) async {
      requested = req.url;
      return http.Response(_envBody(), 200);
    });

    final result = await setup(
      appUrl: 'https://app.formbricks.com/',
      workspaceId: _workspaceId,
      httpClient: mock,
      startTicker: false,
    );

    expect(result.isOk, isTrue);
    // No double slash before /api.
    expect(requested.path, '/api/v2/client/$_workspaceId/environment');
    expect(requested.toString(), isNot(contains('com//')));
    // Persisted appUrl is the normalized form.
    expect(
      FormbricksConfig.instance.get().appUrl,
      'https://app.formbricks.com',
    );
  });

  test('is idempotent — the second call makes no HTTP request', () async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return http.Response(_envBody(), 200);
    });

    await setup(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      httpClient: mock,
      startTicker: false,
    );
    await setup(
      appUrl: _appUrl,
      workspaceId: _workspaceId,
      httpClient: mock,
      startTicker: false,
    );

    expect(calls, 1);
  });

  test('first-setup network failure persists error state and throws', () async {
    final mock = MockClient((_) async => http.Response('{}', 500));
    final now = DateTime(2026, 6, 1, 12);

    await withClock(Clock.fixed(now), () async {
      await expectLater(
        setup(
          appUrl: _appUrl,
          workspaceId: _workspaceId,
          httpClient: mock,
          startTicker: false,
        ),
        throwsA(isA<FormbricksSetupError>()),
      );
    });

    final config = FormbricksConfig.instance.getOrNull();
    expect(config, isNotNull);
    expect(config!.status.isError, isTrue);
    expect(config.status.expiresAt, now.add(const Duration(minutes: 10)));
  });

  test('re-call within the cooldown short-circuits (no HTTP)', () async {
    final now = DateTime(2026, 6, 1, 12);
    final failMock = MockClient((_) async => http.Response('{}', 500));

    await withClock(Clock.fixed(now), () async {
      await expectLater(
        setup(
          appUrl: _appUrl,
          workspaceId: _workspaceId,
          httpClient: failMock,
          startTicker: false,
        ),
        throwsA(isA<FormbricksSetupError>()),
      );
    });

    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return http.Response(_envBody(), 200);
    });

    late Result<void, FormbricksError> result;
    await withClock(Clock.fixed(now.add(const Duration(minutes: 5))), () async {
      result = await setup(
        appUrl: _appUrl,
        workspaceId: _workspaceId,
        httpClient: mock,
        startTicker: false,
      );
    });

    expect(calls, 0);
    expect(_errOf(result), isA<SetupCooldownError>());
    expect(
      (_errOf(result) as SetupCooldownError).retryAt,
      now.add(const Duration(minutes: 10)),
    );
  });

  test(
    're-call after the cooldown elapses proceeds and hits the network',
    () async {
      final now = DateTime(2026, 6, 1, 12);
      final failMock = MockClient((_) async => http.Response('{}', 500));

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          setup(
            appUrl: _appUrl,
            workspaceId: _workspaceId,
            httpClient: failMock,
            startTicker: false,
          ),
          throwsA(isA<FormbricksSetupError>()),
        );
      });

      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        return http.Response(_envBody(), 200);
      });

      late Result<void, FormbricksError> result;
      await withClock(
        Clock.fixed(now.add(const Duration(minutes: 11))),
        () async {
          result = await setup(
            appUrl: _appUrl,
            workspaceId: _workspaceId,
            httpClient: mock,
            startTicker: false,
          );
        },
      );

      expect(calls, 1);
      expect(result.isOk, isTrue);
    },
  );

  test(
    'cached userId with expired user state triggers createOrUpdateUser',
    () async {
      final now = DateTime(2026, 6, 1, 12);
      final cached = TConfig(
        workspaceId: _workspaceId,
        appUrl: _appUrl,
        workspace: TWorkspaceState(
          expiresAt: now.add(const Duration(hours: 1)),
          data: const TWorkspaceData(),
        ),
        user: TUserState(
          expiresAt: now.subtract(const Duration(minutes: 1)),
          data: const TUserData(userId: 'u1'),
        ),
        filteredSurveys: const [],
        status: TStatus.success,
      );
      SharedPreferences.setMockInitialValues({
        FormbricksConfig.storageKey: jsonEncode(cached.toJson()),
      });
      FormbricksConfig.resetInstance();

      var userCalls = 0;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/user')) {
          userCalls++;
          return http.Response(_userBody(), 200);
        }
        return http.Response(_envBody(), 200);
      });

      late Result<void, FormbricksError> result;
      await withClock(Clock.fixed(now), () async {
        result = await setup(
          appUrl: _appUrl,
          workspaceId: _workspaceId,
          httpClient: mock,
          startTicker: false,
        );
      });

      expect(result.isOk, isTrue);
      expect(userCalls, 1);
    },
  );

  test('matching config with a still-valid user makes no user call', () async {
    final now = DateTime(2026, 6, 1, 12);
    final cached = TConfig(
      workspaceId: _workspaceId,
      appUrl: _appUrl,
      workspace: TWorkspaceState(
        expiresAt: now.add(const Duration(hours: 1)),
        data: const TWorkspaceData(),
      ),
      user: TUserState(
        expiresAt: now.add(const Duration(minutes: 30)),
        data: const TUserData(userId: 'u1'),
      ),
      status: TStatus.success,
    );
    SharedPreferences.setMockInitialValues({
      FormbricksConfig.storageKey: jsonEncode(cached.toJson()),
    });
    FormbricksConfig.resetInstance();

    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return http.Response(_envBody(), 200);
    });

    late Result<void, FormbricksError> result;
    await withClock(Clock.fixed(now), () async {
      result = await setup(
        appUrl: _appUrl,
        workspaceId: _workspaceId,
        httpClient: mock,
        startTicker: false,
      );
    });

    expect(result.isOk, isTrue);
    expect(calls, 0);
  });

  test('a failed user refresh in the matching path returns Err', () async {
    final now = DateTime(2026, 6, 1, 12);
    final cached = TConfig(
      workspaceId: _workspaceId,
      appUrl: _appUrl,
      workspace: TWorkspaceState(
        expiresAt: now.add(const Duration(hours: 1)),
        data: const TWorkspaceData(),
      ),
      user: TUserState(
        expiresAt: now.subtract(const Duration(minutes: 1)),
        data: const TUserData(userId: 'u1'),
      ),
      status: TStatus.success,
    );
    SharedPreferences.setMockInitialValues({
      FormbricksConfig.storageKey: jsonEncode(cached.toJson()),
    });
    FormbricksConfig.resetInstance();

    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/user')) return http.Response('{}', 500);
      return http.Response(_envBody(), 200);
    });

    late Result<void, FormbricksError> result;
    await withClock(Clock.fixed(now), () async {
      result = await setup(
        appUrl: _appUrl,
        workspaceId: _workspaceId,
        httpClient: mock,
        startTicker: false,
      );
    });

    expect(_errOf(result), isA<NetworkError>());
  });
}
