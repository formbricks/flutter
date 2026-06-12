/// Formbricks Flutter SDK.
///
/// Public entry point. Drop the [Formbricks] widget into your tree to
/// initialize the SDK and render targeted in-app surveys, and call
/// `Formbricks.track(...)` to trigger code actions. Initialization, the command
/// queue, config, API client and expiry ticker live behind the facade.
library;

export 'src/common/logger.dart' show LogLevel;
export 'src/common/result.dart';
export 'src/types/errors.dart';
export 'src/widgets/formbricks_widget.dart' show Formbricks;
