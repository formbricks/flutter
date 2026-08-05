# Changelog

## 1.1.0

- Support survey-interaction segment filters: segments that target contacts by
  whether they have seen, started responding to, or completed a survey. The SDK
  now pulls fresh segment membership after an interaction instead of waiting for
  the user state to expire, so a rule like "completed survey A, show survey B"
  fires in the same session.
- Bridge the survey runtime's `onFinished` callback, which the "have completed"
  operators depend on. It fires only once the finished response has been accepted
  by the backend.
- Fix a failing user-state flush surfacing as an unhandled async error. The
  refresh is fire-and-forget, and `unawaited` does not handle errors.

Only workspaces using interaction targeting see additional network activity: one
extra user-state request per interaction, gated per survey and per event and
debounced so a display, response and finish together cost a single request.

## 1.0.0

First stable release. No API changes since 0.1.1 — promotes the SDK to a
stable 1.0.

## 0.1.1

- Fix host app touches not passing through to the underlying widgets.
- Validate unsupported attribute value types with a clear error.
- Fix local SDK being blocked on the Android emulator.
- Add manual platform entries to `pubspec.yaml`.

## 0.1.0

First beta release.

- `Formbricks.setup(...)` — initialize against a workspace, with persisted
  config, lifecycle-aware expiry refresh, and error-state cooldown.
- `Formbricks.track(...)` — code-action tracking.
- User identification — `setUserId`, `setAttribute` / `setAttributes`,
  `setLanguage`, and `logout`, with debounced, coalesced backend sync.
- Survey eligibility filtering — `displayOption`, `recontactDays`,
  `displayLimit`, segment targeting, and the `displayPercentage` gate.
- Targeted in-app surveys rendered through a hardened WebView host.
