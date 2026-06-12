import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../types/config.dart';
import '../types/errors.dart';
import 'api_client.dart';
import 'config.dart';
import 'expiry_ticker.dart';
import 'filter_surveys.dart';
import 'logger.dart';
import 'result.dart';
import 'time.dart';

/// How long the SDK waits before retrying after a failed first setup.
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
/// state and **throws** [FormbricksSetupError].
///
/// [httpClient], [startTicker] and [logLevel] are overrides for tests and the
/// playground.
Future<Result<void, FormbricksError>> setup({
  required String appUrl,
  required String workspaceId,
  http.Client? httpClient,
  LogLevel? logLevel,
  bool startTicker = true,
}) async {
  final resolvedLevel =
      logLevel ?? (kDebugMode ? LogLevel.debug : LogLevel.error);
  Logger.configure(level: resolvedLevel);

  if (_isSetup) {
    Logger.debug('Already set up, skipping setup.');
    return const Result.ok(null);
  }

  if (workspaceId.isEmpty) {
    Logger.debug('No workspaceId provided');
    return Result.err(MissingFieldError('workspaceId'));
  }
  if (appUrl.isEmpty) {
    Logger.debug('No appUrl provided');
    return Result.err(MissingFieldError('appUrl'));
  }
  final uri = Uri.tryParse(appUrl);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    Logger.debug('appUrl is not a valid http(s) URL');
    return Result.err(
      MissingFieldError(
        'appUrl',
        message: 'appUrl must be a valid http(s) URL',
      ),
    );
  }

  // Strip any trailing slash so endpoints (which all start with `/api/...`)
  // don't produce a double-slash URL the backend won't route.
  final normalizedAppUrl = appUrl.replaceAll(RegExp(r'/+$'), '');

  final config = FormbricksConfig.instance;
  await config.init();
  final existing = config.getOrNull();
  Logger.debug(
    existing != null
        ? 'Found existing configuration.'
        : 'No existing configuration found.',
  );

  // Retry only after the stored first-setup cooldown expires for this target.
  if (existing != null && existing.status.isError) {
    final expiresAt = existing.status.expiresAt;
    final sameTarget = existing.workspaceId == workspaceId &&
        existing.appUrl == normalizedAppUrl;
    if (sameTarget && expiresAt != null && !isNowExpired(expiresAt)) {
      Logger.debug('Within error cooldown. Skipping setup.');
      return Result.err(SetupCooldownError(retryAt: expiresAt));
    }
    Logger.debug(
      sameTarget
          ? 'Error cooldown elapsed. Continuing with setup.'
          : 'Ignoring error cooldown for different setup target.',
    );
  }

  Logger.debug('Start setup');

  final api = ApiClient(
    appUrl: normalizedAppUrl,
    workspaceId: workspaceId,
    client: httpClient,
    isDebug: resolvedLevel == LogLevel.debug,
  );

  final matches = existing != null &&
      existing.workspace != null &&
      existing.workspaceId == workspaceId &&
      existing.appUrl == normalizedAppUrl;

  // The ticker takes ownership of `api` for its lifetime; every other path must
  // close it so error/early-return/no-ticker paths don't leak the http.Client.
  var handedToTicker = false;
  try {
    if (matches) {
      final result = await _syncExistingConfig(config, api, existing);
      if (result case Err()) return result;
    } else {
      Logger.debug(
        'No valid configuration found. Resetting config and creating new one.',
      );
      await config.reset();
      Logger.debug('Syncing.');
      final response = await api.getWorkspaceState();
      switch (response) {
        case Ok(:final value):
          final filteredSurveys =
              filterSurveys(value, TUserState.defaultNoUserId);
          await config.update(
            TConfig(
              workspaceId: workspaceId,
              appUrl: normalizedAppUrl,
              workspace: value,
              user: TUserState.defaultNoUserId,
              filteredSurveys: filteredSurveys.map((s) => s.toJson()).toList(),
              status: TStatus.success,
            ),
          );
          Logger.debug(
            'Fetched ${filteredSurveys.length} surveys during sync: '
            '${filteredSurveys.map((s) => s.id).join(', ')}',
          );
        case Err(:final error):
          await _handleErrorOnFirstSetup(
            config,
            error,
            appUrl: normalizedAppUrl,
            workspaceId: workspaceId,
          );
      }
    }

    if (startTicker) {
      Logger.debug('Starting expiry ticker');
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
/// is always still valid here because `FormbricksConfig.init` discards any
/// cached config whose workspace has expired before we reach this point. Returns
/// `Err(NetworkError)` on failure; only first setup throws.
Future<Result<void, FormbricksError>> _syncExistingConfig(
  FormbricksConfig config,
  ApiClient api,
  TConfig existing,
) async {
  Logger.debug('Configuration fits setup parameters.');

  final workspace = existing.workspace!;

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

  final filteredSurveys = filterSurveys(workspace, user);
  await config.update(
    existing.copyWith(
      workspace: workspace,
      user: user,
      filteredSurveys: filteredSurveys.map((s) => s.toJson()).toList(),
      status: TStatus.success,
    ),
  );
  Logger.debug(
    'Fetched ${filteredSurveys.length} surveys during sync: '
    '${filteredSurveys.map((s) => s.id).join(', ')}',
  );
  return const Result.ok(null);
}

/// Persists the error-cooldown state and throws [FormbricksSetupError].
Future<Never> _handleErrorOnFirstSetup(
  FormbricksConfig config,
  ApiErrorResponse error, {
  required String appUrl,
  required String workspaceId,
}) async {
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
      workspaceId: workspaceId,
      appUrl: appUrl,
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

/// Resets user state to anonymous, refilters surveys, and persists both.
///
/// Called when switching identity (`setUserId` to a different id) and on
/// `logout`. No-op when no config is loaded yet.
Future<void> tearDown({FormbricksConfig? config}) async {
  final cfg = config ?? FormbricksConfig.instance;
  Logger.debug('Setting user state to default');

  final current = cfg.getOrNull();
  if (current == null) return;

  final workspace = current.workspace;
  await cfg.update(
    current.copyWith(
      user: TUserState.defaultNoUserId,
      filteredSurveys: workspace == null
          ? const []
          : filterSurveys(workspace, TUserState.defaultNoUserId)
              .map((s) => s.toJson())
              .toList(),
    ),
  );
}

NetworkError _toNetworkError(ApiErrorResponse error) => NetworkError(
      message: error.message,
      status: error.status,
      url: error.url,
      responseMessage: error.responseMessage,
    );
