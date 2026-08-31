import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/config.dart';
import 'package:formbricks/src/common/logger.dart';
import 'package:formbricks/src/survey/embedded_data.dart';
import 'package:formbricks/src/survey/survey_store.dart';
import 'package:formbricks/src/types/survey.dart';
import 'package:formbricks/src/user/update_queue.dart';
import 'package:formbricks/src/widgets/survey_webview.dart';
import 'package:formbricks/src/widgets/webview_event.dart';
import 'package:formbricks/src/widgets/webview_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// A stub WebView host that never touches a platform channel: it captures the
/// event callback so tests can fire bridge events, and renders a keyed box.
class _StubHost {
  void Function(WebViewEvent)? onEvent;
  VoidCallback? onLoadError;
  String? html;

  Widget build(
    BuildContext context, {
    required String html,
    required String appUrl,
    required void Function(WebViewEvent event) onEvent,
    LaunchUrlFn? launch,
    VoidCallback? onLoadError,
  }) {
    this.onEvent = onEvent;
    this.onLoadError = onLoadError;
    this.html = html;
    return const SizedBox(key: Key('stub-webview'), width: 50, height: 50);
  }
}

const _stub = Key('stub-webview');

/// A full-bleed, tappable stub host: counts taps that reach the WebView region
/// and captures the event callback so tests can push geometry.
class _TappableHost {
  void Function(WebViewEvent)? onEvent;
  int taps = 0;

  Widget build(
    BuildContext context, {
    required String html,
    required String appUrl,
    required void Function(WebViewEvent event) onEvent,
    LaunchUrlFn? launch,
    VoidCallback? onLoadError,
  }) {
    this.onEvent = onEvent;
    return GestureDetector(
      key: _stub,
      behavior: HitTestBehavior.opaque,
      onTap: () => taps++,
      child: const SizedBox.expand(),
    );
  }
}

