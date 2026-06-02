# formbricks_flutter

First-party Flutter SDK for [Formbricks](https://formbricks.com). Connect your
Flutter app to a Formbricks workspace, identify users, track actions, and render
targeted in-app surveys.

> **Status: in development.** Initialization (`Formbricks.setup`) and its
> foundations are implemented. `track` / identify / survey rendering land in
> follow-up work.

## Initialization

```dart
import 'package:formbricks_flutter/formbricks_flutter.dart';

final result = await Formbricks.setup(
  appUrl: 'https://app.formbricks.com',
  workspaceId: 'wsp_...',
);

switch (result) {
  case Ok():
    // SDK is ready.
  case Err(:final error):
    // Invalid input (e.g. missing/!http(s) appUrl) — error.message explains.
}
```

`setup` is idempotent (a second call is a no-op), runs through an internal
command queue, and installs a lifecycle-aware expiry ticker. A **first**-setup
network failure throws `FormbricksSetupError` and puts the SDK into a 10-minute
error cooldown; subsequent `setup` calls within that window short-circuit.

## Planned public API

```dart
// Static imperative API (sequenced via the same command queue).
await Formbricks.track('button_clicked');
await Formbricks.setUserId('user_123');
await Formbricks.setAttribute('plan', 'pro');
await Formbricks.setAttributes({'plan': 'pro', 'mrr': 99});
await Formbricks.setLanguage('de');
await Formbricks.logout();
```

See [`docs/FLUTTER_SDK_PLAN.md`](../../docs/FLUTTER_SDK_PLAN.md) for the full spec
and the React Native → Flutter architecture mapping.
