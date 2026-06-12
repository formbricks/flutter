import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/api_client.dart';
import 'package:formbricks/src/common/config.dart';
import 'package:formbricks/src/common/expiry_ticker.dart';
import 'package:formbricks/src/types/config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _envBody(
  String expiresAt, {
  List<Map<String, dynamic>> surveys = const [],
}) =>
    jsonEncode({
      'data': {
        'expiresAt': expiresAt,
        'data': {
          'surveys': surveys,
          'actionClasses': <dynamic>[],
          'settings': <String, dynamic>{},
        },
      },
    });

Map<String, dynamic> _surveyJson(
  String id, {
  Map<String, dynamic>? segment,
}) =>
    {
      'id': id,
      'displayOption': 'respondMultiple',
      'triggers': <dynamic>[],
      'languages': <dynamic>[],
      if (segment != null) 'segment': segment,
    };

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
      List<String> segments = const [],
    }) =>
        TConfig(
          workspaceId: 'w',
          appUrl: 'https://app.x',
          workspace: TWorkspaceState(
            expiresAt: workspaceExpiry,
            data: const TWorkspaceData(),
          ),
          user: TUserState(
            expiresAt: userExpiry,
            data: TUserData(userId: userId, segments: segments),
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

    test('refetch recomputes filteredSurveys for an anonymous user', () async {
      await seed(
        configWith(workspaceExpiry: now.subtract(const Duration(minutes: 1))),
      );
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient(
          (_) async => http.Response(
            _envBody(
              '2100-01-01T00:00:00.000',
              surveys: [
                _surveyJson('plain'),
                _surveyJson(
                  'gated',
                  segment: {'id': 'seg_a', 'hasFilters': true},
                ),
              ],
            ),
            200,
          ),
        ),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );

      await withClock(Clock.fixed(now), ticker.debugCheck);

      expect(
        FormbricksConfig.instance
            .get()
            .filteredSurveys
            .map((e) => (e as Map)['id'])
            .toList(),
        ['plain'],
        reason: 'segment-filtered surveys drop without a userId',
      );
    });

    test('refetch recomputes filteredSurveys against the identified user',
        () async {
      await seed(
        configWith(
          workspaceExpiry: now.subtract(const Duration(minutes: 1)),
          userId: 'u1',
          segments: ['seg_a'],
        ),
      );
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient(
          (_) async => http.Response(
            _envBody(
              '2100-01-01T00:00:00.000',
              surveys: [
                _surveyJson('plain'),
                _surveyJson(
                  'gated',
                  segment: {'id': 'seg_a', 'hasFilters': true},
                ),
              ],
            ),
            200,
          ),
        ),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );

      await withClock(Clock.fixed(now), ticker.debugCheck);

      expect(
        FormbricksConfig.instance
            .get()
            .filteredSurveys
            .map((e) => (e as Map)['id'])
            .toList(),
        ['gated'],
        reason: 'identified users only see segment-matched surveys',
      );
    });

    test('a config write landing during the refetch is not clobbered (Ok)',
        () async {
      await seed(
        configWith(workspaceExpiry: now.subtract(const Duration(minutes: 1))),
      );
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient((_) async {
          // Concurrent writer while the request is on the wire.
          final mid = FormbricksConfig.instance.get();
          await FormbricksConfig.instance.update(
            mid.copyWith(
              user: const TUserState(
                expiresAt: null,
                data: TUserData(userId: 'u1', segments: ['seg_a']),
              ),
            ),
          );
          return http.Response(
            _envBody(
              '2100-01-01T00:00:00.000',
              surveys: [
                _surveyJson('plain'),
                _surveyJson(
                  'gated',
                  segment: {'id': 'seg_a', 'hasFilters': true},
                ),
              ],
            ),
            200,
          );
        }),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );

      await withClock(Clock.fixed(now), ticker.debugCheck);

      final config = FormbricksConfig.instance.get();
      expect(
        config.user.data.userId,
        'u1',
        reason: 'the concurrent user write must survive the workspace persist',
      );
      expect(
        config.filteredSurveys.map((e) => (e as Map)['id']).toList(),
        ['gated'],
        reason: 'the refilter must see the concurrently-written user',
      );
    });

    test('a config write landing during a failed refetch is kept (Err)',
        () async {
      await seed(
        configWith(workspaceExpiry: now.subtract(const Duration(minutes: 1))),
      );
      final api = ApiClient(
        appUrl: 'https://app.x',
        workspaceId: 'w',
        client: MockClient((_) async {
          final mid = FormbricksConfig.instance.get();
          await FormbricksConfig.instance.update(
            mid.copyWith(
              user: const TUserState(
                expiresAt: null,
                data: TUserData(userId: 'u1'),
              ),
            ),
          );
          return http.Response('{}', 500);
        }),
      );
      final ticker = ExpiryTicker(
        config: FormbricksConfig.instance,
        apiClient: api,
      );

      await withClock(Clock.fixed(now), ticker.debugCheck);

      final config = FormbricksConfig.instance.get();
      expect(config.user.data.userId, 'u1', reason: 'concurrent write kept');
      expect(
        config.workspace!.expiresAt,
        now.add(const Duration(minutes: 30)),
        reason: 'validity still extended for the retry',
      );
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
