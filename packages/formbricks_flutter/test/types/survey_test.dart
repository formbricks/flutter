import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/types/survey.dart';

Map<String, dynamic> _fullJson() => {
      'id': 's1',
      'delay': 3,
      // An unmodelled field that must survive the lossless round-trip.
      'questions': [
        {'id': 'q1', 'type': 'openText'},
      ],
      'triggers': [
        {
          'actionClass': {'name': 'act1'},
        },
        {
          'actionClass': {'name': 'act2'},
        },
      ],
      'languages': [
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
      ],
      'styling': {
        'overwriteThemeStyling': true,
        'brandColor': {'light': '#fff'},
      },
      'projectOverwrites': {
        'placement': 'center',
        'clickOutsideClose': false,
        'overlay': 'dark',
      },
    };

void main() {
  group('TSurvey', () {
    test('parses typed fields', () {
      final survey = TSurvey.fromJson(_fullJson());
      expect(survey.id, 's1');
      expect(survey.delay, 3);
      expect(
        survey.triggers.map((t) => t.actionClass.name).toList(),
        ['act1', 'act2'],
      );
      expect(survey.languages.length, 2);
      expect(survey.languages[0].isDefault, isTrue);
      expect(survey.languages[1].language.code, 'de');
      expect(survey.languages[1].language.alias, 'german');
      expect(survey.styling?['overwriteThemeStyling'], true);
      expect(survey.projectOverwrites?.placement, 'center');
      expect(survey.projectOverwrites?.clickOutsideClose, false);
      expect(survey.projectOverwrites?.overlay, 'dark');
      expect(survey.isMultiLanguage, isTrue);
    });

    test('toJson returns the raw map verbatim (lossless)', () {
      final json = _fullJson();
      final survey = TSurvey.fromJson(json);
      expect(survey.toJson(), same(json));
      expect((survey.toJson()['questions'] as List).first['id'], 'q1');
    });

    test('defaults when optional fields are absent', () {
      final survey = TSurvey.fromJson({'id': 's2'});
      expect(survey.delay, 0);
      expect(survey.triggers, isEmpty);
      expect(survey.languages, isEmpty);
      expect(survey.styling, isNull);
      expect(survey.projectOverwrites, isNull);
      expect(survey.isMultiLanguage, isFalse);
    });

    test('a single language is not multi-language', () {
      final survey = TSurvey.fromJson({
        'id': 's3',
        'languages': [
          {
            'default': true,
            'enabled': true,
            'language': {'code': 'en'},
          },
        ],
      });
      expect(survey.isMultiLanguage, isFalse);
      expect(survey.languages.single.language.alias, isNull);
    });
  });
}
