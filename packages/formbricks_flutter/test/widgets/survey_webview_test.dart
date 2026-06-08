import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/logger.dart';
import 'package:formbricks_flutter/src/survey/survey_store.dart';
import 'package:formbricks_flutter/src/types/survey.dart';
import 'package:formbricks_flutter/src/widgets/survey_webview.dart';
import 'package:formbricks_flutter/src/widgets/webview_event.dart';
import 'package:formbricks_flutter/src/widgets/webview_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// A stub WebView host that never touches a platform channel: it captures the
/// event callback so tests can fire bridge events, and renders a keyed box.
class _StubHost {
  void Function(WebViewEvent)? onEvent;
  String? html;

  Widget build(
    BuildContext context, {
    required String html,
    required String appUrl,
    required void Function(WebViewEvent event) onEvent,
    LaunchUrlFn? launch,
  }) {
    this.onEvent = onEvent;
    this.html = html;
    return const SizedBox(key: Key('stub-webview'), width: 50, height: 50);
  }
}

const _stub = Key('stub-webview');

Future<void> _seedConfig({
  String? language,
  Map<String, dynamic> settings = const {},
}) async {
  final json = jsonEncode({
    'workspaceId': 'wsp_1',
    'appUrl': 'https://app.formbricks.com',
    'workspace': {
      'expiresAt': '2100-01-01T00:00:00.000',
      'data': {
        'surveys': <dynamic>[],
        'actionClasses': <dynamic>[],
        'settings': settings,
      },
    },
    'user': {
      'expiresAt': null,
      'data': {if (language != null) 'language': language},
    },
    'status': {'value': 'success', 'expiresAt': null},
  });
  SharedPreferences.setMockInitialValues({FormbricksConfig.storageKey: json});
  FormbricksConfig.resetInstance();
  await FormbricksConfig.instance.init();
}

TSurvey _survey(Map<String, dynamic> json) => TSurvey.fromJson(json);

/// Reads the persisted config back from the mock store.
Future<Map<String, dynamic>> _storedUserData() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(FormbricksConfig.storageKey)!;
  final stored = jsonDecode(raw) as Map<String, dynamic>;
  return (stored['user'] as Map)['data'] as Map<String, dynamic>;
}

Future<void> _waitUntil(
  Future<bool> Function() done, {
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for async side effect');
    }
    await Future<void>.delayed(step);
  }
}

