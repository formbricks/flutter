import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/logger.dart';
import 'package:formbricks_flutter/src/common/setup.dart';
import 'package:formbricks_flutter/src/survey/survey_store.dart';
import 'package:formbricks_flutter/src/types/survey.dart';
import 'package:formbricks_flutter/src/widgets/formbricks_widget.dart';
import 'package:formbricks_flutter/src/widgets/survey_webview.dart';
import 'package:formbricks_flutter/src/widgets/webview_event.dart';
import 'package:formbricks_flutter/src/widgets/webview_navigation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubHost {
  void Function(WebViewEvent)? onEvent;

  Widget build(
    BuildContext context, {
    required String html,
    required String appUrl,
    required void Function(WebViewEvent event) onEvent,
    LaunchUrlFn? launch,
  }) {
    this.onEvent = onEvent;
    return const SizedBox(key: Key('stub-webview'), width: 50, height: 50);
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormbricksConfig.resetInstance();
    Logger.resetInstance();
    SurveyStore.resetInstance();
    resetSetupForTest();
  });

  testWidgets('renders nothing and does not swallow touches when idle',
      (tester) async {
    final mock = MockClient((_) async => http.Response(_envBody(), 200));
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Center(
              child: ElevatedButton(
                onPressed: () => tapped = true,
                child: const Text('behind'),
              ),
            ),
            Formbricks(
              appUrl: 'https://app.formbricks.com',
              workspaceId: 'wsp_1',
              httpClient: mock,
              startTicker: false,
            ),
          ],
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.byType(SurveyWebView), findsNothing);
    await tester.tap(find.text('behind'));
    expect(tapped, isTrue);
  });

  testWidgets('renders SurveyWebView when a survey is set', (tester) async {
    final mock = MockClient((_) async => http.Response(_envBody(), 200));
    final host = _StubHost();

    await tester.pumpWidget(
      MaterialApp(
        home: Formbricks(
          appUrl: 'https://app.formbricks.com',
          workspaceId: 'wsp_1',
          httpClient: mock,
          startTicker: false,
          webViewHostBuilder: host.build,
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    SurveyStore.instance.setSurvey(
      TSurvey.fromJson({'id': 's1', 'languages': <dynamic>[]}),
    );
    await tester.pump(); // host rebuild
    await tester.pump(); // post-frame _start
    await tester.pump(); // route push

    expect(find.byType(SurveyWebView), findsOneWidget);
    expect(find.byKey(const Key('stub-webview')), findsOneWidget);
  });

  testWidgets('calls setup exactly once on mount (rebuilds do not re-run it)',
      (tester) async {
    var envFetches = 0;
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/environment')) envFetches++;
      return http.Response(_envBody(), 200);
    });
    final host = _StubHost();

    await tester.pumpWidget(
      MaterialApp(
        home: Formbricks(
          appUrl: 'https://app.formbricks.com',
          workspaceId: 'wsp_1',
          httpClient: mock,
          startTicker: false,
          webViewHostBuilder: host.build,
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(envFetches, 1);

    // Force host rebuilds via store changes; initState must not re-run.
    SurveyStore.instance.setSurvey(
      TSurvey.fromJson({'id': 's1', 'languages': <dynamic>[]}),
    );
    await tester.pump();
    SurveyStore.instance.resetSurvey();
    await tester.pump();

    expect(envFetches, 1);
  });
}
