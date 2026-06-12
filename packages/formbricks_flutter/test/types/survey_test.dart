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
      'displayOption': 'displaySome',
      'displayLimit': 2,
      'recontactDays': 7,
      'displayPercentage': 50.5,
      'segment': {'id': 'seg_1', 'hasFilters': true},
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
      expect(survey.displayOption, 'displaySome');
      expect(survey.displayLimit, 2);
      expect(survey.recontactDays, 7);
      expect(survey.displayPercentage, 50.5);
      expect(survey.segment?.id, 'seg_1');
      expect(survey.segment?.hasFilters, isTrue);
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
      expect(survey.displayOption, isNull);
      expect(survey.displayLimit, isNull);
      expect(survey.recontactDays, isNull);
      expect(survey.displayPercentage, isNull);
      expect(survey.segment, isNull);
    });

    test('integral displayLimit/recontactDays survive a double encoding', () {
      // JSON decoders may produce doubles for whole numbers.
      final survey = TSurvey.fromJson({
        'id': 's',
        'displayLimit': 2.0,
        'recontactDays': 7.0,
      });
      expect(survey.displayLimit, 2);
      expect(survey.recontactDays, 7);
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

  group('TSurveySegment', () {
    TSurveySegment? parse(Map<String, dynamic> segment) =>
        TSurvey.fromJson({'id': 's', 'segment': segment}).segment;

    test('boolean hasFilters is taken verbatim', () {
      expect(parse({'id': 'a', 'hasFilters': true})?.hasFilters, isTrue);
      expect(parse({'id': 'a', 'hasFilters': false})?.hasFilters, isFalse);
    });

    test('legacy non-empty filters array → hasFilters', () {
      final segment = parse({
        'id': 'a',
        'filters': [
          {'connector': null},
        ],
      });
      expect(segment?.id, 'a');
      expect(segment?.hasFilters, isTrue);
    });

    test('legacy empty filters array → no filters', () {
      expect(parse({'id': 'a', 'filters': <dynamic>[]})?.hasFilters, isFalse);
    });

    test('non-list filters value → no filters', () {
      expect(parse({'id': 'a', 'filters': 'bogus'})?.hasFilters, isFalse);
    });

    test('a missing id stays null', () {
      expect(parse({'hasFilters': true})?.id, isNull);
    });
  });
}
