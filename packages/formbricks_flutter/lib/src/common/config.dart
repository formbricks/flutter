import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../types/config.dart';
import 'logger.dart';
import 'time.dart';

/// Persistent SDK config, backed by [SharedPreferences] under [storageKey].
///
/// Design choices:
/// - **Init once.** [init] reads storage a single time during `setup()`; after
///   that [get] is synchronous and does not re-read the disk.
/// - **Awaited persistence.** [update] completes only after the disk write, so a
///   crash can't lose a write that already "returned".
/// - **Dates cross one boundary.** All ISO↔`DateTime` conversion lives in
///   [TConfig.fromJson] / [TConfig.toJson]; nothing here calls `DateTime.parse`.
class FormbricksConfig {
  FormbricksConfig._();

  static FormbricksConfig? _instance;

  /// The process-wide config singleton.
  static FormbricksConfig get instance => _instance ??= FormbricksConfig._();

  /// SharedPreferences key, namespaced to this SDK so multiple Formbricks SDKs
  /// on one device never collide on storage.
  static const String storageKey = 'formbricks-flutter';

  TConfig? _config;
  SharedPreferences? _prefs;

  /// Loads and parses the cached config exactly once.
  ///
  /// A cached config whose **workspace** has expired is discarded. An error-only
  /// config (no workspace) is kept so the
  /// error cooldown survives a reload.
  Future<void> init() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    if (saved == null) {
      _config = null;
      return;
    }

    try {
      final parsed = TConfig.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
      final workspace = parsed.workspace;
      if (workspace != null && isNowExpired(workspace.expiresAt)) {
        Logger.debug('Config in local storage has expired.');
        _config = null;
        return;
      }
      _config = parsed;
    } catch (e) {
      Logger.error('Error loading config from storage: $e');
      _config = null;
    }
  }

  /// Returns the current config. Throws if [init] never produced a valid config.
  TConfig get() {
    final config = _config;
    if (config == null) {
      throw StateError(
        'Config is null — was init() called, or is the cached config invalid?',
      );
    }
    return config;
  }

  /// Returns the current config, or null when none is loaded.
  TConfig? getOrNull() => _config;

  /// Whether a valid config is currently loaded.
  bool get isInitialized => _config != null;

  /// Updates the in-memory config and awaits the disk write before completing.
  Future<void> update(TConfig config) async {
    _config = config;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(config.toJson()));
  }

  /// Clears the persisted config and the in-memory copy.
  Future<void> reset() async {
    _config = null;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  /// Drops the singleton so each test starts clean. Test-only.
  @visibleForTesting
  static void resetInstance() => _instance = null;
}
