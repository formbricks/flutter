import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/types/survey.dart';
import 'package:formbricks_flutter/src/widgets/survey_html.dart';

TSurvey _survey([Map<String, dynamic>? extra]) => TSurvey.fromJson({
      'id': 's1',
      'questions': [
        {'headline': 'Hi'},
      ],
      ...?extra,
    });

SurveyHtmlOptions _opts({
  TSurvey? survey,
  String appUrl = 'https://app.formbricks.com',
  Map<String, dynamic>? styling,
  String? placement,
  bool? clickOutside,
  String? overlay,
  bool branding = true,
  String languageCode = 'default',
  String? contactId,
}) =>
    SurveyHtmlOptions(
      survey: survey ?? _survey(),
      appUrl: appUrl,
      workspaceId: 'wsp_1',
      isBrandingEnabled: branding,
      languageCode: languageCode,
      styling: styling,
      placement: placement,
      clickOutside: clickOutside,
      overlay: overlay,
      contactId: contactId,
    );

void main() {
  group('buildSurveyHtml', () {
    test(
        'includes script url, renderSurvey, all 5 callbacks, shim & window.open',
        () {
      final html = buildSurveyHtml(_opts());
      expect(html, contains('https://app.formbricks.com/js/surveys.umd.cjs'));
      expect(html, contains('const runtime = window.formbricksSurveys'));
      expect(html, contains('runtime.renderSurvey'));
      expect(html, contains('onDisplayCreated'));
      expect(html, contains('onResponseCreated'));
      expect(html, contains('onClose'));
      expect(html, contains('getSetIsResponseSendingFinished'));
      expect(html, contains('getSetIsError'));
      expect(html, contains('window.ReactNativeWebView = { postMessage'));
      expect(html, contains('window.open = function'));
      expect(html, contains('Formbricks.postMessage'));
      expect(html, contains('"isWebEnvironment":false'));
    });

    test('script and runtime failures close the survey route', () {
      final html = buildSurveyHtml(_opts());
      const timeoutClose =
          "closeOnError('Timed out loading Formbricks Surveys library.')";

      expect(html, contains('function closeOnError'));
      expect(html, contains('let closedForError = false'));
      expect(html, contains('if (!closedForError) loadSurvey()'));
      expect(html, contains('postFormbricksMessage({ onClose: true })'));
      expect(html, contains("typeof runtime.renderSurvey !== 'function'"));
      expect(html, contains('script.onerror = (error) =>'));
      expect(html, contains('scriptLoadTimeout'));
      expect(html, contains(timeoutClose));
      expect(
        html,
        contains("closeOnError('Failed to render Formbricks survey:'"),
      );
    });

    test('console bridge forwards multiple log arguments', () {
      final html = buildSurveyHtml(_opts());

      expect(html, contains('(...logs) => consoleLog'));
      expect(html, contains("logs.map(stringifyLog).join(' ')"));
    });

    test('embeds the full survey JSON incl. unmodelled fields', () {
      final html =
          buildSurveyHtml(_opts(survey: _survey({'customField': 'XYZ'})));
      expect(html, contains('customField'));
      expect(html, contains('XYZ'));
    });

    test('omits null styling / placement / contactId keys', () {
      final html = buildSurveyHtml(_opts());
      expect(html, isNot(contains('"styling"')));
      expect(html, isNot(contains('"placement"')));
      expect(html, isNot(contains('"contactId"')));
    });

    test('passes through resolved settings-derived options', () {
      final html = buildSurveyHtml(
        _opts(
          styling: {'brandColor': 'x'},
          placement: 'center',
          clickOutside: true,
          overlay: 'dark',
          contactId: 'c1',
        ),
      );
      expect(html, contains('"placement":"center"'));
      expect(html, contains('"overlay":"dark"'));
      expect(html, contains('"clickOutside":true'));
      expect(html, contains('"isBrandingEnabled":true'));
      expect(html, contains('"contactId":"c1"'));
      expect(html, contains('"styling":{"brandColor":"x"}'));
    });

    test('neutralizes a </script> breakout in survey content', () {
      final html = buildSurveyHtml(
        _opts(
          survey: _survey({
            'headline': '</script><img src=x onerror=alert(1)>',
          }),
        ),
      );
      // The raw breakout sequence must not survive.
      expect(html.contains('</script><img'), isFalse);
      // The opening <img tag must be escaped (no raw "<img" anywhere).
      expect(html.contains('<img src=x'), isFalse);
      // The (now-inert) content text still survives in escaped form, and the
      // unicode-escape prefix is present.
      expect(html.contains('img src=x onerror=alert(1)'), isTrue);
      final escapedLt = '${String.fromCharCode(0x5c)}u003c';
      expect(html.contains('${escapedLt}img'), isTrue);
    });

    test('invalid appUrl → empty doc with no renderSurvey', () {
      final html = buildSurveyHtml(_opts(appUrl: 'ftp://x.com'));
      expect(html, isNot(contains('renderSurvey')));
      expect(html, contains('Formbricks WebView Survey'));
    });
  });
}
