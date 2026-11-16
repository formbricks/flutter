/// The SDK golden journey, shared by every Formbricks SDK: set up, identify
/// the user, set plan = pro, track `qa-action`, then answer the survey that
/// action shows (NPS 9, the feedback text, Finish, close).
///
/// CI runs it through e2e/flutter/run-journey.sh against the server seeded by
/// e2e/server/seed.sh, then asserts the stored response through the V1 API.
/// Inputs come as dart-defines: APP_URL and WORKSPACE_ID (read by the app,
/// which sets up on launch), E2E_USER_ID and E2E_FEEDBACK.
///
/// The Flutter widgets are driven with Patrol finders. The survey is a web
/// page in the SDK's native WebView: `$.platform.mobile` (UiAutomator /
/// XCUITest) checks what the user sees, and the answers go in through the
/// page's DOM, as Espresso-Web does on Android and Playwright on JS. Native
/// taps can't answer it reliably: on Android the WebView reports stale
/// accessibility bounds after a card re-renders, so taps land beside the
/// button; on iOS an XCUITest tap reaches the Flutter platform view but the
/// page never registers it (a real finger does).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/formbricks.dart';
import 'package:formbricks_playground/main.dart';
import 'package:patrol/patrol.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _userId = String.fromEnvironment('E2E_USER_ID');
const String _feedback = String.fromEnvironment('E2E_FEEDBACK');
const String _actionKey = 'qa-action';

// What the user sees, through the native accessibility tree.
final CompoundSelector _npsNineVisible = Selector(text: '9');
final CompoundSelector _thanksVisible = Selector(text: 'Thanks!');

// The survey DOM, shared by every SDK's journey (harness-howto.md).
const String _npsNine = 'input[name="qa_nps"][value="9"]';
const String _firstCardButton =
    '#questionCard-0 [data-fb-part="button-primary"]';
const String _feedbackInput = '#qa_feedback-input';
const String _secondCardButton =
    '#questionCard-1 [data-fb-part="button-primary"]';
const String _closeButton = '[data-fb-part="button-close"]';

void main() {
  patrolTest(
    'golden journey: identify, track qa-action, answer the survey',
    config: const PatrolTesterConfig(
      printLogs: true,
      settlePolicy: SettlePolicy.trySettle,
    ),
    ($) async {
      expect(_userId, isNotEmpty, reason: 'pass --dart-define=E2E_USER_ID=…');
      expect(
        _feedback,
        isNotEmpty,
        reason: 'pass --dart-define=E2E_FEEDBACK=…',
      );

      try {
        await _journey($);
      } catch (_) {
        await _dumpNativeTree($);
        rethrow;
      }
    },
  );
}

Future<void> _journey(PatrolIntegrationTester $) async {
  // A retry reuses the app's storage on iOS; start from a clean SDK state.
  await Formbricks.debugClearStoredConfig();
  await $.pumpWidget(const PlaygroundApp());

  // The app sets up on launch from the APP_URL / WORKSPACE_ID dart-defines.
  // The first request through a fresh tunnel can take a while.
  await _waitUntil(
    $,
    () => _text($, kConnectionStatusKey).startsWith('Connected to'),
    timeout: const Duration(seconds: 180),
    what: 'the SDK to set up',
  );

  if (!const bool.fromEnvironment('E2E_EXPERIMENT_ANON')) {
    _step('setUserId($_userId)');
    await $(kUserIdFieldKey).scrollTo().enterText(_userId);
    await $(kSetUserIdButtonKey).scrollTo().tap();
    await $("setUserId('$_userId') -> ok").waitUntilVisible();

    _step('setAttribute(plan, pro)');
    await $(kSetAttributeButtonKey).scrollTo().tap();
    await $("setAttribute('plan', 'pro') -> ok").waitUntilVisible();
  }

  _step('track($_actionKey) until the survey shows');
  await $(kActionFieldKey).scrollTo().enterText(_actionKey);
  await _trackUntilTheSurveyShows($);
  final survey = _SurveyPage($);

  _step('answer the survey');
  await survey.click(_npsNine);
  expect(await survey.eval('${_q(_npsNine)}.checked'), 'true');
  await survey.click(_firstCardButton);
  await survey.type(_feedbackInput, _feedback);
  await survey.click(_secondCardButton);
  // The ending card renders only after the server accepted the response.
  await $.platform.mobile.waitUntilVisible(
    _thanksVisible,
    timeout: const Duration(seconds: 30),
  );

  _step('close the survey');
  await survey.click(_closeButton);
  await _waitUntil(
    $,
    () => find.byType(WebViewWidget).evaluate().isEmpty,
    timeout: const Duration(seconds: 20),
    what: 'the survey to close',
  );
}

