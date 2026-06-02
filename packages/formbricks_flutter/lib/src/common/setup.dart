import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../types/config.dart';
import '../types/errors.dart';
import 'api_client.dart';
import 'config.dart';
import 'expiry_ticker.dart';
import 'logger.dart';
import 'result.dart';
import 'time.dart';

/// How long the SDK stays in the error state after a failed first setup before
/// it will retry. Named constant rather than an inline magic number (RN buried
/// this as `Date.now() + 10 * 60000`).
const Duration _kErrorCooldown = Duration(minutes: 10);

bool _isSetup = false;
ExpiryTicker? _ticker;

/// Whether `setup()` has completed. Read by the [CommandQueue].
bool get isSetup => _isSetup;

/// Overrides the setup flag. Exposed for the command queue + tests.
void setIsSetup({required bool value}) => _isSetup = value;

/// Resets the setup module's state (flag + ticker). Test-only. Tests should
/// also call `FormbricksConfig.resetInstance()` and `Logger.resetInstance()`.
@visibleForTesting
void resetSetupForTest() {
  _isSetup = false;
  _ticker?.stop();
  _ticker = null;
}

/// Initializes the SDK: validates input, hydrates the cached config, syncs
/// workspace (and user, when one is cached and expired), installs the expiry
/// ticker, and marks setup complete.
///
/// Returns `Ok` on success and `Err(MissingFieldError)` for bad input. On a
/// **first-setup** network/forbidden failure it persists the error-cooldown
/// state and **throws** [FormbricksSetupError] (matching the RN SDK).
///
/// [httpClient], [startTicker] and [logLevel] are seams for tests / the demo.
Future<Result<void, FormbricksError>> setup({
  required String appUrl,
  required String workspaceId,
  http.Client? httpClient,
  LogLevel? logLevel,
  @visibleForTesting bool startTicker = true,
}) async {
  if (logLevel != null) Logger.configure(level: logLevel);

  if (_isSetup) {
    Logger.debug('Already set up, skipping setup.');
    return const Result.ok(null);
  }

  final config = FormbricksConfig.instance;
  await config.init();
  final existing = config.getOrNull();

  // Error-cooldown gate. NOTE: this is the corrected logic — RN skipped setup
  // when the cooldown had *expired* (a bug). Here: still cooling down (expiresAt
  // in the future) → short-circuit; cooldown elapsed → clear and continue.
  if (existing != null && existing.status.isError) {
    final expiresAt = existing.status.expiresAt;
    if (expiresAt != null && !isNowExpired(expiresAt)) {
      Logger.debug('Within error cooldown. Skipping setup.');
      return const Result.ok(null);
    }
    Logger.debug('Error cooldown elapsed. Continuing with setup.');
  }

  // Validation.
  if (workspaceId.isEmpty) {
    Logger.debug('No workspaceId provided');
    return Result.err(MissingFieldError('workspaceId'));
  }
  if (appUrl.isEmpty) {
    Logger.debug('No appUrl provided');
    return Result.err(MissingFieldError('appUrl'));
  }
  final uri = Uri.tryParse(appUrl);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    Logger.debug('appUrl is not a valid http(s) URL');
    return Result.err(
      MissingFieldError(
        'appUrl',
        message: 'appUrl must be a valid http(s) URL',
      ),
    );
  }

  Logger.debug('Start setup');

  final api = ApiClient(
    appUrl: appUrl,
    workspaceId: workspaceId,
    client: httpClient,
    isDebug: logLevel == LogLevel.debug,
  );

  final matches =
      existing != null &&
      existing.workspace != null &&
      existing.workspaceId == workspaceId &&
      existing.appUrl == appUrl;

  // The ticker takes ownership of `api` for its lifetime; every other path must
  // close it so error/early-return/no-ticker paths don't leak the http.Client.
  var handedToTicker = false;
  try {
    if (matches) {
      final result = await _syncExistingConfig(config, api, existing);
      if (result case Err()) return result;
    } else {
      // Fresh setup: reset any stale config, fetch, persist or enter error state.
      await config.reset();
      final response = await api.getWorkspaceState();
      switch (response) {
        case Ok(:final value):
          await config.update(
            TConfig(
              workspaceId: workspaceId,
              appUrl: appUrl,
              workspace: value,
              user: TUserState.defaultNoUserId,
              filteredSurveys: const [],
              status: TStatus.success,
            ),
          );
        case Err(:final error):
          // Persists error state and throws FormbricksSetupError.
          await _handleErrorOnFirstSetup(config, error);
      }
    }

    if (startTicker) {
      final ticker = ExpiryTicker(config: config, apiClient: api)..start();
      _ticker = ticker;
      handedToTicker = true;
    }
    _isSetup = true;
    Logger.debug('Set up complete');
    return const Result.ok(null);
  } finally {
    if (!handedToTicker) api.close();
  }
}

/// Sync path when the cached config already matches the requested workspace/app:
/// refresh the user if it expired while identified, then persist. The workspace
/// is always still valid here — `FormbricksConfig.init` discards any cached
/// config whose workspace has expired before we reach this point. Returns
/// `Err(NetworkError)` on failure (does not throw — only first-setup throws).
Future<Result<void, FormbricksError>> _syncExistingConfig(
  FormbricksConfig config,
  ApiClient api,
  TConfig existing,
) async {
  Logger.debug('Configuration fits setup parameters.');

  final workspace = existing.workspace!;

  // User.
  TUserState user;
  final existingUser = existing.user;
  final userExpiresAt = existingUser.expiresAt;
  if (userExpiresAt == null || !isNowExpired(userExpiresAt)) {
    user = existingUser;
  } else if (existingUser.data.userId != null) {
    Logger.debug('Person state expired. Syncing.');
    final response = await api.createOrUpdateUser(
      userId: existingUser.data.userId!,
    );
    switch (response) {
      case Ok(:final value):
        user = value.state;
      case Err(:final error):
        return Result.err(_toNetworkError(error));
    }
  } else {
    user = TUserState.defaultNoUserId;
  }

  await config.update(
    existing.copyWith(
      workspace: workspace,
      user: user,
      filteredSurveys: const [],
      status: TStatus.success,
    ),
  );
  return const Result.ok(null);
}

/// Persists the error-cooldown state and throws [FormbricksSetupError]. Mirrors
/// RN's `handleErrorOnFirstSetup`.
Future<Never> _handleErrorOnFirstSetup(
  FormbricksConfig config,
  ApiErrorResponse error,
) async {
  final isForbidden = error.code == 'forbidden';
  if (isForbidden) {
    Logger.error('Authorization error: ${error.message}');
  } else {
    Logger.error(
      'Error during first setup: ${error.code} - ${error.message}. '
      'Please try again later.',
    );
  }

  await config.update(
    TConfig(
      status: TStatus(
        value: 'error',
        expiresAt: clock.now().add(_kErrorCooldown),
      ),
    ),
  );

  throw FormbricksSetupError(
    code: isForbidden
        ? FormbricksErrorCode.forbidden
        : FormbricksErrorCode.networkError,
  );
}

NetworkError _toNetworkError(ApiErrorResponse error) => NetworkError(
  message: error.message,
  status: error.status,
  url: error.url,
  responseMessage: error.responseMessage,
);