Future<void> _seedConfig({
  String? language,
  String? userId,
  Map<String, dynamic> settings = const {},
  List<Map<String, dynamic>> surveys = const [],
  List<Map<String, dynamic>> filteredSurveys = const [],
  bool omitWorkspace = false,
}) async {
  final json = jsonEncode({
    'workspaceId': 'wsp_1',
    'appUrl': 'https://app.formbricks.com',
    'workspace': omitWorkspace
        ? null
        : {
            'expiresAt': '2100-01-01T00:00:00.000',
            'data': {
              'surveys': surveys,
              'actionClasses': <dynamic>[],
              'settings': settings,
            },
          },
    'user': {
      'expiresAt': null,
      'data': {
        if (language != null) 'language': language,
        if (userId != null) 'userId': userId,
      },
    },
    'filteredSurveys': filteredSurveys,
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
    EmbeddedDataStore.instance.clear();
  });

  tearDown(EmbeddedDataStore.instance.clear);

  group('the Embedded Data pipe', () {
    // `_present` passing `hiddenFieldsRecord: EmbeddedDataStore.instance
    // .snapshot()` is the single line joining the store, the render options and
    // the renderer. The store, the options and the identity-clear are each
    // tested in isolation elsewhere, so without these two the line could be
    // deleted with every other test still green — and its failure mode is
    // silent: the survey renders, the values just never arrive.
    testWidgets('the display-time snapshot reaches the WebView html',
        (tester) async {
      await _seedConfig();
      EmbeddedDataStore.instance.set({'plan': 'pro', 'screen': 'checkout'});

      final host = await _present(
        tester,
        _survey({'id': 's1', 'languages': <dynamic>[]}),
      );

      expect(
        host.html,
        contains('"hiddenFieldsRecord":{"plan":"pro","screen":"checkout"}'),
      );
    });

    testWidgets('a value set during the delay still reaches the survey',
        (tester) async {
      // Pins "read at display, not at mount": the bag is empty when the widget
      // mounts and only filled while the delay timer runs.
      await _seedConfig();
      final survey =
          _survey({'id': 's1', 'delay': 2, 'languages': <dynamic>[]});
      final host = _StubHost();
      SurveyStore.instance.setSurvey(survey);
      await tester.pumpWidget(
        MaterialApp(
          home: SurveyWebView(survey: survey, webViewHostBuilder: host.build),
        ),
      );
      await tester.pump(); // _start arms the timer
      expect(host.html, isNull);

      EmbeddedDataStore.instance.set({'plan': 'pro'});
      await tester.pump(const Duration(seconds: 2)); // timer fires
      await tester.pump(); // route push

      expect(host.html, contains('"hiddenFieldsRecord":{"plan":"pro"}'));
    });
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

  testWidgets('WebView load errors dismiss the modal and reset the store',
      (tester) async {
    await _seedConfig();
    final host =
        await _present(tester, _survey({'id': 's1', 'languages': <dynamic>[]}));
    expect(find.byKey(_stub), findsOneWidget);

    host.onLoadError!();
    await tester.pump();
    await tester.pump();

    expect(SurveyStore.instance.survey, isNull);
    expect(find.byKey(_stub), findsNothing);
  });

  group('interaction-based segment refresh', () {
    setUp(UpdateQueue.resetInstance);

    testWidgets('FinishedEvent nudges the refresh when the gate allows it',
        (tester) async {
      await _seedConfig(userId: 'user-1');
      final host = await _present(
        tester,
        _survey({
          'id': 's1',
          'languages': <dynamic>[],
          'interactionRefresh': {'onFinished': true},
        }),
      );

      host.onEvent!(const FinishedEvent());

      expect(UpdateQueue.instance.pendingUserId, 'user-1');
      // Cancel the debounced flush so no timer outlives the test.
      UpdateQueue.resetInstance();
    });

    testWidgets('DisplayCreatedEvent nudges the refresh when flagged',
        (tester) async {
      await _seedConfig(userId: 'user-1');
      final host = await _present(
        tester,
        _survey({
          'id': 's1',
          'languages': <dynamic>[],
          'interactionRefresh': {'onDisplay': true},
        }),
      );

      host.onEvent!(const DisplayCreatedEvent());

      expect(UpdateQueue.instance.pendingUserId, 'user-1');
      UpdateQueue.resetInstance();
    });

    testWidgets('a closed gate makes every event a no-op', (tester) async {
      await _seedConfig(userId: 'user-1');
      final host = await _present(
        tester,
        _survey({'id': 's1', 'languages': <dynamic>[]}),
      );

      host.onEvent!(const FinishedEvent());
      host.onEvent!(const DisplayCreatedEvent());

      expect(UpdateQueue.instance.isEmpty, isTrue);
    });

    testWidgets('the same source refreshes at most once per showing',
        (tester) async {
      await _seedConfig(userId: 'user-1');
      final host = await _present(
        tester,
        _survey({
          'id': 's1',
          'languages': <dynamic>[],
          'interactionRefresh': {'onFinished': true},
        }),
      );

      host.onEvent!(const FinishedEvent());
      expect(UpdateQueue.instance.pendingUserId, 'user-1');

      UpdateQueue.resetInstance();
      host.onEvent!(const FinishedEvent());
      expect(UpdateQueue.instance.isEmpty, isTrue);
    });
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

  testWidgets('DisplayCreatedEvent refilters — a displayOnce survey drops out',
      (tester) async {
    final surveyJson = {
      'id': 's1',
      'displayOption': 'displayOnce',
      'triggers': <dynamic>[],
      'languages': <dynamic>[],
    };
    await _seedConfig(surveys: [surveyJson], filteredSurveys: [surveyJson]);
    final host = await _present(tester, _survey(surveyJson));

    await tester.runAsync(() async {
      host.onEvent!(const DisplayCreatedEvent());
      await _waitUntil(() async {
        final data = await _storedUserData();
        return (data['displays'] as List?)?.isNotEmpty ?? false;
      });
    });

    expect(
      FormbricksConfig.instance.get().filteredSurveys,
      isEmpty,
      reason: 'the just-displayed displayOnce survey must leave the '
          'eligible set immediately',
    );
  });

  testWidgets(
      'ResponseCreatedEvent refilters — a displayMultiple survey drops out',
      (tester) async {
    final surveyJson = {
      'id': 's1',
      'displayOption': 'displayMultiple',
      'triggers': <dynamic>[],
      'languages': <dynamic>[],
    };
    await _seedConfig(surveys: [surveyJson], filteredSurveys: [surveyJson]);
    final host = await _present(tester, _survey(surveyJson));

    await tester.runAsync(() async {
      host.onEvent!(const ResponseCreatedEvent());
      await _waitUntil(() async {
        final data = await _storedUserData();
        return (data['responses'] as List?)?.isNotEmpty ?? false;
      });
    });

    expect(
      FormbricksConfig.instance.get().filteredSurveys,
      isEmpty,
      reason: 'the just-answered displayMultiple survey must leave the '
          'eligible set immediately',
    );
  });

  testWidgets('DisplayCreatedEvent refilter keeps still-eligible surveys',
      (tester) async {
    final shown = {
      'id': 's1',
      'displayOption': 'displayOnce',
      'triggers': <dynamic>[],
      'languages': <dynamic>[],
    };
    final keeper = {
      'id': 'keeper',
      'displayOption': 'respondMultiple',
      'triggers': <dynamic>[],
      'languages': <dynamic>[],
    };
    await _seedConfig(
      surveys: [shown, keeper],
      filteredSurveys: [shown, keeper],
    );
    final host = await _present(tester, _survey(shown));

    await tester.runAsync(() async {
      host.onEvent!(const DisplayCreatedEvent());
      await _waitUntil(() async {
        final data = await _storedUserData();
        return (data['displays'] as List?)?.isNotEmpty ?? false;
      });
    });

    expect(
      FormbricksConfig.instance
          .get()
          .filteredSurveys
          .map((e) => (e as Map)['id'])
          .toList(),
      ['keeper'],
      reason: 'only the just-displayed displayOnce survey drops out',
    );
  });

  testWidgets(
      'DisplayCreatedEvent without a workspace empties filteredSurveys '
      'without throwing', (tester) async {
    final surveyJson = {
      'id': 's1',
      'triggers': <dynamic>[],
      'languages': <dynamic>[],
    };
    await _seedConfig(
      omitWorkspace: true,
      filteredSurveys: [surveyJson],
    );
    final host = await _present(tester, _survey(surveyJson));

    await tester.runAsync(() async {
      host.onEvent!(const DisplayCreatedEvent());
      await _waitUntil(() async {
        final data = await _storedUserData();
        return (data['displays'] as List?)?.isNotEmpty ?? false;
      });
    });

    expect(FormbricksConfig.instance.get().filteredSurveys, isEmpty);
    expect(tester.takeException(), isNull);
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

  group('box-none touch pass-through', () {
    // Presents the survey above a full-screen host tap target and returns both
    // so a test can assert which layer a tap reaches.
    Future<({_TappableHost host, int Function() hostTaps})> presentOver(
      WidgetTester tester,
      TSurvey survey,
    ) async {
      final host = _TappableHost();
      var hostTaps = 0;
      SurveyStore.instance.setSurvey(survey);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => hostTaps++,
                  child: const SizedBox.expand(),
                ),
              ),
              SurveyWebView(survey: survey, webViewHostBuilder: host.build),
            ],
          ),
        ),
      );
      await tester.pump(); // post-frame _start
      await tester.pump(); // present
      return (host: host, hostTaps: () => hostTaps);
    }

    testWidgets(
        'non-overlay: taps outside the card reach the host, inside hit the card',
        (tester) async {
      await _seedConfig(); // no overlay configured → box-none
      final r = await presentOver(
        tester,
        _survey({'id': 's1', 'languages': <dynamic>[]}),
      );
      // Card occupies the top-left 100x100; everything else is pass-through.
      r.host.onEvent!(const GeometryEvent(Rect.fromLTWH(0, 0, 100, 100)));
      await tester.pump();

      await tester.tapAt(const Offset(400, 400)); // outside the card
      await tester.tapAt(const Offset(50, 50)); // inside the card
      await tester.pump();

      expect(r.hostTaps(), 1, reason: 'outside-card tap falls through to host');
      expect(r.host.taps, 1, reason: 'inside-card tap hits the WebView');
    });

    testWidgets('non-overlay before geometry arrives: every tap passes through',
        (tester) async {
      await _seedConfig();
      final r = await presentOver(
        tester,
        _survey({'id': 's1', 'languages': <dynamic>[]}),
      );
      // No GeometryEvent yet → nothing is interactive.
      await tester.tapAt(const Offset(50, 50));
      await tester.pump();

      expect(r.hostTaps(), 1);
      expect(r.host.taps, 0);
    });

    testWidgets('overlay (backdrop): the survey blocks the whole host',
        (tester) async {
      await _seedConfig(settings: {'overlay': 'dark'});
      final r = await presentOver(
        tester,
        _survey({'id': 's1', 'languages': <dynamic>[]}),
      );
      // A backdrop survey is full-screen; geometry is irrelevant.
      await tester.tapAt(const Offset(50, 50));
      await tester.tapAt(const Offset(400, 400));
      await tester.pump();

      expect(r.hostTaps(), 0, reason: 'backdrop must block the host entirely');
      expect(r.host.taps, 2, reason: 'all taps land on the full-screen survey');
    });
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