Future<_StubHost> _present(
  WidgetTester tester,
  TSurvey survey, {
  Future<bool> Function(Uri, {LaunchMode mode})? launch,
}) async {
  final host = _StubHost();
  SurveyStore.instance.setSurvey(survey);
  await tester.pumpWidget(
    MaterialApp(
      home: SurveyWebView(
        survey: survey,
        webViewHostBuilder: host.build,
        launch: launch,
      ),
    ),
  );
  await tester.pump(); // post-frame _start
  await tester.pump(); // route push (transitionDuration: zero)
  return host;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Logger.resetInstance();
    SurveyStore.resetInstance();
    FormbricksConfig.resetInstance();
  });

  testWidgets('presents a single-language survey immediately', (tester) async {
    await _seedConfig();
    final host = await _present(
      tester,
      _survey({'id': 's1', 'languages': <dynamic>[]}),
    );
    expect(find.byKey(_stub), findsOneWidget);
    expect(host.html, contains('renderSurvey'));
  });

  testWidgets(
    'a multi-language survey unavailable in the user language resets & does '
    'not present',
    (tester) async {
      await _seedConfig(language: 'es');
      await _present(
        tester,
        _survey({
          'id': 's1',
          'languages': [
            {
              'default': true,
              'enabled': true,
              'language': {'code': 'en'},
            },
            {
              'default': false,
              'enabled': true,
              'language': {'code': 'de'},
            },
          ],
        }),
      );
      expect(find.byKey(_stub), findsNothing);
      expect(SurveyStore.instance.survey, isNull);
    },
  );

  testWidgets('delay defers presentation until the timer fires',
      (tester) async {
    await _seedConfig();
    final survey = _survey({'id': 's1', 'delay': 2, 'languages': <dynamic>[]});
    final host = _StubHost();
    SurveyStore.instance.setSurvey(survey);
    await tester.pumpWidget(
      MaterialApp(
        home: SurveyWebView(survey: survey, webViewHostBuilder: host.build),
      ),
    );
    await tester.pump(); // _start arms the timer
    expect(find.byKey(_stub), findsNothing);
    await tester.pump(const Duration(seconds: 2)); // timer fires
    await tester.pump(); // route push
    expect(find.byKey(_stub), findsOneWidget);
  });

  testWidgets('unmounting during the delay cancels the timer (no late present)',
      (tester) async {
    await _seedConfig();
    final survey = _survey({'id': 's1', 'delay': 5, 'languages': <dynamic>[]});
    final host = _StubHost();
    SurveyStore.instance.setSurvey(survey);
    await tester.pumpWidget(
      MaterialApp(
        home: SurveyWebView(survey: survey, webViewHostBuilder: host.build),
      ),
    );
    await tester.pump(); // arms the timer
    await tester.pumpWidget(const MaterialApp(home: SizedBox())); // unmount
    await tester.pump(const Duration(seconds: 5)); // would have fired
    expect(find.byKey(_stub), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CloseEvent dismisses the modal and resets the store',
      (tester) async {
    await _seedConfig();
    final host =
        await _present(tester, _survey({'id': 's1', 'languages': <dynamic>[]}));
    expect(find.byKey(_stub), findsOneWidget);

    host.onEvent!(const CloseEvent());
    await tester.pump();
    await tester.pump();

    expect(SurveyStore.instance.survey, isNull);
    expect(find.byKey(_stub), findsNothing);
  });

  testWidgets(
      'DisplayCreatedEvent records a display + lastDisplayAt + persists',
      (tester) async {
    await _seedConfig();
    final host =
        await _present(tester, _survey({'id': 's1', 'languages': <dynamic>[]}));

    Map<String, dynamic>? storedData;
    await tester.runAsync(() async {
      host.onEvent!(const DisplayCreatedEvent());
      await _waitUntil(() async {
        final data = await _storedUserData();
        final displays = data['displays'] as List?;
        return displays != null &&
            displays.isNotEmpty &&
            data['lastDisplayAt'] != null;
      });
      storedData = await _storedUserData();
    });

    // In-memory.
    final data = FormbricksConfig.instance.get().user.data;
    expect(data.displays.length, 1);
    expect(data.displays.single.surveyId, 's1');
    expect(data.lastDisplayAt, isNotNull);
    // Persisted to disk (would fail if the prefs write were dropped).
    final displays = storedData!['displays'] as List;
    expect(displays, hasLength(1));
    expect(displays.single['surveyId'], 's1');
    expect(storedData!['lastDisplayAt'], isNotNull);
  });

  testWidgets('ResponseCreatedEvent appends the survey id + persists',
      (tester) async {
    await _seedConfig();
    final host =
        await _present(tester, _survey({'id': 's1', 'languages': <dynamic>[]}));

    Map<String, dynamic>? storedData;
    await tester.runAsync(() async {
      host.onEvent!(const ResponseCreatedEvent());
      await _waitUntil(() async {
        final data = await _storedUserData();
        final responses = data['responses'] as List?;
        return responses != null &&
            responses.length == 1 &&
            responses.single == 's1';
      });
      storedData = await _storedUserData();
    });

    expect(FormbricksConfig.instance.get().user.data.responses, ['s1']);
    expect(storedData!['responses'], ['s1']); // persisted to disk
  });

  testWidgets('OpenExternalUrlEvent launches via the injected launcher',
      (tester) async {
    await _seedConfig();
    final launched = <Uri>[];
    Future<bool> fakeLaunch(
      Uri url, {
      LaunchMode mode = LaunchMode.platformDefault,
    }) async {
      launched.add(url);
      return true;
    }

    final host = await _present(
      tester,
      _survey({'id': 's1', 'languages': <dynamic>[]}),
      launch: fakeLaunch,
    );

    await tester.runAsync(() async {
      host.onEvent!(const OpenExternalUrlEvent('https://x.com'));
      await _waitUntil(() async => launched.isNotEmpty);
    });

    expect(launched.map((u) => u.toString()).toList(), ['https://x.com']);
  });

  testWidgets('a response immediately followed by close keeps the response',
      (tester) async {
    await _seedConfig();
    final host =
        await _present(tester, _survey({'id': 's1', 'languages': <dynamic>[]}));

    Map<String, dynamic>? storedData;
    await tester.runAsync(() async {
      host.onEvent!(const ResponseCreatedEvent());
      host.onEvent!(const CloseEvent());
      await _waitUntil(() async {
        final data = await _storedUserData();
        final responses = data['responses'] as List?;
        return responses != null &&
            responses.length == 1 &&
            responses.single == 's1';
      });
      storedData = await _storedUserData();
    });
    await tester.pump();

    expect(FormbricksConfig.instance.get().user.data.responses, ['s1']);
    expect(storedData!['responses'], ['s1']); // response survived the close
    expect(SurveyStore.instance.survey, isNull);
  });
}