/// Taps Track again until the survey shows: an early tap can land before the
/// SDK has the workspace state or the user's segments, and is then ignored.
Future<void> _trackUntilTheSurveyShows(PatrolIntegrationTester $) async {
  final deadline = DateTime.now().add(const Duration(seconds: 180));
  for (var attempt = 1; ; attempt++) {
    await $(kTrackButtonKey).scrollTo().tap();
    _step('track attempt $attempt: ${_text($, kLastTrackKey)}');
    try {
      await $.platform.mobile.waitUntilVisible(
        _npsNineVisible,
        timeout: const Duration(seconds: 15),
      );
      return;
    } on PatrolActionException {
      if (DateTime.now().isAfter(deadline)) rethrow;
    }
  }
}

String _q(String selector) => 'document.querySelector(${jsonEncode(selector)})';

/// The survey page inside the SDK's WebView, driven through its DOM.
class _SurveyPage {
  _SurveyPage(this.$);

  final PatrolIntegrationTester $;

  /// Evaluates [expression] in the survey's WebView (the SDK mounts exactly
  /// one) and returns it as a string.
  Future<String> eval(String expression) async {
    final widget = $.tester.widget<WebViewWidget>(find.byType(WebViewWidget));
    final result = await widget.platform.params.controller
        .runJavaScriptReturningResult('String($expression)');
    // Android returns the string JSON-encoded, iOS as is.
    final text = '$result';
    return text.startsWith('"') ? jsonDecode(text) as String : text;
  }

  /// Waits until [selector] is in the page. Evaluating before the page has
  /// loaded throws on iOS, so errors count as "not yet".
  Future<void> _waitFor(String selector) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (await _exists(selector) != true) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the survey never showed $selector');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Runs [statements] in the page; a script error fails the test with the
  /// page's own message instead of the platform's generic one.
  Future<void> _run(String statements) async {
    final result = await eval(
      '(() => { try { $statements return "ok"; } '
      'catch (e) { return "error: " + e; } })()',
    );
    if (result != 'ok') fail('the survey page script failed: $result');
  }

  Future<bool> _exists(String selector) async {
    try {
      return await eval('!!${_q(selector)}') == 'true';
    } on PlatformException catch (e) {
      _step('page not ready: ${e.message}');
      return false;
    }
  }

  Future<void> click(String selector) async {
    await _waitFor(selector);
    _step('click $selector');
    // The NPS radio is hidden behind its label; clicking the label is what a
    // user's tap does.
    await _run(
      'const el = ${_q(selector)}; (el.closest("label") || el).click();',
    );
  }

  /// Sets the value the way typing does, so the page's input handler sees it.
  Future<void> type(String selector, String text) async {
    await _waitFor(selector);
    _step('type into $selector');
    await _run('''
      const el = ${_q(selector)};
      el.focus();
      Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value")
        .set.call(el, ${jsonEncode(text)});
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));''');
    expect(await eval('${_q(selector)}.value'), text);
  }
}

Future<void> _waitUntil(
  PatrolIntegrationTester $,
  bool Function() condition, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'timed out waiting for $what (status: '
        '${_text($, kConnectionStatusKey)})',
      );
    }
    await $.pump(const Duration(milliseconds: 500));
  }
}

String _text(PatrolIntegrationTester $, Key key) {
  final finder = $(key);
  if (finder.evaluate().isEmpty) return '';
  return finder.text ?? '';
}

void _step(String message) => debugPrint('[golden journey] $message');

/// Prints the native accessibility tree, so a failure can be read from the
/// CI log.
Future<void> _dumpNativeTree(PatrolIntegrationTester $) async {
  try {
    final Object json = Platform.isAndroid
        ? (await $.platform.android.getNativeViews(null)).toJson()
        : (await $.platform.ios.getNativeViews(null)).toJson();
    debugPrint('[golden journey] native tree:');
    _printNodes(jsonDecode(jsonEncode(json)), 0);
  } catch (e) {
    debugPrint('[golden journey] could not read the native tree: $e');
  }
}

void _printNodes(Object? node, int depth) {
  if (node is List) {
    for (final child in node) {
      _printNodes(child, depth);
    }
  } else if (node is Map) {
    final fields = [
      for (final entry in node.entries)
        if (_describeField(entry.value) case final String value)
          '${entry.key}=$value',
    ];
    if (fields.isNotEmpty) debugPrint('${'  ' * depth}${fields.join(' ')}');
    for (final entry in node.entries) {
      if (entry.value is List) _printNodes(entry.value, depth + 1);
    }
  }
}

/// Every set field of a node, so the log shows why a selector missed it
/// (visibility, bounds, class). Empty strings and false flags are noise.
String? _describeField(Object? value) => switch (value) {
  null || false || '' || List() => null,
  Map() => jsonEncode(value),
  _ => '$value',
};
