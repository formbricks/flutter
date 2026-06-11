/// Debounced user-update coalescer.
///
/// Ports the RN `UpdateQueue` (`lib/user/update-queue.ts`). Rapid identity and
/// attribute changes are merged into a single accumulator and flushed once,
/// 500 ms after the *last* call, into one `POST /api/v2/client/{id}/user`.
///
/// Ordering of the public API is provided by the [CommandQueue], not here — the
/// debounce flow is fire-and-forget at the call site (`unawaited(processUpdates())`).
/// A failed flush drops the whole batch (no retry, no partial update).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../common/api_client.dart';
import '../common/config.dart';
import '../common/filter_surveys.dart';
import '../common/logger.dart';
import '../common/result.dart';
import '../types/config.dart';
import '../types/errors.dart';

/// The pending, un-flushed identity/attribute accumulator.
class _PendingUpdates {
  _PendingUpdates({required this.userId, this.attributes});

  /// The user id to apply. May be empty when only attributes were queued and no
  /// userId is resolvable yet (mirrors RN's `?? ""` fallback).
  final String userId;

  /// The attributes to apply (numbers preserved as numbers; dates already ISO).
  final Map<String, Object?>? attributes;
}

/// A 500 ms debounce that coalesces user updates into one backend call.
class UpdateQueue {
  UpdateQueue._();

  static UpdateQueue? _instance;

  /// The process-wide queue singleton.
  static UpdateQueue get instance => _instance ??= UpdateQueue._();

  /// The debounce window: a flush fires this long after the last call.
  static const Duration debounceDelay = Duration(milliseconds: 500);

  /// Config override for tests. Defaults to [FormbricksConfig.instance].
  @visibleForTesting
  FormbricksConfig? configOverride;

  /// API-client override for tests. When set, [_sendUpdates] uses it instead of
  /// building one from config (and does not close it).
  @visibleForTesting
  ApiClient? apiClientOverride;

  FormbricksConfig get _config => configOverride ?? FormbricksConfig.instance;

  _PendingUpdates? _updates;
  Timer? _debounce;
  Completer<void>? _flushCompleter;

  /// Whether nothing is queued.
  bool get isEmpty => _updates == null;

  /// The queued userId, or null when nothing is queued. Test-only.
  @visibleForTesting
  String? get pendingUserId => _updates?.userId;

  /// The queued attributes, or null when nothing is queued. Test-only.
  @visibleForTesting
  Map<String, Object?>? get pendingAttributes => _updates?.attributes;

  /// Merges [userId] into the pending updates (creating them if empty).
  void updateUserId(String userId) {
    final current = _updates;
    _updates = _PendingUpdates(
      userId: userId,
      attributes: current?.attributes ?? <String, Object?>{},
    );
  }

  /// Merges [attributes] into the pending updates.
  ///
  /// The effective userId is resolved from the pending updates first, then from
  /// the persisted config (mirrors `update-queue.ts:40`). Later keys win.
  void updateAttributes(Map<String, Object?> attributes) {
    final pendingUserId = _updates?.userId;
    final userId = (pendingUserId != null && pendingUserId.isNotEmpty)
        ? pendingUserId
        : (_config.getOrNull()?.user.data.userId ?? '');

    final current = _updates;
    _updates = _PendingUpdates(
      userId: userId,
      attributes: <String, Object?>{...?current?.attributes, ...attributes},
    );
  }

