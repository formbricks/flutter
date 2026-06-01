# formbricks_flutter

First-party Flutter SDK for [Formbricks](https://formbricks.com). Connect your
Flutter app to a Formbricks workspace, identify users, track actions, and render
targeted in-app surveys.

> **Status: skeleton.** This package was scaffolded to establish the monorepo.
> The public API and survey rendering land in follow-up work. It currently
> exposes only a placeholder `welcome()`.

## Planned public API

```dart
// Host widget — initializes the SDK and renders any active survey.
Formbricks(appUrl: 'https://app.formbricks.com', workspaceId: 'wsp_...');

// Static imperative API (sequenced via an internal command queue).
await Formbricks.track('button_clicked');
await Formbricks.setUserId('user_123');
await Formbricks.setAttribute('plan', 'pro');
await Formbricks.setAttributes({'plan': 'pro', 'mrr': 99});
await Formbricks.setLanguage('de');
await Formbricks.logout();
```

See [`docs/FLUTTER_SDK_PLAN.md`](../../docs/FLUTTER_SDK_PLAN.md) for the full spec
and the React Native → Flutter architecture mapping.
