import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/survey_script_url.dart';

void main() {
  group('getSurveyScriptUrl', () {
    test('host only', () {
      expect(
        getSurveyScriptUrl('https://app.formbricks.com'),
        'https://app.formbricks.com/js/surveys.umd.cjs',
      );
    });

    test('preserves an existing path', () {
      expect(
        getSurveyScriptUrl('https://x.com/foo'),
        'https://x.com/foo/js/surveys.umd.cjs',
      );
    });

    test('trailing slash is not doubled', () {
      expect(
        getSurveyScriptUrl('https://x.com/foo/'),
        'https://x.com/foo/js/surveys.umd.cjs',
      );
    });

    test('http with explicit port', () {
      expect(
        getSurveyScriptUrl('http://localhost:3000'),
        'http://localhost:3000/js/surveys.umd.cjs',
      );
    });

    test('strips query and fragment', () {
      expect(
        getSurveyScriptUrl('https://x.com/a?b=1#c'),
        'https://x.com/a/js/surveys.umd.cjs',
      );
    });

    test('non-http(s) scheme → null', () {
      expect(getSurveyScriptUrl('ftp://x.com'), isNull);
    });

    test('null → null', () => expect(getSurveyScriptUrl(null), isNull));
    test('empty → null', () => expect(getSurveyScriptUrl(''), isNull));

    test('hostless → null', () {
      expect(getSurveyScriptUrl('https://'), isNull);
    });

    test('scheme-less string → null', () {
      expect(getSurveyScriptUrl('app.formbricks.com'), isNull);
    });
  });
}
