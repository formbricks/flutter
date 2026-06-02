/// Formbricks Flutter SDK.
///
/// Public entry point. This ticket lands initialization only — `Formbricks.setup`
/// plus the foundations behind it (config, API client, command queue, expiry
/// ticker). `track` / identify / survey rendering arrive in follow-up work.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'src/common/command_queue.dart';
import 'src/common/config.dart';
import 'src/common/logger.dart';
import 'src/common/result.dart';
import 'src/common/setup.dart' as setup_internal;
import 'src/types/errors.dart';

export 'src/common/logger.dart' show LogLevel;
export 'src/common/result.dart';
export 'src/types/errors.dart';

/// The Formbricks SDK facade.
///
/// Static methods delegate to a hidden command queue so calls execute in strict
/// submission order. `setup()` itself runs with `checkSetup: false` because it
/// is what flips the SDK into the set-up state.
class Formbricks {
  Formbricks._();

  static final CommandQueue _queue = CommandQueue(
    isSetup: () => setup_internal.isSetup,
  );

  /// Initializes the SDK against [appUrl] / [workspaceId].
  ///
  /// Completes with `Ok` on success or `Err(MissingFieldError)` for invalid
  /// input. Throws [FormbricksSetupError] if the *first* setup attempt fails on
  /// the network (the SDK then enters a 10-minute error cooldown).
  static Future<Result<void, FormbricksError>> setup({
    required String appUrl,
    required String workspaceId,
    LogLevel? logLevel,
  }) {
    return _queue.add<Result<void, FormbricksError>>(
      () => setup_internal.setup(
        appUrl: appUrl,
        workspaceId: workspaceId,
        logLevel: logLevel,
      ),
      checkSetup: false,
    );
  }

  /// Returns the raw JSON the SDK has persisted in `SharedPreferences` (under
  /// the `formbricks-flutter` key), or `null` if nothing is stored yet.
  ///
  /// A debugging/inspection aid — handy for seeing exactly what `setup()` and
  /// future state changes write to disk. Not part of the stable API.
  static Future<String?> debugStoredConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FormbricksConfig.storageKey);
  }
}
