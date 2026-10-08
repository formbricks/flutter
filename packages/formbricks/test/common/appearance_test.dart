import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/formbricks.dart';
import 'package:formbricks/src/common/appearance.dart';

void main() {
  setUp(AppearanceState.instance.reset);
  tearDown(AppearanceState.instance.reset);

  group('AppearanceState', () {
    test('defaults to light', () {
      expect(AppearanceState.instance.current, FormbricksAppearance.light);
    });

    test('set before setup, from the enum or a string', () {
      Formbricks.setAppearance(FormbricksAppearance.dark);
      expect(AppearanceState.instance.current, FormbricksAppearance.dark);
      Formbricks.setAppearance('system');
      expect(AppearanceState.instance.current, FormbricksAppearance.system);
    });

    test('an unknown value falls back to light without throwing', () {
      Formbricks.setAppearance('dark');
      expect(() => Formbricks.setAppearance('sepia'), returnsNormally);
      expect(AppearanceState.instance.current, FormbricksAppearance.light);
    });

    test('notifies listeners on every change', () {
      var calls = 0;
      void listener() => calls++;
      AppearanceState.instance.addListener(listener);
      Formbricks.setAppearance(FormbricksAppearance.dark);
      expect(calls, 1);
      AppearanceState.instance.removeListener(listener);
      Formbricks.setAppearance(FormbricksAppearance.light);
      expect(calls, 1);
    });
  });

  group('resolveAppearance', () {
    Future<String> resolveIn(
      WidgetTester tester,
      FormbricksAppearance requested, {
      Widget Function(Widget child)? wrap,
      Brightness platform = Brightness.light,
    }) async {
      late String result;
      Widget child = Builder(
        builder: (context) {
          result = resolveAppearance(context, requested);
          return const SizedBox.shrink();
        },
      );
      if (wrap != null) child = wrap(child);
      tester.platformDispatcher.platformBrightnessTestValue = platform;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(child);
      return result;
    }

    testWidgets('light and dark win over the app theme', (tester) async {
      Widget dark(Widget c) => MaterialApp(theme: ThemeData.dark(), home: c);
      expect(
        await resolveIn(tester, FormbricksAppearance.light, wrap: dark),
        'light',
      );
      expect(
        await resolveIn(tester, FormbricksAppearance.dark),
        'dark',
      );
    });

    testWidgets('system follows a dark app theme on a light phone',
        (tester) async {
      Widget darkApp(Widget c) => MaterialApp(theme: ThemeData.dark(), home: c);
      expect(
        await resolveIn(
          tester,
          FormbricksAppearance.system,
          wrap: darkApp,
          platform: Brightness.light,
        ),
        'dark',
      );
    });

    testWidgets('system follows an app pinned to light on a dark phone',
        (tester) async {
      Widget lightApp(Widget c) => MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: ThemeMode.light,
            home: c,
          );
      expect(
        await resolveIn(
          tester,
          FormbricksAppearance.system,
          wrap: lightApp,
          platform: Brightness.dark,
        ),
        'light',
      );
    });

    testWidgets('system follows a Cupertino app theme', (tester) async {
      Widget cupertino(Widget c) => CupertinoApp(
            theme: const CupertinoThemeData(brightness: Brightness.dark),
            home: c,
          );
      expect(
        await resolveIn(tester, FormbricksAppearance.system, wrap: cupertino),
        'dark',
      );
    });
  });

  test('appearanceSwitchScript tolerates an older renderer', () {
    expect(
      appearanceSwitchScript('dark'),
      "window.formbricksSurveys?.setAppearance?.('dark');",
    );
  });

  group('buildCustomCss', () {
    test('sends no key when neither scope has CSS', () {
      expect(buildCustomCss(null, null), isNull);
      expect(buildCustomCss(<String, dynamic>{}, {'light': ''}), isNull);
    });

    test('forwards workspace and survey CSS untouched', () {
      expect(
        buildCustomCss(
          {'light': '.a{color:red}', 'dark': '.a{color:blue}'},
          {'dark': '.b{margin:0}'},
        ),
        {
          'workspace': {'light': '.a{color:red}', 'dark': '.a{color:blue}'},
          'survey': {'dark': '.b{margin:0}'},
        },
      );
    });

    test('omits an empty scope and null fields instead of sending null', () {
      final result = buildCustomCss({'light': '.a{}', 'dark': null}, null);
      expect(result, {
        'workspace': {'light': '.a{}'},
      });
      expect(result!.containsKey('survey'), isFalse);
    });
  });
}
