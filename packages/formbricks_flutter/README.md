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

try {
  final result = await Formbricks.setup(
    appUrl: 'https://app.formbricks.com',
    workspaceId: 'wsp_...',
  );

  switch (result) {
    case Ok():
    // SDK is ready.
    case Err(:final error):
    // Invalid input (e.g. missing / non-http(s) appUrl) — error.message explains.
  }
} on FormbricksSetupError {
  // First-setup network/auth failure — see below.
}
```

`setup` reports problems through **two** channels:

- It **returns `Err`** for invalid input (missing or non-`http(s)`
  `appUrl` / `workspaceId`) and for a workspace/user sync failure when refreshing
  an existing cached config.
- It **throws `FormbricksSetupError`** when the _first_ setup attempt fails on the
  network/auth. The SDK then enters a 10-minute error cooldown.
- It **returns `Err(SetupCooldownError)`** for any `setup` call made _within_ that
  cooldown window — the SDK stays inert (no network call), and `error.retryAt`
  says when it will try again. Distinct from `Ok` so callers don't treat the
  suppressed-retry state as "ready".

`setup` is also idempotent (a second successful call is a no-op), runs through an
internal command queue, and installs a lifecycle-aware expiry ticker.

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
