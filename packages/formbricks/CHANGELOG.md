# Changelog

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
