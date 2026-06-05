/// The single active-survey store, ported from the React Native SDK's
/// `lib/survey/store.ts`.
///
/// RN exposed it via `useSyncExternalStore`; here it is a `ValueNotifier` so the
/// `Formbricks` widget can rebuild through a `ValueListenableBuilder`. Singleton,
/// matching the rest of the SDK.
library;

import 'package:flutter/foundation.dart';

import '../types/survey.dart';

/// Holds the currently-active survey (or null) and notifies listeners on change.
class SurveyStore {
  SurveyStore._();

  static SurveyStore? _instance;

  /// The process-wide survey store.
  static SurveyStore get instance => _instance ??= SurveyStore._();

  final ValueNotifier<TSurvey?> _notifier = ValueNotifier<TSurvey?>(null);

  /// Listenable the widget layer subscribes to.
  ValueListenable<TSurvey?> get listenable => _notifier;

  /// The currently-active survey, or null.
  TSurvey? get survey => _notifier.value;

  /// Sets [survey] as active, notifying listeners **only when the id changes**
  /// (mirrors RN's id-guard — re-setting the same survey is a no-op).
  void setSurvey(TSurvey survey) {
    if (_notifier.value?.id != survey.id) {
      // Assigning a value different from the current one notifies listeners.
      _notifier.value = survey;
    }
  }

  /// Clears the active survey, notifying listeners only when one was set.
  void resetSurvey() {
    if (_notifier.value != null) {
      _notifier.value = null;
    }
  }

  /// Disposes the notifier and drops the singleton. Test-only.
  @visibleForTesting
  static void resetInstance() {
    _instance?._notifier.dispose();
    _instance = null;
  }
}
