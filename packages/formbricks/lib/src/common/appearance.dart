/// How surveys render, and the in-memory state behind `Formbricks.setAppearance`.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;

import 'logger.dart';

/// How surveys render. [system] follows the host app's own theme — its
/// `Theme` / `ThemeMode` — not the phone's.
enum FormbricksAppearance {
  /// Always light (the default).
  light,

  /// Always dark.
  dark,

  /// Follows the app's theme, live.
  system;

  /// Parses `'light'`, `'dark'` or `'system'`; null for anything else.
  static FormbricksAppearance? tryParse(Object? value) {
    if (value is FormbricksAppearance) return value;
    if (value is! String) return null;
    for (final appearance in values) {
      if (appearance.name == value.trim().toLowerCase()) return appearance;
    }
    return null;
  }
}

/// The in-memory appearance state (ENG-3452).
///
/// Never persisted, never sent to the server, and left alone by `logout()`, so a
/// fresh app launch starts light (ENG-3551). Not routed through the command
/// queue, so it works before `setup()` completes.
class AppearanceState extends ChangeNotifier {
  AppearanceState._();

  /// The process-wide state.
  static final AppearanceState instance = AppearanceState._();

  FormbricksAppearance _current = FormbricksAppearance.light;

  /// The requested appearance. May be [FormbricksAppearance.system].
  FormbricksAppearance get current => _current;

  /// Sets the appearance. An unknown value is logged and falls back to light.
  void set(Object? value) {
    final parsed = FormbricksAppearance.tryParse(value);
    if (parsed == null) {
      Logger.error(
        'setAppearance: unknown appearance "$value", falling back to light',
      );
    }
    _current = parsed ?? FormbricksAppearance.light;
    notifyListeners();
  }

  /// Test-only: back to the cold-start state.
  void reset() {
    _current = FormbricksAppearance.light;
  }
}

/// What the renderer understands: always `'light'` or `'dark'`, never `'system'`.
///
/// `system` reads the theme of [context], which is the app's own, and only falls
/// back to the platform brightness when the app sets none.
String resolveAppearance(BuildContext context, FormbricksAppearance requested) {
  switch (requested) {
    case FormbricksAppearance.light:
      return 'light';
    case FormbricksAppearance.dark:
      return 'dark';
    case FormbricksAppearance.system:
      // A Material app (or any `Theme`) states its brightness there; a
      // `Theme.of` with no ancestor would quietly answer light, so look first.
      // Otherwise the Cupertino theme, then the platform as a last resort.
      final brightness = context.findAncestorWidgetOfExactType<Theme>() != null
          ? Theme.of(context).brightness
          : CupertinoTheme.maybeBrightnessOf(context) ??
              MediaQuery.maybePlatformBrightnessOf(context) ??
              Brightness.light;
      return brightness == Brightness.dark ? 'dark' : 'light';
  }
}

/// JavaScript that flips an open survey in place. Optional chaining: a server
/// whose renderer predates `setAppearance` leaves the survey light instead of
/// throwing.
String appearanceSwitchScript(String resolved) =>
    "window.formbricksSurveys?.setAppearance?.('$resolved');";

/// Builds the renderer's `customCss` prop from the workspace and survey CSS.
///
/// The compiled strings pass through untouched. Empty fields are omitted rather
/// than sent as null — the renderer rejects the whole prop on a null inside a
/// scope — and null is returned when there is no CSS at all, so the key is never
/// sent.
Map<String, Map<String, String>>? buildCustomCss(
  Object? workspace,
  Object? survey,
) {
  Map<String, String>? scope(Object? raw) {
    if (raw is! Map) return null;
    final result = <String, String>{};
    for (final mode in const ['light', 'dark']) {
      final css = raw[mode];
      if (css is String && css.isNotEmpty) result[mode] = css;
    }
    return result.isEmpty ? null : result;
  }

  final workspaceScope = scope(workspace);
  final surveyScope = scope(survey);
  if (workspaceScope == null && surveyScope == null) return null;
  return {
    if (workspaceScope != null) 'workspace': workspaceScope,
    if (surveyScope != null) 'survey': surveyScope,
  };
}

/// Hands the open survey's resolved appearance to the WebView host.
///
/// An [InheritedNotifier] rather than a new parameter on the host builder, so
/// injected test hosts keep compiling. The default host listens and runs
/// [appearanceSwitchScript] when it changes.
class AppearanceScope extends InheritedNotifier<ValueNotifier<String>> {
  /// Creates a scope around [child].
  const AppearanceScope({
    super.key,
    required ValueNotifier<String> appearance,
    required super.child,
  }) : super(notifier: appearance);

  /// The nearest resolved-appearance notifier, if any.
  static ValueNotifier<String>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}
