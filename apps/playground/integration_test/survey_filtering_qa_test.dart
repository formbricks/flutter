/// E2E QA for ENG-1128 survey eligibility filtering, against a real local
/// Formbricks backend and the real survey runtime in a WebView.
///
/// Run (simulator booted, backend on localhost:3000):
/// ```sh
/// fvm flutter test integration_test/survey_filtering_qa_test.dart \
///   -d UDID \
///   --dart-define=APP_URL=http://localhost:3000 \
///   --dart-define=WORKSPACE_ID=WSP_ID \
///   --dart-define=SURVEY_ID=SURVEY_ID \
///   --dart-define=SCENARIO=baseline
/// ```
///
/// SCENARIO selects the assertion set; the survey must be configured in the
/// dashboard to match (see the QA matrix in the PR/session notes).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/formbricks_flutter.dart';
import 'package:formbricks_playground/main.dart';
import 'package:integration_test/integration_test.dart';

const String _surveyId = String.fromEnvironment('SURVEY_ID');
const String _scenario = String.fromEnvironment(
  'SCENARIO',
  defaultValue: 'baseline',
);

Future<Map<String, dynamic>> _storedConfig() async {
  final raw = await Formbricks.debugStoredConfig();
  expect(raw, isNotNull, reason: 'no persisted config');
  return jsonDecode(raw!) as Map<String, dynamic>;
}

List<String> _filteredIds(Map<String, dynamic> config) =>
    ((config['filteredSurveys'] as List?) ?? const [])
        .map((e) => (e as Map)['id'] as String)
        .toList();

List<dynamic> _displays(Map<String, dynamic> config) =>
    ((config['user'] as Map)['data'] as Map)['displays'] as List? ?? const [];

