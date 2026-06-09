import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/utils.dart';
import 'package:formbricks_flutter/src/types/survey.dart';

TSurvey _survey(
  List<Map<String, dynamic>> languages, {
  Map<String, dynamic>? styling,
}) =>
    TSurvey.fromJson({
      'id': 's',
      'languages': languages,
      if (styling != null) 'styling': styling,
    });

void main() {
  final langs = [
    {
      'default': true,
      'enabled': true,
      'language': {'code': 'en', 'alias': null},
    },
    {
      'default': false,
      'enabled': true,
      'language': {'code': 'de', 'alias': 'german'},
    },
    {
      'default': false,
      'enabled': false,
      'language': {'code': 'fr', 'alias': null},
    },
  ];

  group('getLanguageCode', () {
    test('null language → default', () {
      expect(getLanguageCode(_survey(langs), null), 'default');
    });
    test('default-language match → default', () {
      expect(getLanguageCode(_survey(langs), 'en'), 'default');
    });
    test('alias match → code', () {
      expect(getLanguageCode(_survey(langs), 'german'), 'de');
    });
    test('enabled non-default → code', () {
      expect(getLanguageCode(_survey(langs), 'de'), 'de');
    });
    test('case-insensitive match', () {
      expect(getLanguageCode(_survey(langs), 'DE'), 'de');
    });
    test('case-insensitive payload code match', () {
      expect(
        getLanguageCode(
          _survey([
            {
              'default': true,
              'enabled': true,
              'language': {'code': 'EN'},
            },
            {
              'default': false,
              'enabled': true,
              'language': {'code': 'DE'},
            },
          ]),
          'de',
        ),
        'DE',
      );
    });
    test('disabled language → null', () {
      expect(getLanguageCode(_survey(langs), 'fr'), isNull);
    });
    test('unknown language → null', () {
      expect(getLanguageCode(_survey(langs), 'es'), isNull);
    });
  });

  group('getDefaultLanguageCode', () {
    test('returns the default code', () {
      expect(getDefaultLanguageCode(_survey(langs)), 'en');
    });
    test('null when no default', () {
      expect(
        getDefaultLanguageCode(
          _survey([
            {
              'default': false,
              'enabled': true,
              'language': {'code': 'en'},
            },
          ]),
        ),
        isNull,
      );
    });
  });

  group('getStyling', () {
    test('overwrite disabled → workspace styling', () {
      final settings = {
        'styling': {'allowStyleOverwrite': false, 'brandColor': 'ws'},
      };
      final survey = _survey(
        const [],
        styling: {'overwriteThemeStyling': true, 'brandColor': 'survey'},
      );
      expect(getStyling(settings, survey), {
        'allowStyleOverwrite': false,
        'brandColor': 'ws',
      });
    });

    test('overwrite enabled + survey opts out → workspace styling', () {
      final settings = {
        'styling': {'allowStyleOverwrite': true, 'brandColor': 'ws'},
      };
      final survey = _survey(
        const [],
        styling: {'overwriteThemeStyling': false},
      );
      expect(getStyling(settings, survey), {
        'allowStyleOverwrite': true,
        'brandColor': 'ws',
      });
    });

    test('overwrite enabled + survey overrides → survey styling', () {
      final settings = {
        'styling': {'allowStyleOverwrite': true},
      };
      final survey = _survey(
        const [],
        styling: {'overwriteThemeStyling': true, 'brandColor': 'survey'},
      );
      expect(getStyling(settings, survey), {
        'overwriteThemeStyling': true,
        'brandColor': 'survey',
      });
    });

    test('overwrite enabled + survey has no styling → workspace styling', () {
      final settings = {
        'styling': {'allowStyleOverwrite': true, 'brandColor': 'ws'},
      };
      expect(getStyling(settings, _survey(const [])), {
        'allowStyleOverwrite': true,
        'brandColor': 'ws',
      });
    });

    test('missing workspace styling → empty map', () {
      expect(getStyling(const {}, _survey(const [])), <String, dynamic>{});
    });
  });
}
