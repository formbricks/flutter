import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/survey/survey_store.dart';
import 'package:formbricks_flutter/src/types/survey.dart';

TSurvey _s(String id) => TSurvey.fromJson({'id': id});

void main() {
  setUp(SurveyStore.resetInstance);

  test('getInstance returns a singleton', () {
    expect(SurveyStore.instance, same(SurveyStore.instance));
  });

  test('setSurvey stores the survey and notifies once', () {
    var notifications = 0;
    SurveyStore.instance.listenable.addListener(() => notifications++);
    SurveyStore.instance.setSurvey(_s('a'));
    expect(SurveyStore.instance.survey?.id, 'a');
    expect(notifications, 1);
  });

  test('setSurvey with the same id does not notify', () {
    SurveyStore.instance.setSurvey(_s('a'));
    var notifications = 0;
    SurveyStore.instance.listenable.addListener(() => notifications++);
    SurveyStore.instance.setSurvey(_s('a'));
    expect(notifications, 0);
  });

  test('setSurvey with a different id replaces and notifies', () {
    SurveyStore.instance.setSurvey(_s('a'));
    var notifications = 0;
    SurveyStore.instance.listenable.addListener(() => notifications++);
    SurveyStore.instance.setSurvey(_s('b'));
    expect(SurveyStore.instance.survey?.id, 'b');
    expect(notifications, 1);
  });

  test('resetSurvey clears and notifies', () {
    SurveyStore.instance.setSurvey(_s('a'));
    var notifications = 0;
    SurveyStore.instance.listenable.addListener(() => notifications++);
    SurveyStore.instance.resetSurvey();
    expect(SurveyStore.instance.survey, isNull);
    expect(notifications, 1);
  });

  test('resetSurvey when already empty does not notify', () {
    var notifications = 0;
    SurveyStore.instance.listenable.addListener(() => notifications++);
    SurveyStore.instance.resetSurvey();
    expect(notifications, 0);
  });

  test('a removed listener is not called', () {
    var notifications = 0;
    void listener() => notifications++;
    SurveyStore.instance.listenable.addListener(listener);
    SurveyStore.instance.listenable.removeListener(listener);
    SurveyStore.instance.setSurvey(_s('a'));
    expect(notifications, 0);
  });
}