/// Polls the persisted config until [predicate] passes or [timeout] elapses.
Future<Map<String, dynamic>> _waitForConfig(
  WidgetTester tester,
  bool Function(Map<String, dynamic>) predicate, {
  Duration timeout = const Duration(seconds: 20),
  String? what,
}) async {
  final deadline = DateTime.now().add(timeout);
  late Map<String, dynamic> config;
  while (true) {
    config = await _storedConfig();
    if (predicate(config)) return config;
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'timed out waiting for ${what ?? 'config condition'}; '
        'filteredSurveys=${_filteredIds(config)} '
        'displays=${_displays(config).length}',
      );
    }
    await tester.pump(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const PlaygroundApp());
  // Wait for auto-connect (dart-defines) to complete.
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (find.textContaining('Connected to').evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('app never reached connected state');
    }
    await tester.pump(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _trigger(WidgetTester tester) =>
    _tapButton(tester, 'Trigger Code Action');

/// Closes an open survey by popping its modal route.
Future<void> _closeSurvey(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.pop();
  await tester.pump(const Duration(milliseconds: 500));
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// Waits until the display count for the session reaches [count] — proof the
/// real survey runtime rendered and fired onDisplayCreated over the bridge.
Future<Map<String, dynamic>> _waitForDisplays(WidgetTester tester, int count) =>
    _waitForConfig(
      tester,
      (c) => _displays(c).length >= count,
      what: 'display #$count',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scenario: $_scenario', (tester) async {
    expect(_surveyId, isNotEmpty, reason: 'pass --dart-define=SURVEY_ID=...');

    await Formbricks.debugClearStoredConfig();
    await _pumpApp(tester);

    switch (_scenario) {
      // Survey: displaySome (limit >= 2), no recontact, no percentage,
      // segment without filters. Expect: eligible, shows repeatedly,
      // displays recorded.
      case 'baseline':
        var config = await _waitForConfig(
          tester,
          (c) => _filteredIds(c).contains(_surveyId),
          what: 'survey eligible after fresh sync',
        );
        expect(_displays(config), isEmpty);

        await _trigger(tester);
        config = await _waitForDisplays(tester, 1);
        final userData = (config['user'] as Map)['data'] as Map;
        debugPrint(
          'QA filtered=${_filteredIds(config)} '
          'responses=${userData['responses']} '
          'lastDisplayAt=${userData['lastDisplayAt']} '
          'displays=${jsonEncode(userData['displays'])}',
        );
        debugPrint(
          'QA survey=${jsonEncode(((config['workspace'] as Map)['data'] as Map)['surveys'])}',
        );
        expect(
          _filteredIds(config),
          contains(_surveyId),
          reason: 'displaySome below limit stays eligible',
        );
        await _closeSurvey(tester);

        await _trigger(tester);
        await _waitForDisplays(tester, 2);
        await _closeSurvey(tester);

      // Survey: displayOnce. Expect: shows once, then drops out of the
      // eligible set immediately; second trigger shows nothing.
      case 'displayOnce':
        await _waitForConfig(
          tester,
          (c) => _filteredIds(c).contains(_surveyId),
          what: 'survey eligible after fresh sync',
        );

        await _trigger(tester);
        final config = await _waitForDisplays(tester, 1);
        expect(
          _filteredIds(config),
          isNot(contains(_surveyId)),
          reason: 'displayOnce must drop out after its display',
        );
        await _closeSurvey(tester);

        await _trigger(tester);
        await tester.pump(const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(
          _displays(await _storedConfig()).length,
          1,
          reason: 'second trigger must not display again',
        );

      // Survey: displaySome with displayLimit=2. Expect: two displays, then
      // ineligible.
      case 'displayLimit2':
        await _waitForConfig(
          tester,
          (c) => _filteredIds(c).contains(_surveyId),
          what: 'survey eligible after fresh sync',
        );

        await _trigger(tester);
        var config = await _waitForDisplays(tester, 1);
        expect(_filteredIds(config), contains(_surveyId));
        await _closeSurvey(tester);

        await _trigger(tester);
        config = await _waitForDisplays(tester, 2);
        expect(
          _filteredIds(config),
          isNot(contains(_surveyId)),
          reason: 'at displayLimit the survey must drop out',
        );
        await _closeSurvey(tester);

        await _trigger(tester);
        await tester.pump(const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(_displays(await _storedConfig()).length, 2);

      // Survey: recontactDays >= 1 (survey-level). Expect: shows once;
      // after close the recontact window excludes it.
      case 'recontactDays':
        await _waitForConfig(
          tester,
          (c) => _filteredIds(c).contains(_surveyId),
          what: 'survey eligible after fresh sync',
        );

        await _trigger(tester);
        await _waitForDisplays(tester, 1);
        await _closeSurvey(tester);

        final config = await _waitForConfig(
          tester,
          (c) => !_filteredIds(c).contains(_surveyId),
          what: 'recontact window to exclude the survey',
        );
        expect(
          (((config['user'] as Map)['data'] as Map)['lastDisplayAt']),
          isNotNull,
        );

      // Survey: displayPercentage set to a mid value (e.g. 50). Expect:
      // stays eligible, but across many triggers some are skipped and some
      // shown. Statistical, so only sanity-checked.
      case 'displayPercentage':
        await _waitForConfig(
          tester,
          (c) => _filteredIds(c).contains(_surveyId),
          what: 'survey eligible after fresh sync',
        );

        var shown = 0;
        for (var i = 0; i < 12; i++) {
          final before = _displays(await _storedConfig()).length;
          await _trigger(tester);
          await tester.pump(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(seconds: 2));
          final after = _displays(await _storedConfig()).length;
          if (after > before) {
            shown++;
            await _closeSurvey(tester);
          }
        }
        // 12 rolls at 50%: 0 or 12 each have p ≈ 0.02% — treat as failure.
        expect(shown, greaterThan(0), reason: 'never shown across 12 rolls');
        expect(shown, lessThan(12), reason: 'never skipped across 12 rolls');

      // Survey: segment WITH filters. Expect: anonymous session never sees
      // it; it is not in filteredSurveys and a trigger shows nothing.
      case 'segmentAnonymous':
        final config = await _waitForConfig(
          tester,
          (c) => (c['workspace'] != null),
          what: 'workspace synced',
        );
        expect(_filteredIds(config), isNot(contains(_surveyId)));

        await _trigger(tester);
        await tester.pump(const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(_displays(await _storedConfig()), isEmpty);

      // Survey: segment without filters, respondMultiple. Identifies the
      // user, asserts the segment branch the backend takes (matched →
      // eligible; unmatched → nothing), then logs out and asserts the
      // anonymous refilter restores eligibility.
      case 'segmentIdentified':
        // Anonymous baseline: with a filtered segment the survey must be
        // hidden; without filters it must be eligible.
        await _waitForConfig(
          tester,
          (c) => c['workspace'] != null,
          what: 'workspace synced',
        );

        await _tapButton(tester, 'Set userId');
        var config = await _waitForConfig(
          tester,
          (c) =>
              ((c['user'] as Map)['data'] as Map)['userId'] ==
              'playground-user',
          what: 'identity flush',
        );
        final segments =
            (((config['user'] as Map)['data'] as Map)['segments'] as List)
                .cast<String>();
        debugPrint(
          'QA identified segments=$segments '
          'filtered=${_filteredIds(config)}',
        );
        if (segments.isEmpty) {
          expect(
            _filteredIds(config),
            isEmpty,
            reason: 'identified with no matched segments sees nothing',
          );
          await _trigger(tester);
          await tester.pump(const Duration(seconds: 3));
          await Future<void>.delayed(const Duration(seconds: 3));
          expect(_displays(await _storedConfig()), isEmpty);
        } else {
          expect(
            _filteredIds(config),
            contains(_surveyId),
            reason: 'identified user matched the survey segment',
          );
          await _trigger(tester);
          await _waitForDisplays(tester, 1);
          await _closeSurvey(tester);
        }

        await _tapButton(tester, 'Logout');
        config = await _waitForConfig(
          tester,
          (c) => ((c['user'] as Map)['data'] as Map)['userId'] == null,
          what: 'logout teardown',
        );
        // After logout the anonymous refilter applies: a segment WITH
        // filters hides the survey, one without filters restores it.
        final rawSurvey =
            (((config['workspace'] as Map)['data'] as Map)['surveys'] as List)
                .cast<Map<String, dynamic>>()
                .firstWhere((s) => s['id'] == _surveyId);
        final segment = rawSurvey['segment'] as Map?;
        final segmentHasFilters =
            segment?['hasFilters'] == true ||
            (segment?['filters'] as List?)?.isNotEmpty == true;
        debugPrint(
          'QA post-logout segmentHasFilters=$segmentHasFilters '
          'filtered=${_filteredIds(config)}',
        );
        expect(
          _filteredIds(config),
          segmentHasFilters ? isNot(contains(_surveyId)) : contains(_surveyId),
          reason: segmentHasFilters
              ? 'segment-filtered survey must drop after logout'
              : 'anonymous refilter restores the unfiltered survey',
        );

      default:
        fail('unknown SCENARIO "$_scenario"');
    }
  });
}
