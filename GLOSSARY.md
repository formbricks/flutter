# Glossary

Domain terms the code and architecture reviews use. Only terms specific to the Flutter SDK belong here: no general
programming concepts, and no implementation details.

## Setup

**Workspace** — The Formbricks workspace the SDK is set up for, identified by `workspaceId`. Its surveys, action classes and settings are cached as the workspace state.

**App URL** — The base URL of the Formbricks server the SDK talks to (`appUrl`). The survey script is loaded from it.

**Setup** — Initializing the SDK for a workspace and app URL: hydrating the cached config, syncing workspace (and user) state, and starting the expiry ticker. Tracking and user calls made before setup completes fail with `NotSetupError`.

**Error cooldown** — After a failed first setup, the SDK waits 10 minutes before trying setup again for the same workspace and app URL.

## Users

**Contact** — The identified user on the Formbricks side, set with `setUserId` and resolved to a `contactId`. Without a user id the user is anonymous.

**Attribute** — A value set on the contact with `setAttributes` / `setAttribute` (strings, numbers, dates); the language is set as one. Attributes are sent to the server and can place the contact in segments.

**Segment** — A group of contacts defined on the server. A survey can target a segment; the user state carries the segments the contact belongs to.

**Embedded Data** — Context the host app attaches to future responses with `setEmbeddedData`. It is held in memory only, never persisted, and is not an attribute.

## Surveys

**Action class** — A workspace-defined action that can trigger surveys. A `code` action class has a key the host passes to `track`; `noCode` ones are not tracked by this SDK.

**Code action** — A call to `Formbricks.track(key)` that matches a `code` action class and shows a filtered survey whose trigger names it.

**Filtered surveys** — The surveys the current user is eligible to see, recomputed at every state change by three stages: display option, recontact days and segment targeting. Only this set is considered when an action is tracked.

**Display** — One showing of a survey to the user, recorded with its survey id and time. Displays and responses feed the display option and recontact days checks.

**Display option** — How often a survey may be shown: `displayOnce`, `displayMultiple`, `displaySome` (up to a display limit) or `respondMultiple`.

**Recontact days** — The minimum number of days since the user's last display before another survey may be shown; a survey's own value overrides the workspace's.

**Display percentage** — The chance that a triggered survey is actually shown; a roll per trigger decides it.

**Survey script** — The survey renderer, loaded from `{appUrl}/js/surveys.umd.cjs` into the WebView that shows a survey.
