/// The in-memory Embedded Data bag.
///
/// Context a host app attaches to future responses without tying it to a
/// trigger — `Formbricks.setEmbeddedData({'screen': 'checkout'})` once, instead
/// of repeating the same values on every possible `track(...)` call.
///
/// Mirrors the JS SDK's store key for key, so web and mobile behave identically.
library;

import '../common/logger.dart';

/// Holds the host-supplied Embedded Data for this process.
///
/// Lifetime rules, all deliberate:
///
/// * **In-memory, process scoped, never persisted.** Not `SharedPreferences`:
///   persisting this bag would blur the Embedded Data ↔ contact-attribute
///   boundary and create a stale-data / PII-at-rest surface. A cold app start
///   begins empty; the host re-pushes.
/// * **Snapshot at display, then frozen.** `SurveyWebView` copies the bag into
///   the survey's render options when the survey is shown, so a later
///   `setEmbeddedData` affects the next response, never the one on screen.
/// * **No filtering here.** The SDK is a dumb pipe: the survey renderer applies
///   the ingest contract — allow-list, coercion, `locked`, size caps — and logs
///   what it refuses, and the server re-runs all of it on ingest. Filtering here
///   would ship a second copy of those rules for the four mobile SDKs to drift
///   from.
/// * **Independent of `setup`.** A host legitimately pushes context before the
///   SDK finishes initializing, and silently dropping that write is the failure
///   this API exists to avoid.
/// * **No network.** Every method is a synchronous memory write, so calling it
///   on every screen change is free. Values ride the existing response payload.
class EmbeddedDataStore {
  EmbeddedDataStore._();

  /// The process-wide bag.
  static final EmbeddedDataStore instance = EmbeddedDataStore._();

  final Map<String, Object> _data = <String, Object>{};

  /// Merges [values] into the bag — never replaces it — so refreshing a
  /// volatile field (`screen`) cannot wipe the stable ones (`plan`) set at
  /// launch. Per key: last write wins, and an explicit `null` removes the key.
  ///
  /// A key the caller simply leaves out is untouched; that is how a host skips a
  /// field it has no value for this screen. `null` is the deliberate "remove
  /// this" spelling, matching the JS SDK's `{ key: null }`.
  ///
  /// Values must be a `String`, `num`, `bool` or `DateTime` — the four scalars
  /// the ingest contract can store. Anything else is logged and skipped rather
  /// than thrown: a host mistake must never cost a response. A non-finite `num`
  /// is refused for the same reason, and a sharper one — `jsonEncode` throws on
  /// `NaN`/`Infinity`, and the payload it would refuse is the whole survey's
  /// render options, so one bad value would cost the survey, not the field.
  void set(Map<String, Object?> values) {
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) {
        _data.remove(entry.key);
        continue;
      }
      if (value is num && !value.isFinite) {
        Logger.error(
          'setEmbeddedData: "${entry.key}" is not a finite number — '
          'the key was skipped',
        );
        continue;
      }
      if (value is! String &&
          value is! num &&
          value is! bool &&
          value is! DateTime) {
        Logger.error(
          'setEmbeddedData: "${entry.key}" is a ${value.runtimeType}, which '
          'cannot be stored — the key was skipped',
        );
        continue;
      }
      _data[entry.key] = value;
    }
  }

  /// Removes one [key]. A key that is not set is a no-op.
  void remove(String key) {
    _data.remove(key);
  }

  /// Removes everything — logout, or a hard context switch.
  void clear() {
    _data.clear();
  }

  /// A detached, JSON-safe copy for the display-time snapshot: mutating the bag
  /// after a survey has rendered must not reach that survey's response.
  ///
  /// `DateTime` is serialized as ISO 8601, which is what the renderer's ingest
  /// contract accepts for a `date` field. Everything else `jsonEncode` already
  /// handles.
  Map<String, Object> snapshot() => <String, Object>{
        for (final entry in _data.entries)
          entry.key: entry.value is DateTime
              ? (entry.value as DateTime).toUtc().toIso8601String()
              : entry.value,
      };
}
