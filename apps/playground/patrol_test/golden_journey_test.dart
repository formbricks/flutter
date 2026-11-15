/// The SDK golden journey, shared by every Formbricks SDK: set up, identify
/// the user, set plan = pro, track `qa-action`, then answer the survey that
/// action shows (NPS 9, the feedback text, Finish, close).
///
/// CI runs it through e2e/flutter/run-journey.sh against the server seeded by
/// e2e/server/seed.sh, then asserts the stored response through the V1 API.
/// Inputs come as dart-defines: APP_URL and WORKSPACE_ID (read by the app,
/// which sets up on launch), E2E_USER_ID and E2E_FEEDBACK.
///
/// Flutter widgets are driven with Patrol finders; the survey is a web page in
/// the SDK's native WebView, so it is driven through `$.platform.mobile`
/// (UiAutomator on Android, XCUITest on iOS).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/formbricks.dart';
import 'package:formbricks_playground/main.dart';
import 'package:patrol/patrol.dart';

const String _userId = String.fromEnvironment('E2E_USER_ID');
const String _feedback = String.fromEnvironment('E2E_FEEDBACK');
const String _actionKey = 'qa-action';

// The survey's DOM, as the accessibility tree exposes it. Each step lists the
// selectors that may match on either platform; the first one found is used.
final List<CompoundSelector> _npsNine = [Selector(text: '9')];
final List<CompoundSelector> _next = [Selector(text: 'Next')];
final List<CompoundSelector> _finish = [Selector(text: 'Finish')];
final List<CompoundSelector> _thanks = [Selector(text: 'Thanks!')];
final List<CompoundSelector> _feedbackInput = [
  // Android WebView exposes the input's HTML id as its resource name.
  MobileSelector(
    android: const AndroidSelector(resourceName: 'qa_feedback-input'),
    ios: const IOSSelector(text: 'Type your answer'),
  ),
  Selector(text: 'Type your answer'),
];
// Never a bare Selector(contentDescription: …): its iOS side would have no
// condition and match any element.
final List<CompoundSelector> _close = [
  Selector(text: 'Close survey'),
  MobileSelector(
    android: const AndroidSelector(contentDescription: 'Close survey'),
    ios: const IOSSelector(label: 'Close survey'),
  ),
];

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
  await _waitUntil(
    $,
    () => _text($, kConnectionStatusKey).startsWith('Connected to'),
    timeout: const Duration(seconds: 60),
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

  _step('answer the survey');
  await _tapFirst($, _npsNine);
  await _tapFirst($, _next);
  final input = await _waitForFirst($, _feedbackInput);
  await $.platform.mobile.enterText(
    input,
    text: _feedback,
    keyboardBehavior: KeyboardBehavior.alternative,
  );
  await _tapFirst($, _finish);
  // The ending card renders only after the server accepted the response.
  await _waitForFirst($, _thanks, timeout: const Duration(seconds: 30));

  _step('close the survey');
  await _tapFirst($, _close);
  await _waitUntilGone($, _thanks);
}

/// Taps Track again until the survey shows: an early tap can land before the
/// SDK has the workspace state or the user's segments, and is then ignored.
Future<void> _trackUntilTheSurveyShows(PatrolIntegrationTester $) async {
  final deadline = DateTime.now().add(const Duration(seconds: 180));
  for (var attempt = 1; ; attempt++) {
    await $(kTrackButtonKey).scrollTo().tap();
    _step('track attempt $attempt: ${_text($, kLastTrackKey)}');
    try {
      await _waitForFirst($, _npsNine, timeout: const Duration(seconds: 15));
      return;
    } on _NotFound {
      if (DateTime.now().isAfter(deadline)) rethrow;
    }
  }
}

Future<void> _tapFirst(
  PatrolIntegrationTester $,
  List<CompoundSelector> candidates,
) async {
  final selector = await _waitForFirst($, candidates);
  await $.platform.mobile.tap(selector);
}

/// Returns the first of [candidates] that becomes visible within [timeout].
Future<CompoundSelector> _waitForFirst(
  PatrolIntegrationTester $,
  List<CompoundSelector> candidates, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  do {
    for (final candidate in candidates) {
      if (await _isVisible($, candidate)) return candidate;
    }
  } while (DateTime.now().isBefore(deadline));
  throw _NotFound(candidates);
}

Future<void> _waitUntilGone(
  PatrolIntegrationTester $,
  List<CompoundSelector> candidates,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (true) {
    var visible = false;
    for (final candidate in candidates) {
      visible = visible || await _isVisible($, candidate);
    }
    if (!visible) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('the survey is still open after closing it');
    }
  }
}

Future<bool> _isVisible(
  PatrolIntegrationTester $,
  CompoundSelector selector,
) async {
  try {
    await $.platform.mobile.waitUntilVisible(
      selector,
      timeout: const Duration(seconds: 2),
    );
    return true;
  } on PatrolActionException {
    return false;
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

/// Prints the native accessibility tree, so a selector that did not match
/// can be fixed from the CI log.
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

class _NotFound implements Exception {
  _NotFound(this.candidates);

  final List<CompoundSelector> candidates;

  @override
  String toString() =>
      'none of these became visible: '
      '${candidates.map(_describe).join(' | ')}';

  static String _describe(CompoundSelector s) => switch (s) {
    Selector() =>
      'Selector(text: ${s.text}, contentDescription: ${s.contentDescription})',
    _ => s.runtimeType.toString(),
  };
}
