# Changelog

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
