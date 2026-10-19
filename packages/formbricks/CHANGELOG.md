# Changelog

## 1.3.0

- Add `Formbricks.setAppearance()`: surveys render `light` (the default), `dark`
  or `system`, which follows your app's own theme, not the phone's. It works
  before or after `setup`, an open survey switches in place, and the choice is
  not persisted or sent to the server. You can also pass `appearance:` to the
  `Formbricks` widget. Custom CSS configured in Formbricks is now forwarded to
  the survey renderer. Dark mode needs a Formbricks server that supports it; an
  older server keeps surveys light.
- Take the survey card position from the renderer (`onCardRectChange`) instead
  of scraping its DOM. This keeps touches outside the card reaching your app
  when a survey has no backdrop, and stops depending on markup that has broken
  before. It needs a current Formbricks server: on an older one, a survey with
  no backdrop blocks touches to the app behind it.
- Raise dependency floors: `clock` ^1.1.3, `url_launcher` ^6.3.3 and
  `connectivity_plus` ^7.3.2.

## 1.2.0

- Add `Formbricks.setEmbeddedData()` and `Formbricks.clearEmbeddedData()`: attach
  context to future responses without tying it to a trigger. Values merge into an
  in-memory bag (last write wins per key, `null` removes a key), are snapshotted
  when a survey is shown, and land only on fields the survey declares as ingested
  Embedded Data. Typed fields, defaults and locking need a Formbricks server on
  6.0 or later; older servers treat the values as plain hidden fields.
- Includes the 1.1.1 fix below, which shipped from a release branch and was not
  yet listed here.

## 1.1.1

- Fix survey cards being untappable when the survey has no backdrop. The
  card-geometry probe required `aria-modal`, which the surveys runtime now sets
  only for surveys that have one. With no rect to work from, the pointer mask
  rejected touches across the whole WebView instead of only outside the card.
  The runtime is served at render time, so hosts on a current server hit this
  without changing SDK version.

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