  /// Schedules a debounced [_flush].
  ///
  /// Each call cancels the previous timer so the flush fires 500 ms after the
  /// *last* call. Calls within one window share a single completer, completed
  /// (or completed-with-error) when that window's flush runs. Fire-and-forget
  /// at the call site; the returned future exists for tests.
  Future<void> processUpdates() {
    if (_updates == null) return Future<void>.value();

    _debounce?.cancel();
    final completer = _flushCompleter ??= Completer<void>();

    _debounce = Timer(debounceDelay, () async {
      final c = _flushCompleter;
      _flushCompleter = null;
      _debounce = null;
      try {
        await _flush();
        if (c != null && !c.isCompleted) c.complete();
      } catch (error, stackTrace) {
        Logger.error('Failed to process updates: $error');
        if (c != null && !c.isCompleted) c.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  /// Cancels any pending flush and drops the buffered updates without sending.
  ///
  /// Call on logout / identity switch so a queued change can't re-identify the
  /// user after logout, nor leak attributes queued for one user into the next.
  /// Also the disposal/hot-reload path: a dangling [Timer] can't fire after the
  /// queue is cleared. The shared completer is resolved (not errored) so
  /// fire-and-forget callers don't see a dropped batch as a failure.
  void clear() {
    _debounce?.cancel();
    _debounce = null;
    final c = _flushCompleter;
    _flushCompleter = null;
    if (c != null && !c.isCompleted) c.complete();
    _updates = null;
  }

  /// The debounced handler (port of `update-queue.ts:154–195`).
  Future<void> _flush() async {
    final pending = _updates;
    if (pending == null) return;

    // Snapshot, then drop the live buffer *before* any await. Anything queued
    // during the round-trip starts a fresh batch instead of writing into the
    // one in flight (which would otherwise get re-sent by an overlapping flush
    // or silently wiped by this flush's exit). Failed batches are dropped (no
    // retry) anyway, so clearing up-front changes no semantics.
    _updates = null;

    final cfg = _config.get();

    // Resolve the effective userId: pending (non-empty) first, then config.
    final pendingUserId = pending.userId;
    final effectiveUserId =
        (pendingUserId.isNotEmpty) ? pendingUserId : cfg.user.data.userId;

    var attributes = <String, Object?>{...?pending.attributes};

    // Language without a userId updates local config only — never the backend.
    if (effectiveUserId == null || effectiveUserId.isEmpty) {
      attributes = await _handleLanguageWithoutUserId(attributes);
    }

    // Attributes require a userId. If any remain without one, error out. The
    // buffer is already cleared above, so nothing re-sends.
    if (attributes.isNotEmpty &&
        (effectiveUserId == null || effectiveUserId.isEmpty)) {
      const message =
          "Formbricks can't set attributes without a userId! Please set a "
          'userId first with the setUserId function';
      Logger.error(message);
      throw MissingFieldError('userId', message: message);
    }

    await _sendUpdates(effectiveUserId, attributes);
  }

  /// Writes a queued `language` straight into local config (no API call) and
  /// strips it from [attributes] (port of `update-queue.ts:68–96`).
  Future<Map<String, Object?>> _handleLanguageWithoutUserId(
    Map<String, Object?> attributes,
  ) async {
    final language = attributes['language'];
    if (language is! String) return attributes;

    final cfg = _config.get();
    await _config.update(
      cfg.copyWith(
        user: cfg.user.copyWith(
          data: cfg.user.data.copyWith(language: language),
        ),
      ),
    );
    Logger.debug('Updated language successfully');

    return Map<String, Object?>.from(attributes)..remove('language');
  }

  /// Sends the batch to the backend and persists the returned state (port of
  /// `update.ts:63–123`). No-op without a userId; no retry on failure.
  Future<void> _sendUpdates(
    String? userId,
    Map<String, Object?> attributes,
  ) async {
    if (userId == null || userId.isEmpty) return;

    final cfg = _config.get();
    final injected = apiClientOverride;
    final api = injected ??
        ApiClient(appUrl: cfg.appUrl!, workspaceId: cfg.workspaceId!);

    Result<CreateOrUpdateUserResponse, ApiErrorResponse> result;
    try {
      result = await api.createOrUpdateUser(
        userId: userId,
        attributes: attributes,
      );
    } finally {
      if (injected == null) api.close();
    }

    switch (result) {
      case Err(:final error):
        // No retry — the buffer is already cleared by the flush, so nothing
        // re-sends until the next identity/attribute change.
        Logger.error('Failed to send updates: ${error.message}');
      case Ok(:final value):
        // errors => always-visible; messages => debug-only.
        value.errors?.forEach(Logger.error);
        value.messages?.forEach((m) => Logger.debug('User update message: $m'));
        final hasWarnings = value.errors?.isNotEmpty ?? false;

        // Persist the synced user and refilter in the same write.
        final current = _config.get();
        final workspace = current.workspace;
        await _config.update(
          current.copyWith(
            user: value.state,
            filteredSurveys: workspace == null
                ? const []
                : filterSurveys(workspace, value.state)
                    .map((s) => s.toJson())
                    .toList(),
          ),
        );

        if (!hasWarnings) Logger.debug('Updates sent successfully');
    }
  }

  /// Drops the singleton so each test starts clean. Test-only.
  @visibleForTesting
  static void resetInstance() {
    _instance?.clear();
    _instance = null;
  }
}
