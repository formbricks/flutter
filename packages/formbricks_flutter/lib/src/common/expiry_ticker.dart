import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import '../types/config.dart';
import 'api_client.dart';
import 'config.dart';
import 'filter_surveys.dart';
import 'logger.dart';
import 'result.dart';
import 'time.dart';

/// A single, lifecycle-aware expiry ticker.
///
/// Replaces the RN SDK's two separate 60s tickers (workspace + user) with one
/// `Timer.periodic` that checks both. It is also lifecycle-aware: it cancels the
/// timer while the app is backgrounded and runs an immediate check the moment
/// the app resumes — RN ran its tickers regardless of app state, wasting battery
/// and racing storage on resume.
class ExpiryTicker with WidgetsBindingObserver {
  /// Creates a ticker bound to [config] and [apiClient].
  ///
  /// [onTick] overrides the work done each tick (test seam). [binding] overrides
  /// the [WidgetsBinding] used to observe lifecycle (defaults to the instance).
  ExpiryTicker({
    required this.config,
    required this.apiClient,
    this.interval = const Duration(seconds: 60),
    this.onTick,
    this.binding,
  });

  /// The config to read/persist expiry state against.
  final FormbricksConfig config;

  /// The API client used to refetch workspace state on expiry.
  final ApiClient apiClient;

  /// The check interval.
  final Duration interval;

  /// Optional override for the per-tick work (test seam).
  final Future<void> Function()? onTick;

  /// Optional override for the lifecycle binding (test seam).
  final WidgetsBinding? binding;

  Timer? _timer;
  bool _started = false;

  /// The +30 min extension applied when a sync fails / user state is refreshed.
  static const Duration _kExtension = Duration(minutes: 30);

  WidgetsBinding get _resolvedBinding => binding ?? WidgetsBinding.instance;

  /// Whether a timer is currently scheduled (test helper / introspection).
  bool get hasActiveTimer => _timer?.isActive ?? false;

  /// Starts observing lifecycle and schedules the periodic check.
  void start() {
    if (_started) return;
    _started = true;
    _resolvedBinding.addObserver(this);
    _scheduleTimer();
  }

  /// Cancels the timer and stops observing lifecycle.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _resolvedBinding.removeObserver(this);
    _started = false;
  }

  void _scheduleTimer() {
    // Always cancel any existing timer first, so a resume can never leave two
    // periodic timers running (the RN dual-ticker bug this design guards
    // against).
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() => (onTick ?? _check)();

  /// Runs one expiry check and awaits it. Test-only.
  @visibleForTesting
  Future<void> debugCheck() => _check();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.resumed:
        unawaited(_tick());
        _scheduleTimer();
    }
  }

  /// One expiry check: refetch the workspace if expired; extend the user state
  /// expiry if it lapsed while a user is identified.
  Future<void> _check() async {
    final snapshot = config.getOrNull();
    if (snapshot == null) return;

    final workspace = snapshot.workspace;
    if (workspace != null && isNowExpired(workspace.expiresAt)) {
      Logger.debug('Workspace state has expired. Starting sync.');
      final result = await apiClient.getWorkspaceState();
      // Re-read after the round-trip so concurrent writes aren't clobbered.
      final synced = config.getOrNull();
      if (synced == null) return;
      switch (result) {
        case Ok(:final value):
          await config.update(
            synced.copyWith(
              workspace: value,
              filteredSurveys: filterSurveys(value, synced.user)
                  .map((s) => s.toJson())
                  .toList(),
            ),
          );
        case Err(:final error):
          Logger.error('Error during workspace expiry sync: ${error.code}');
          // Extend validity so we retry later instead of hammering the backend.
          await config.update(
            synced.copyWith(
              workspace: TWorkspaceState(
                expiresAt: clock.now().add(_kExtension),
                data: synced.workspace?.data ?? workspace.data,
              ),
            ),
          );
      }
    }

    final current = config.getOrNull();
    if (current == null) return;
    final user = current.user;
    final expiresAt = user.expiresAt;
    if (user.data.userId != null &&
        expiresAt != null &&
        isNowExpired(expiresAt)) {
      // Mirror RN's user ticker: extend the identified user's state by 30 min.
      await config.update(
        current.copyWith(
          user: user.copyWith(expiresAt: clock.now().add(_kExtension)),
        ),
      );
    }
  }
}
