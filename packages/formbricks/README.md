# formbricks

First-party Flutter SDK for [Formbricks](https://formbricks.com). Connect your
Flutter app to a Formbricks workspace, identify users, set attributes, track
code actions, and render targeted in-app surveys in a `WebView` overlay.

Targets **iOS and Android**.

## Install

```bash
flutter pub add formbricks
```

```dart
import 'package:formbricks/formbricks.dart';
```

## Quick start

Mount the `Formbricks` widget once, high in your tree (e.g. wrapping or
alongside your app's home). It initializes the SDK on mount and renders any
triggered survey in a modal overlay:

```dart
import 'package:flutter/material.dart';
import 'package:formbricks/formbricks.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Stack(
        children: [
          const HomePage(),
          // Initializes the SDK and hosts the survey overlay.
          Formbricks(
            appUrl: 'https://app.formbricks.com',
            workspaceId: 'wsp_...',
          ),
        ],
      ),
    );
  }
}
```

Then drive the SDK through its static API from anywhere:

```dart
// Trigger a code action — shows a matching, eligible survey.
await Formbricks.track('button_clicked');

// Identify the current user and set attributes.
await Formbricks.setUserId('user_123');
await Formbricks.setAttribute('plan', 'pro');
await Formbricks.setAttributes({'plan': 'pro', 'mrr': 99, 'signup_date': DateTime.now()});

// Pick a survey language, then clear identity on sign-out.
await Formbricks.setLanguage('de');
await Formbricks.logout();
```

All static methods are sequenced through an internal command queue, so calls
run in submission order (a `setUserId` followed by `setAttribute` can't race).
Each returns a `Future<Result<void, FormbricksError>>`.

> Prefer to initialize before any UI mounts? Call `Formbricks.setup(...)`
> directly (see below) — the widget still needs to be in the tree to render
> surveys, but it won't re-run setup (setup is idempotent).

## Public API

| Method                                              | Description                                                              |
| --------------------------------------------------- | ------------------------------------------------------------------------ |
| `Formbricks(appUrl:, workspaceId:, logLevel:)`      | Host widget — initializes the SDK and renders triggered surveys.         |
| `Formbricks.setup({appUrl, workspaceId, logLevel})` | Imperative initialization. Idempotent.                                   |
| `Formbricks.track(String name)`                     | Fire a code action; shows a matching eligible survey.                    |
| `Formbricks.setUserId(String userId)`               | Identify the contact. Switching ids resets the prior user's state first. |
| `Formbricks.setAttribute(String key, Object value)` | Set one attribute (`String` / `num` / `DateTime`).                       |
| `Formbricks.setAttributes(Map<String, Object>)`     | Set several attributes at once.                                          |
| `Formbricks.setLanguage(String language)`           | Set the survey language.                                                 |
| `Formbricks.logout()`                               | Reset to an anonymous session.                                           |

Attribute keys must be lowercase letters, numbers, and underscores, and start
with a letter. `DateTime` values are sent as UTC ISO-8601 strings; numbers stay
numbers. Identity/attribute changes are debounced (~500 ms) and coalesced into a
single backend request.

## Identification & targeting

- **Anonymous** sessions can be shown any survey that isn't gated behind a
  targeting segment.
- After `setUserId`, the backend returns the user's matched **segments**;
  segment-targeted surveys are shown only to users in a matching segment.
- `setLanguage` **without** a userId set updates only the local config (no
  network request) — it takes effect on the next survey shown.

A tracked action only shows a survey that passes eligibility:

- **`displayOption`** — `respondMultiple`, `displayOnce`, `displayMultiple`,
  `displaySome` (+ `displayLimit`).
- **`recontactDays`** — per-survey value, falling back to the workspace setting,
  measured from the last display.
- **`displayPercentage`** — a per-trigger dice-roll.

The SDK tracks displays and responses locally as they happen, so e.g. a
`displayOnce` survey stops triggering immediately after it has been shown.

## Initialization & error handling

`Formbricks.setup` reports problems through **three** channels:

```dart
try {
  final result = await Formbricks.setup(
    appUrl: 'https://app.formbricks.com',
    workspaceId: 'wsp_...',
  );

  switch (result) {
    case Ok():
    // SDK is ready.
    case Err(:final error):
    // Invalid input, or a sync failure refreshing an existing cached config —
    // error.message explains. SetupCooldownError means a retry is suppressed.
  }
} on FormbricksSetupError {
  // First-setup network/auth failure — the SDK enters a 10-minute cooldown.
}
```

- **Returns `Err`** for invalid input (missing or non-`http(s)` `appUrl` /
  `workspaceId`) and for a workspace/user sync failure when refreshing an
  existing cached config.
- **Throws `FormbricksSetupError`** when the _first_ setup attempt fails on the
  network/auth. The SDK then enters a 10-minute error cooldown.
- **Returns `Err(SetupCooldownError)`** for any `setup` call made _within_ that
  cooldown window — the SDK stays inert (no network call) and `error.retryAt`
  says when it will try again.

`setup` is idempotent (a second successful call is a no-op), runs through the
command queue, and installs a lifecycle-aware expiry ticker that refreshes
workspace and user state and pauses while the app is backgrounded.

Set `logLevel: LogLevel.debug` to see the SDK's `🧱 Formbricks - …` trace; the
default level is `error`. Logs never contain attribute values or other PII.

## Storage & privacy

Config is persisted with `shared_preferences` under the key `formbricks-flutter`.
This is **not encrypted at rest** — avoid putting sensitive Personally
Identifiable Information (PII) in attribute values. Survey responses are
submitted by the embedded WebView directly to your `appUrl` over HTTPS; the
Dart layer never handles response content.

## Platform support

iOS + Android only; Flutter Web and desktop are not supported. Surveys render by
loading `{appUrl}/js/surveys.umd.cjs` in a WebView, so that URL must be reachable
from the device. Formbricks Cloud and standard self-hosted instances serve this
script automatically — no extra setup is needed unless you host behind a
restricted network.
