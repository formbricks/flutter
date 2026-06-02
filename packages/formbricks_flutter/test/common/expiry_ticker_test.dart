import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/api_client.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/expiry_ticker.dart';
import 'package:formbricks_flutter/src/types/config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _envBody(String expiresAt) => jsonEncode({
  'data': {
    'expiresAt': expiresAt,
    'data': {
      'surveys': <dynamic>[],
      'actionClasses': <dynamic>[],
      'settings': <String, dynamic>{},
    },
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormbricksConfig.resetInstance();
    api = ApiClient(
      appUrl: 'https://app.x',
      workspaceId: 'w',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
  });

  ExpiryTicker makeTicker(void Function() onEachTick) => ExpiryTicker(
    config: FormbricksConfig.instance,
    apiClient: api,
    interval: const Duration(seconds: 60),
    onTick: () async => onEachTick(),
  );

  test('does not tick while paused', () {
    fakeAsync((async) {
      var ticks = 0;
      final ticker = makeTicker(() => ticks++)..start();
      ticker.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.elapse(const Duration(minutes: 5));
      expect(ticks, 0);
      ticker.stop();
    });
  });

  test('runs an immediate check on resume', () {
    fakeAsync((async) {
      var ticks = 0;
      final ticker = makeTicker(() => ticks++)..start();
      expect(ticks, 0, reason: 'start() should not tick immediately');
      ticker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(ticks, 1, reason: 'resume should run an immediate check');
      ticker.stop();
    });
  });

  test('keeps exactly one timer across a pause/resume cycle', () {
    fakeAsync((async) {
      var ticks = 0;
      final ticker = makeTicker(() => ticks++)..start();
      ticker.didChangeAppLifecycleState(AppLifecycleState.paused);
      ticker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final afterResume = ticks; // 1 (the immediate check)
      async.elapse(const Duration(seconds: 60));
      // One timer → exactly one more tick. Two timers would add two.
      expect(ticks - afterResume, 1);
      ticker.stop();
    });
  });

  test('fires on the interval while active', () {
    fakeAsync((async) {
      var ticks = 0;
      final ticker = makeTicker(() => ticks++)..start();
      async.elapse(const Duration(seconds: 60));
      expect(ticks, 1);
      async.elapse(const Duration(seconds: 60));
      expect(ticks, 2);
      ticker.stop();
    });
  });

  group('check()', () {
    final now = DateTime(2026, 6, 1, 12);

    Future<void> seed(TConfig config) async {
      final c = FormbricksConfig.instance;
      await c.init();
      await c.update(config);
    }

    TConfig configWith({
      required DateTime workspaceExpiry,
      DateTime? userExpiry,
      String? userId,
    }) => TConfig(
      workspaceId: 'w',
      appUrl: 'https://app.x',
      workspace: TWorkspaceState(
        expiresAt: workspaceExpiry,
        data: const TWorkspaceData(),
      ),
      user: TUserState(
        expiresAt: userExpiry,
        data: TUserData(userId: userId),
      ),
      status: TStatus.success,
    );

    test('refetches the workspace when it has expired', () async {
      await seed(
        configWith(workspaceExpiry: now.subtract(const Duration(minutes: 1))),
      );
      var calls = 0;
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient((_) async {
          calls++;
          return http.Response(_envBody('2100-01-01T00:00:00.000'), 200);
        }),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );

      await withClock(Clock.fixed(now), ticker.debugCheck);

      expect(calls, 1);
      expect(FormbricksConfig.instance.get().workspace!.expiresAt.year, 2100);
    });

    test('extends workspace validity when the refetch fails', () async {
      await seed(
        configWith(workspaceExpiry: now.subtract(const Duration(minutes: 1))),
      );
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );

      await withClock(Clock.fixed(now), ticker.debugCheck);

      expect(
        FormbricksConfig.instance.get().workspace!.expiresAt,
        now.add(const Duration(minutes: 30)),
      );
    });

    test('extends an identified user state that has expired', () async {
      await seed(
        configWith(
          workspaceExpiry: now.add(const Duration(hours: 1)),
          userExpiry: now.subtract(const Duration(minutes: 1)),
          userId: 'u1',
        ),
      );
      var calls = 0;
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );

      await withClock(Clock.fixed(now), ticker.debugCheck);

      expect(calls, 0, reason: 'workspace not expired → no refetch');
      expect(
        FormbricksConfig.instance.get().user.expiresAt,
        now.add(const Duration(minutes: 30)),
      );
    });

    test('does nothing when no config is loaded', () async {
      FormbricksConfig.resetInstance();
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );
      await withClock(Clock.fixed(now), ticker.debugCheck);
      expect(FormbricksConfig.instance.getOrNull(), isNull);
    });
  });
}
