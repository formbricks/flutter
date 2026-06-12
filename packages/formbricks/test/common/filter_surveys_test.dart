import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/filter_surveys.dart';
import 'package:formbricks/src/common/logger.dart';
import 'package:formbricks/src/types/config.dart';
import 'package:formbricks/src/types/survey.dart';

Map<String, dynamic> _survey(
  String id, {
  Object? displayOption = 'respondMultiple',
  int? displayLimit,
  int? recontactDays,
  Map<String, dynamic>? segment,
}) =>
    {
      'id': id,
      if (displayOption != null) 'displayOption': displayOption,
      if (displayLimit != null) 'displayLimit': displayLimit,
      if (recontactDays != null) 'recontactDays': recontactDays,
      if (segment != null) 'segment': segment,
    };

TWorkspaceState _workspace(
  List<Object?> surveys, {
  Map<String, dynamic> settings = const {},
}) =>
    TWorkspaceState(
      expiresAt: DateTime(2100),
      data: TWorkspaceData(surveys: surveys, settings: settings),
    );

TUserState _user({
  String? userId,
  List<String> segments = const [],
  List<TDisplay> displays = const [],
  List<String> responses = const [],
  DateTime? lastDisplayAt,
}) =>
    TUserState(
      expiresAt: null,
      data: TUserData(
        userId: userId,
        segments: segments,
        displays: displays,
        responses: responses,
        lastDisplayAt: lastDisplayAt,
      ),
    );

List<String> _ids(List<TSurvey> surveys) => surveys.map((s) => s.id).toList();

void main() {
  final now = DateTime(2026, 6, 10, 12);
  DateTime fixedNow() => now;

  setUp(Logger.resetInstance);

  group('diffInDays', () {
    test('same instant → 0', () {
      expect(diffInDays(now, now), 0);
    });

    test('less than a day → 0', () {
      expect(
        diffInDays(now, now.subtract(const Duration(hours: 23, minutes: 59))),
        0,
      );
    });

    test('exactly one day → 1', () {
      expect(diffInDays(now, now.subtract(const Duration(days: 1))), 1);
    });

    test('partial days floor down', () {
      expect(
        diffInDays(now, now.subtract(const Duration(days: 2, hours: 12))),
        2,
      );
    });

    test('is direction-agnostic', () {
      final other = now.add(const Duration(days: 3));
      expect(diffInDays(now, other), 3);
      expect(diffInDays(other, now), 3);
    });
  });

  group('surveyHasSegmentFilters', () {
    TSurvey parse(Map<String, dynamic> json) => TSurvey.fromJson(json);

    test('no segment → false', () {
      expect(surveyHasSegmentFilters(parse({'id': 's'})), isFalse);
    });

    test('boolean hasFilters is taken verbatim', () {
      expect(
        surveyHasSegmentFilters(
          parse({
            'id': 's',
            'segment': {'id': 'seg', 'hasFilters': true},
          }),
        ),
        isTrue,
      );
      expect(
        surveyHasSegmentFilters(
          parse({
            'id': 's',
            'segment': {'id': 'seg', 'hasFilters': false},
          }),
        ),
        isFalse,
      );
    });

    test('legacy non-empty filters array → true', () {
      expect(
        surveyHasSegmentFilters(
          parse({
            'id': 's',
            'segment': {
              'id': 'seg',
              'filters': [
                {'connector': null},
              ],
            },
          }),
        ),
        isTrue,
      );
    });

    test('legacy empty filters array → false', () {
      expect(
        surveyHasSegmentFilters(
          parse({
            'id': 's',
            'segment': {'id': 'seg', 'filters': <dynamic>[]},
          }),
        ),
        isFalse,
      );
    });

    test('non-list filters value → false', () {
      expect(
        surveyHasSegmentFilters(
          parse({
            'id': 's',
            'segment': {'id': 'seg', 'filters': 'bogus'},
          }),
        ),
        isFalse,
      );
    });
  });

  group('filterSurveys — displayOption stage', () {
    final display = TDisplay(surveyId: 's1', createdAt: now);

    test('respondMultiple is always kept', () {
      final result = filterSurveys(
        _workspace([_survey('s1')]),
        _user(displays: [display], responses: ['s1']),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('displayOnce is dropped once a display exists', () {
      final workspace = _workspace([
        _survey('s1', displayOption: 'displayOnce'),
      ]);
      expect(
        _ids(
          filterSurveys(workspace, _user(displays: [display]), now: fixedNow),
        ),
        isEmpty,
      );
      expect(
        _ids(filterSurveys(workspace, _user(), now: fixedNow)),
        ['s1'],
      );
    });

    test('displayOnce ignores displays of other surveys', () {
      final result = filterSurveys(
        _workspace([_survey('s1', displayOption: 'displayOnce')]),
        _user(displays: [TDisplay(surveyId: 'other', createdAt: now)]),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('displayMultiple is dropped once a response exists', () {
      final workspace = _workspace([
        _survey('s1', displayOption: 'displayMultiple'),
      ]);
      expect(
        _ids(filterSurveys(workspace, _user(responses: ['s1']), now: fixedNow)),
        isEmpty,
      );
      // Displays alone don't matter for displayMultiple.
      expect(
        _ids(
          filterSurveys(workspace, _user(displays: [display]), now: fixedNow),
        ),
        ['s1'],
      );
    });

    test('displaySome without a limit is kept', () {
      final result = filterSurveys(
        _workspace([_survey('s1', displayOption: 'displaySome')]),
        _user(displays: [display, display], responses: ['s1']),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('displaySome with a limit is dropped once a response exists', () {
      final result = filterSurveys(
        _workspace([
          _survey('s1', displayOption: 'displaySome', displayLimit: 5),
        ]),
        _user(responses: ['s1']),
        now: fixedNow,
      );
      expect(_ids(result), isEmpty);
    });

    test('displaySome keeps below the displayLimit and drops at it', () {
      final workspace = _workspace([
        _survey('s1', displayOption: 'displaySome', displayLimit: 2),
      ]);
      expect(
        _ids(
          filterSurveys(workspace, _user(displays: [display]), now: fixedNow),
        ),
        ['s1'],
        reason: '1 display < limit 2',
      );
      expect(
        _ids(
          filterSurveys(
            workspace,
            _user(displays: [display, display]),
            now: fixedNow,
          ),
        ),
        isEmpty,
        reason: '2 displays == limit 2',
      );
    });

    test('an unknown displayOption excludes the survey without throwing', () {
      final result = filterSurveys(
        _workspace([
          _survey('bad', displayOption: 'weird'),
          _survey('good'),
        ]),
        _user(),
        now: fixedNow,
      );
      expect(_ids(result), ['good']);
    });

    test('a missing displayOption excludes the survey without throwing', () {
      final result = filterSurveys(
        _workspace([
          _survey('bad', displayOption: null),
          _survey('good'),
        ]),
        _user(),
        now: fixedNow,
      );
      expect(_ids(result), ['good']);
    });
  });

  group('filterSurveys — recontactDays stage', () {
    test('no prior display → kept regardless of recontactDays', () {
      final result = filterSurveys(
        _workspace(
          [_survey('s1', recontactDays: 30)],
          settings: {'recontactDays': 30},
        ),
        _user(),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('survey-level recontactDays boundary: diff == days is kept', () {
      final result = filterSurveys(
        _workspace([_survey('s1', recontactDays: 3)]),
        _user(lastDisplayAt: now.subtract(const Duration(days: 3))),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('survey-level recontactDays: diff < days is dropped', () {
      final result = filterSurveys(
        _workspace([_survey('s1', recontactDays: 3)]),
        _user(lastDisplayAt: now.subtract(const Duration(days: 2, hours: 23))),
        now: fixedNow,
      );
      expect(_ids(result), isEmpty);
    });

    test('recontactDays of 0 shows again immediately', () {
      final result = filterSurveys(
        _workspace([_survey('s1', recontactDays: 0)]),
        _user(lastDisplayAt: now.subtract(const Duration(hours: 1))),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('survey-level value takes precedence over workspace settings', () {
      final result = filterSurveys(
        _workspace(
          [_survey('s1', recontactDays: 1)],
          settings: {'recontactDays': 10},
        ),
        _user(lastDisplayAt: now.subtract(const Duration(days: 2))),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('falls back to workspace settings.recontactDays', () {
      final workspace = _workspace(
        [_survey('s1')],
        settings: {'recontactDays': 5},
      );
      expect(
        _ids(
          filterSurveys(
            workspace,
            _user(lastDisplayAt: now.subtract(const Duration(days: 5))),
            now: fixedNow,
          ),
        ),
        ['s1'],
      );
      expect(
        _ids(
          filterSurveys(
            workspace,
            _user(lastDisplayAt: now.subtract(const Duration(days: 4))),
            now: fixedNow,
          ),
        ),
        isEmpty,
      );
    });

    test('non-num workspace recontactDays is ignored, not thrown', () {
      for (final garbage in ['7', true]) {
        final result = filterSurveys(
          _workspace([_survey('s1')], settings: {'recontactDays': garbage}),
          _user(lastDisplayAt: now.subtract(const Duration(minutes: 1))),
          now: fixedNow,
        );
        expect(_ids(result), ['s1'], reason: 'garbage value: $garbage');
      }
    });

    test('neither survey nor workspace recontactDays set → kept', () {
      final result = filterSurveys(
        _workspace([_survey('s1')]),
        _user(lastDisplayAt: now.subtract(const Duration(minutes: 1))),
        now: fixedNow,
      );
      expect(_ids(result), ['s1']);
    });

    test('defaults to clock.now when no now is injected', () {
      withClock(Clock.fixed(now), () {
        final workspace = _workspace([_survey('s1', recontactDays: 3)]);
        expect(
          _ids(
            filterSurveys(
              workspace,
              _user(lastDisplayAt: now.subtract(const Duration(days: 3))),
            ),
          ),
          ['s1'],
        );
        expect(
          _ids(
            filterSurveys(
              workspace,
              _user(lastDisplayAt: now.subtract(const Duration(days: 2))),
            ),
          ),
          isEmpty,
        );
      });
    });
  });

  group('filterSurveys — segment stage', () {
    final unfiltered = _survey('plain');
    final filtered = _survey(
      'gated',
      segment: {'id': 'seg_a', 'hasFilters': true},
    );

    test('anonymous: segment-filtered surveys are dropped, others kept', () {
      final result = filterSurveys(
        _workspace([unfiltered, filtered]),
        _user(),
        now: fixedNow,
      );
      expect(_ids(result), ['plain']);
    });

    test('anonymous: legacy filters shapes are honored', () {
      final result = filterSurveys(
        _workspace([
          _survey(
            'legacy-gated',
            segment: {
              'id': 'seg_a',
              'filters': [
                {'connector': null},
              ],
            },
          ),
          _survey(
            'legacy-empty',
            segment: {'id': 'seg_b', 'filters': <dynamic>[]},
          ),
        ]),
        _user(),
        now: fixedNow,
      );
      expect(_ids(result), ['legacy-empty']);
    });

    test('an empty-string userId is treated as anonymous', () {
      final result = filterSurveys(
        _workspace([unfiltered, filtered]),
        _user(userId: ''),
        now: fixedNow,
      );
      expect(_ids(result), ['plain']);
    });

    test('identified with no matched segments → nothing is eligible', () {
      final result = filterSurveys(
        _workspace([unfiltered, filtered]),
        _user(userId: 'u1'),
        now: fixedNow,
      );
      expect(result, isEmpty);
    });

    test('identified: only surveys whose segment id matched are kept', () {
      final result = filterSurveys(
        _workspace([
          filtered,
          _survey('other', segment: {'id': 'seg_b', 'hasFilters': true}),
          unfiltered,
        ]),
        _user(userId: 'u1', segments: ['seg_a']),
        now: fixedNow,
      );
      expect(_ids(result), ['gated']);
    });

    test('identified: a null segment id never matches', () {
      final result = filterSurveys(
        _workspace([
          _survey('idless', segment: {'hasFilters': true}),
        ]),
        _user(userId: 'u1', segments: ['seg_a']),
        now: fixedNow,
      );
      expect(result, isEmpty);
    });
  });

  group('filterSurveys — composition', () {
    test('stages compose: passing earlier stages still fails segments', () {
      final result = filterSurveys(
        _workspace([
          _survey('gated', segment: {'id': 'seg_a', 'hasFilters': true}),
        ]),
        _user(),
        now: fixedNow,
      );
      expect(result, isEmpty);
    });

    test('an earlier stage drops before segments can keep', () {
      // Segment matches, but the survey was already displayed once.
      final result = filterSurveys(
        _workspace([
          _survey(
            's1',
            displayOption: 'displayOnce',
            segment: {'id': 'seg_a', 'hasFilters': true},
          ),
        ]),
        _user(
          userId: 'u1',
          segments: ['seg_a'],
          displays: [TDisplay(surveyId: 's1', createdAt: now)],
        ),
        now: fixedNow,
      );
      expect(result, isEmpty);
    });

    test('a malformed survey entry is skipped, valid ones survive', () {
      final result = filterSurveys(
        _workspace([
          {'noId': true},
          'not even a map',
          _survey('good'),
        ]),
        _user(),
        now: fixedNow,
      );
      expect(_ids(result), ['good']);
    });

    test('empty survey list → empty result', () {
      expect(filterSurveys(_workspace([]), _user(), now: fixedNow), isEmpty);
    });
  });
}
