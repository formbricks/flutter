# Formbricks Flutter SDK — Project Definition & Tech Spec

Project Lead: TBD
Author: anshuman@formbricks.com
Last updated: 2026-05-28
Status: Draft for review

---

## 1. Summary

Build `formbricks_flutter`, a first-party Flutter SDK that mirrors the surface area of `@formbricks/react-native` (this repo). It lets a Flutter app initialize a Formbricks workspace, identify users, set attributes, track code actions, and render targeted in-app surveys inside a `WebView` overlay backed by the existing `surveys.umd.cjs` runtime hosted at `${appUrl}/js/surveys.umd.cjs`.

The SDK ships as a single pub.dev package (`formbricks_flutter`) targeting iOS and Android, supporting both Material and Cupertino apps, with no native platform code beyond the WebView and storage plugins it depends on.

---

## 2. Context / Why

- Flutter is a top-3 mobile cross-platform framework. We currently have RN + iOS + Android + Web. Flutter is the only major mobile gap.
- Several enterprise prospects (and existing customers) have Flutter apps and have been blocked from adopting Formbricks. Today they either embed our web SDK in a `webview_flutter` themselves (no targeting, no state sync) or skip Formbricks entirely.
- We already proved the WebView-renderer pattern works in RN. Porting the same architecture to Flutter is cheap relative to the GTM upside.
- Doing this now (before V5 churn settles) lets us bake the V5 client API contract (`/api/v1/client/{workspaceId}/environment`, `/api/v2/client/{workspaceId}/user`) into the new SDK from day one instead of carrying a legacy `environmentId` debt like RN does.

---

## 3. Scope

### In scope (v1.0)

- Pure-Dart SDK package on pub.dev: `formbricks_flutter`.
- Public Dart API surface (mirrors RN `index.ts`):
  - `Formbricks` widget — drop-in host that initializes the SDK and renders any active survey.
  - `Formbricks.setup({appUrl, workspaceId})`
  - `Formbricks.track(String name)`
  - `Formbricks.setUserId(String userId)`
  - `Formbricks.setAttribute(String key, dynamic value)` — accepts `String`, `num`, `DateTime`.
  - `Formbricks.setAttributes(Map<String, dynamic> attrs)`
  - `Formbricks.setLanguage(String language)`
  - `Formbricks.logout()`
- Persistent config in `SharedPreferences` (key `formbricks-flutter`), schema identical to RN's `RNConfig` payload so the backend contract is unchanged.
- Workspace state fetch + cache with expiry refresh (matches RN's `workspace/state.ts`).
- User state fetch via `POST /api/v2/client/{workspaceId}/user` with debounce-batched attribute updates.
- Code action tracking against cached `actionClasses`, with `displayPercentage` gate and survey filtering by `displayOption`, `recontactDays`, and `segments`.
- WebView host (`webview_flutter`) that loads `surveys.umd.cjs` from `appUrl`, posts message bridge events (`onDisplayCreated`, `onResponseCreated`, `onClose`, `onOpenExternalURL`), enforces same-origin navigation, and opens external links via `url_launcher`.
- Sequential command queue with `await Formbricks.track(...)` semantics (same contract as RN).
- Multi-language survey resolution.
- Example app under `example/` (equivalent to `apps/playground`) for manual QA.
- CI: format (`dart format`), analyze (`flutter analyze` with `package:lints/recommended.yaml`), unit tests (`flutter test`), integration test on iOS sim + Android emulator, pub.dev dry-run publish.

### Explicitly out of scope (v1.0)

- Link surveys (URL-based survey rendering outside the embedded WebView).
- File upload questions inside surveys (RN has a `fileUploadParams` bridge stub but the RN SDK does not implement upload either — defer until product priority is set).
- Native-rendered surveys (no WebView). Same WebView strategy as RN — we will not reimplement the survey runtime in Flutter widgets.
- Offline queueing of responses. Backend submission goes through the embedded WebView's `ResponseQueue`, same as RN. No Dart-side offline retry.
- Web (Flutter Web) and desktop (macOS/Windows/Linux) targets. iOS + Android only for v1.
- Push-notification triggers, in-app messages, or any non-survey product surface.
- Server-side rendering, SSG, or any non-mobile-app context.
- A migration path from `environmentId` → `workspaceId`. New SDK only accepts `workspaceId`.

---

## 4. Success Criteria

Ship is successful when **all** of the following hold:

1. `formbricks_flutter` is published to pub.dev with a stable `^1.0.0` and `pub.dev/packages/formbricks_flutter` shows a Pub Points score ≥ 130.
2. Integration test suite renders a survey, submits a response, and verifies the backend recorded the display + response in a staging workspace — running green on both iOS sim and Android emulator in CI.
3. Behavior parity matrix vs RN SDK passes for all rows: `setup`, `track`, `setUserId`, `setAttribute`/`setAttributes`, `setLanguage`, `logout`, multi-language survey, `displayOnce`/`displayMultiple`/`displaySome`/`respondMultiple`, `recontactDays`, `displayPercentage`, `segments` filtering, error-state cooldown after first setup fails.
4. Example app demonstrates: app-action survey trigger, code-action survey trigger, attribute-based segment, language switch, logout/identity reset.
5. At least one design-partner customer has the SDK in their app and successfully collected ≥ 100 in-app responses through it before GA.
6. Bundle-size impact on a vanilla Flutter app < 800 KB compressed APK delta (mostly `webview_flutter` + `shared_preferences` + `url_launcher`, all of which most apps already have).

---

## 5. Requirements & Constraints

### Tech stack

- Language: Dart ≥ 3.12.0. Flutter ≥ 3.44.0 (stable channel).
- Required plugins (peer/direct):
  - `webview_flutter: ^4.x` — survey rendering.
  - `shared_preferences: ^2.x` — persistent config (RN equivalent: `AsyncStorage`).
  - `url_launcher: ^6.x` — open external URLs surfaced from inside the survey.
  - `connectivity_plus: ^6.x` — connectivity check before `track()` (RN equivalent: `@react-native-community/netinfo`).
  - `http: ^1.x` — REST calls. We will **not** depend on `dio` — keep the dep graph minimal and avoid forcing a transitive interceptor stack on host apps.
- Dev / test:
  - `flutter_test`, `mocktail`, `http_mock_adapter` or a custom `http.Client` mock.
  - `melos` (optional) if we ever go monorepo; for v1 a single `formbricks_flutter` package is sufficient.

### Public API surface (1:1 with RN where it makes sense)

```dart
// Initialization (widget — preferred)
Formbricks(appUrl: 'https://app.formbricks.com', workspaceId: 'wsp_...')

// Imperative API — static methods, all return Future<void>, sequenced via CommandQueue.
// State (command queue, config) lives in a private singleton, not exposed publicly.
await Formbricks.track('button_clicked');
await Formbricks.setUserId('user_123');
await Formbricks.setAttribute('plan', 'pro');
await Formbricks.setAttributes({'plan': 'pro', 'mrr': 99});
await Formbricks.setLanguage('de');
await Formbricks.logout();
```

### Internal architecture (mirrors `packages/react-native/src/lib/`)

| Concern | RN file | Flutter equivalent |
|---|---|---|
| Command queue (sequential public API) | `lib/common/command-queue.ts` | `lib/src/common/command_queue.dart` — `Future`-based queue, single in-flight worker |
| Persistent config singleton | `lib/common/config.ts` | `lib/src/common/config.dart` — `FormbricksConfig` singleton wrapping `SharedPreferences` |
| AsyncStorage shim | `lib/common/storage.ts` | direct `SharedPreferences` use, no shim needed |
| HTTP client | `lib/common/api.ts` | `lib/src/common/api_client.dart` — thin wrapper over `package:http` `Client` |
| Setup orchestration | `lib/common/setup.ts` | `lib/src/common/setup.dart` |
| Logger | `lib/common/logger.ts` | `lib/src/common/logger.dart` — same `🧱 Formbricks - ...` format, `debug`/`error` levels |
| Expiry tick listeners | `lib/common/event-listeners.ts` | `lib/src/common/expiry_ticker.dart` — `Timer.periodic`, lifecycle-aware (cancel on `AppLifecycleState.paused`, restart on `resumed`) |
| Survey trigger / `track` | `lib/survey/action.ts` | `lib/src/survey/action.dart` |
| In-memory survey store + listeners | `lib/survey/store.ts` | `lib/src/survey/survey_store.dart` — `ValueNotifier<TSurvey?>` (replaces RN's `useSyncExternalStore`) |
| User update debouncer | `lib/user/update-queue.ts` | `lib/src/user/update_queue.dart` — 500 ms debounce, single-flight |
| Workspace state fetch | `lib/workspace/state.ts` | `lib/src/workspace/workspace_state.dart` |
| Survey filtering (`displayOption`, `recontactDays`, segments) | `lib/common/utils.ts` `filterSurveys` | `lib/src/common/filter_surveys.dart` |
| WebView host | `components/survey-web-view.tsx` | `lib/src/widgets/survey_webview.dart` using `webview_flutter` `WebViewController`. Same generated `<html>` template — keep the inline JS bridge byte-for-byte where possible so the contract with `surveys.umd.cjs` stays identical |
| Top-level Formbricks widget | `components/formbricks.tsx` | `lib/src/widgets/formbricks_widget.dart` — `StatefulWidget` listening to `SurveyStore` via `AnimatedBuilder` / `ValueListenableBuilder` |

### Command queue

Required, same reasoning as RN: public API must be sequential so a `setUserId` followed by a `setAttribute` cannot race (attribute update needs the userId in the request body). Dart-side implementation:

```dart
class CommandQueue {
  final _queue = Queue<_QueuedCommand>();
  Completer<void>? _idle;
  bool _running = false;

  Future<void> add(FutureOr<void> Function() cmd, {bool checkSetup = true}) {
    final completer = Completer<void>();
    _queue.add(_QueuedCommand(cmd, checkSetup, completer));
    _run();
    return completer.future;
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    while (_queue.isNotEmpty) {
      final item = _queue.removeFirst();
      if (item.checkSetup && !FormbricksSetup.isSetup) {
        item.completer.complete();
        continue;
      }
      try { await item.cmd(); item.completer.complete(); }
      catch (e, s) { Logger.error('Global error: $e\n$s'); item.completer.completeError(e, s); }
    }
    _running = false;
  }
}
```

Each public API method `add`s its work and returns the completer's `Future`. This replicates RN's `queue.add(...); await queue.wait();` pattern.

### Update queue (attribute debounce)

Mirror RN exactly: 500 ms debounce, single in-flight, accumulator merges `userId` + `attributes`. Critical detail to port: **language updates without a userId must update local config only, not hit the backend** (`update-queue.ts:68–96`). Attribute updates without a userId throw and clear the buffer (`update-queue.ts:98–112`).

### REST endpoints (unchanged from RN)

- `GET  {appUrl}/api/v1/client/{workspaceId}/environment` → workspace state. Server may return `data.settings`, `data.workspace`, or legacy `data.project` — map to `data.settings` (see `workspace/state.ts:42–60`).
- `POST {appUrl}/api/v2/client/{workspaceId}/user` body `{ userId, attributes }` → `{ state: UserState, messages?: string[], errors?: string[] }`.
- Surveys runtime script: `{appUrl}/js/surveys.umd.cjs` (loaded inside the WebView, not by Dart).

### Storage schema

Key: `formbricks-flutter` (distinct from RN's `formbricks-react-native` so a single device with both SDKs doesn't collide). Value: JSON blob with the same shape as RN's `TConfig`:

```json
{
  "workspaceId": "wsp_...",
  "appUrl": "https://app.formbricks.com",
  "workspace": { "expiresAt": "...", "data": { "surveys": [...], "actionClasses": [...], "settings": {...} } },
  "user":      { "expiresAt": null|"...", "data": { "userId": null|"...", "contactId": null|"...", "segments": [], "displays": [], "responses": [], "lastDisplayAt": null|"...", "language": "..." } },
  "filteredSurveys": [...],
  "status":    { "value": "success"|"error", "expiresAt": null|"..." }
}
```

Dates serialize as ISO 8601 strings (Dart `DateTime.toIso8601String()` ↔ JS `new Date(...)`). Decoder must accept both `null` and missing keys for forward-compat.

### WebView bridge protocol (unchanged from RN)

JS → Dart (via `JavaScriptChannel`, replaces `window.ReactNativeWebView.postMessage`):

```js
function onClose()            { Formbricks.postMessage(JSON.stringify({ onClose: true })); }
function onDisplayCreated()   { Formbricks.postMessage(JSON.stringify({ onDisplayCreated: true })); }
function onResponseCreated()  { Formbricks.postMessage(JSON.stringify({ onResponseCreated: true })); }
// console.* → { type: 'Console', data: { type, log } }  (dev only)
```

Dart side validates message shape with a Zod-equivalent — there is no Zod in Dart, so we hand-roll a minimal validator with `Map<String, dynamic>` shape checks. Do not auto-trust the WebView (see Security).

### Constraints

- Backend contract is **frozen**. The SDK must not require backend changes. Anything that doesn't work today through the existing client API endpoints is out of scope.
- Minimum supported iOS: 12. Minimum supported Android: API 21 (matches `webview_flutter`).
- No null-safety opt-outs. No `dynamic` in public API except where the value is genuinely polymorphic (attribute values).
- Plugin authors must avoid `flutter_inappwebview` despite it being more featureful — `webview_flutter` is the official Flutter team plugin, is lighter, and is what enterprise security reviewers expect.
- No analytics calls, no telemetry beacons from the SDK itself.

### Dependencies on other teams

- Backend: confirms `/api/v1/client/{workspaceId}/environment` and `/api/v2/client/{workspaceId}/user` will remain stable through the Flutter SDK v1 lifecycle. No changes requested.
- Web team (`@formbricks/surveys`): keep the JS bridge contract (`window.formbricksSurveys.renderSurvey({ onDisplayCreated, onResponseCreated, onClose, ... })`) stable.
- Docs: a new "Flutter" framework guide alongside the React Native one.

---

## 6. Security Considerations (mandatory)

### Does this feature process user data?

Yes. The SDK receives user-provided identifiers (`userId`) and attribute values, persists them locally in `SharedPreferences`, and transmits them to the customer's configured `appUrl` over HTTPS. Survey responses are submitted by the embedded WebView directly to the same backend; Dart never touches response content.

### Are third-party services involved?

No third parties. The SDK only talks to the customer's `appUrl` (Formbricks Cloud or self-hosted). All dependencies are first-party Flutter team plugins (`webview_flutter`, `shared_preferences`, `url_launcher`) plus `connectivity_plus` and `http` from `dart.dev`-published, well-audited packages.

### Does this affect data privacy?

- `SharedPreferences` on Android is **not encrypted by default**. PII in attribute values therefore lives in plaintext at rest in `/data/data/<pkg>/shared_prefs/`. We will:
  - Document this clearly in the README.
  - Offer an opt-in `storage:` parameter on `Formbricks` widget that accepts a custom `FormbricksStorage` interface, so security-conscious customers can plug in `flutter_secure_storage` themselves.
  - Match RN parity — RN uses unencrypted `AsyncStorage` too — so we are not regressing.
- iOS `NSUserDefaults` (backing `SharedPreferences` on iOS) is similarly unencrypted but file-system-protected. Same documentation note.
- No PII in logs. Logger never logs attribute values; only attribute keys and userId at `debug` level. Default level is `error`.

### Does this affect tenant isolation?

The `workspaceId` scopes all API calls. The SDK MUST:
- Reject `appUrl` values that don't parse as `http://` or `https://` (port `survey-script-url.ts:8–10`).
- Enforce same-origin for in-WebView navigation; any URL whose origin ≠ `appUrl` origin is opened via `url_launcher` instead of inside the WebView (port `survey-web-view.tsx:275–305`).
- Reject WebView messages that don't validate against the expected shape.
- Never echo a cached config when `workspaceId` or `appUrl` changes — must reset (port `setup.ts:209–218`).

### Does this affect permissions or access control?

No new permissions. The SDK uses the **embedding app's** existing internet permission. It does not request camera, location, contacts, or any runtime permission.

### Required safeguards before shipping

1. **Origin allow-list for WebView**: only allow `appUrl` origin to load full pages; all other URLs go to `url_launcher.launchUrl()` with `mode: LaunchMode.externalApplication`.
2. **URL scheme allow-list**: only `http:` and `https:` open externally. Block `javascript:`, `file:`, `intent:`, `data:`. (Port `survey-web-view.tsx:291–296`.)
3. **WebView hardening**: `allowFileAccess: false`, `allowContentAccess: false`, `javaScriptEnabled: true` only on the survey HTML, `setSupportMultipleWindows: false`. Disable cookie persistence beyond the survey lifetime.
4. **Message validation**: every JS→Dart payload goes through a strict validator. Reject extra keys, wrong types, or non-JSON.
5. **HTTPS enforcement**: on iOS, the SDK should not weaken ATS. Document that customers using a self-hosted HTTP `appUrl` must add their own ATS exception — we will not bundle one.
6. **No eval, no dynamic code loading on the Dart side**. The Dart code is fully AOT-compiled. The only loaded JS is the customer's own `surveys.umd.cjs` from their `appUrl`.
7. **Secret handling**: `workspaceId` is not a secret (it's public per the existing product model). We document this; no token rotation needed.
8. **Dependency audit**: pin minor versions in `pubspec.yaml`, run `flutter pub outdated` weekly via Dependabot equivalent. No git-source or path-source dependencies in the published package.
9. **SBOM**: publish a Software Bill of Materials with every release (CycloneDX via `cyclonedx-dart`).
10. **Security review**: required from security@formbricks.com sign-off before pub.dev publish.

---

## 7. Open Questions / Risks

### Open questions

- **Repo layout**: ship as a new repo `formbricks/formbricks-flutter`, or add `packages/flutter` to this monorepo? RN lives in its own repo today. Flutter as a new repo keeps releases independent; sibling monorepo improves shared-spec evolution. *Recommendation: new repo, mirror the RN repo structure.*
- **Versioning**: do we align v1.0.0 of Flutter SDK with the workspace API generation (V5)? If yes, we lock the public API around the workspace-only world from day one.
- **Survey runtime bundle URL**: we currently load `/js/surveys.umd.cjs` from the customer's `appUrl`. For self-hosters running airgapped, this requires their own static asset hosting — same constraint as RN, but worth re-confirming with the self-host docs team.
- **`displayPercentage`**: RN uses `Math.random()` which is fine for non-security gating. Dart's `Random()` is equivalent. No question here, just noting we will not import `dart:math` `Random.secure()` for this gate.
- **`flutter_secure_storage` default vs opt-in**: do we keep parity with RN (unencrypted) or upgrade by default? Tradeoff: encrypted storage costs ~250 KB on Android, breaks reads after a clear-on-uninstall edge case on iOS, and requires native keychain entitlements. *Recommendation: opt-in, document loudly.*

### Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| WebView Android touch-event regressions (RN hit this — see `formbricks.tsx:56–61` `pointerEvents="box-none"`) | Med | Med | Wrap `WebView` in `Stack` with `IgnorePointer` outside the active survey area; integration test on a real Android device + Pixel emulator before GA |
| `webview_flutter` Android requires Hybrid Composition / SurfaceAndroidWebView quirks → keyboard avoidance bugs (RN had to add `KeyboardAvoidingView`) | Med | Med | Test text input questions on Android with soft keyboard early; default to `MediaQuery.viewInsets` padding inside the modal route |
| Survey script (`surveys.umd.cjs`) makes a breaking change to the JS→host message shape | Low | High | Lock the bridge schema in a shared spec doc with the web team; run the integration test suite against the prod surveys script on every release |
| `SharedPreferences` size limit (~few MB on Android) blown by large cached `workspace.surveys` payloads | Low | Med | Cap cached `surveys` count per workspace; surface a warning log when serialized config > 256 KB |
| Apple App Store rejects the embedded WebView as a "browser-like" app | Very low | High | Survey WebView is modal, no URL bar, no general browsing — same pattern Apple has accepted from countless in-app survey SDKs (Hotjar, Sprig, etc.). Document review notes for the App Store review team |
| Pub.dev publish account / package name squatting | Low | Med | Reserve `formbricks_flutter` (and `formbricks`) on pub.dev now under `formbricks.com` verified publisher |
| Flutter SDK drifts out of parity with RN as new features land on RN | Med | Med | Shared client-API contract doc; quarterly parity review; mark RN as the canonical reference until Flutter reaches v1.0 |
| Customers ship the SDK on Flutter Web (out of scope) and file bugs | Med | Low | Add a runtime guard: throw a clear `UnsupportedError` with a doc link when `kIsWeb` |

### Lessons from the RN SDK to **avoid** repeating in Flutter

1. **Don't bake in a legacy alias from day one.** RN still carries `environmentId` → `workspaceId` migration code in `config.ts` `migrateLegacyConfig` and `setup.ts` lines 283–295. Flutter SDK should accept `workspaceId` only — no deprecated alias to ever remove later.
2. **Don't make `RNConfig.getInstance()` async + side-effectful.** RN's singleton calls `await init()` on **every** `getInstance()` call (`config.ts:71–74`), which re-reads `SharedPreferences`/`AsyncStorage` every time. In Flutter, initialize once at SDK setup and expose a synchronous accessor; gate the public API behind `setup()` having completed.
3. **Don't let `Logger` be a process-global singleton with mutable level configured deep inside a component.** RN configures the logger from inside `survey-web-view.tsx:19` based on `__DEV__`. Move logger configuration into `Formbricks.setup()` so behavior is deterministic and testable.
4. **Don't store `Date` objects in JSON.** RN's `TConfig` typings claim `Date` fields but storage round-trips them as strings — leading to subtle bugs like `new Date(workspace.expiresAt) >= new Date()` having to defensively re-construct (`workspace/state.ts:91`). Use `DateTime` in memory, `String` (ISO 8601) on the wire and on disk, and convert at exactly one boundary in `FormbricksConfig.fromJson` / `toJson`.
5. **Don't couple WebView rendering to the host widget tree's React lifecycle.** RN's `SurveyWebView` `useEffect` chain (lines 34–90) does state sync, language resolution, and delay-timer setup as three separate effects, which has caused at least one race on remount. In Flutter, drive the survey lifecycle as a single state machine inside the widget's `State` with explicit transitions (`idle → loading → presenting → closing`).
6. **Don't expose a synchronous `update()` that fires-and-forgets `saveToStorage`.** RN's `config.ts:76–87` returns synchronously but persists asynchronously via `void this.saveToStorage()`. A crash between in-memory update and disk write loses state. Flutter version should return a `Future<void>` from `update()` that completes after persistence, and the command queue should `await` it.
7. **Don't put two separate expiry tickers on two separate intervals.** RN has `workspaceSyncIntervalId` and `userStateSyncIntervalId` (`workspace/state.ts:9`, `user/state.ts:4`) each ticking every 60s. Unify into one `Timer.periodic` that walks both expiries — half the wakeups, simpler lifecycle management.
8. **Don't ignore the foreground/background lifecycle.** RN's expiry tickers keep running even when the app is backgrounded, wasting battery and occasionally racing with `AsyncStorage` rehydration on resume. In Flutter, observe `WidgetsBindingObserver.didChangeAppLifecycleState` and pause the ticker on `paused`/`inactive`, run an immediate expiry check on `resumed`.
9. **Don't bury error-state recovery in a 10-minute magic number.** RN sets `status.expiresAt = Date.now() + 10 * 60000` in `handleErrorOnFirstSetup` (`setup.ts:407`). Make this a named constant `_errorCooldown = Duration(minutes: 10)` at the top of `setup.dart` so it's discoverable.
10. **Don't bridge JS → host via positional `JSON.parse` of a free-form payload.** RN's `survey-web-view.tsx:171–267` parses, then runs a Zod safeParse, then does five separate `if (onClose) / if (onDisplayCreated) / ...` branches. Replace with a tagged-union `WebViewEvent` Dart class + `sealed class` exhaustive `switch` so adding a new event is a compile error if a handler is missing.
11. **Don't conflate "no userId set" with "no segments matched" in `filterSurveys`.** RN's `utils.ts:128–143` has two early returns that look similar but mean different things — `!userId` returns surveys without segment filters, `!segments.length` returns `[]`. Port the logic, but rename to make the distinction obvious (`_filterAnonymous` vs `_filterIdentifiedWithoutSegments`) and unit-test both branches.
12. **Don't ship without a real example app from day one.** RN's `apps/playground` was added late and is the only thing that catches keyboard/modal/touch regressions before they reach customers. Build `example/` in the first PR.
13. **Don't use exact-pinned plugin versions in the published package**. RN's `package.json` pins every dep exactly (`react: 19.2.4`, `react-native: 0.84.1`) — that is fine for the playground but in `formbricks_flutter` `pubspec.yaml` we should use caret ranges (`webview_flutter: ^4.4.0`) so the SDK doesn't force-downgrade customers' transitive deps.
14. **Don't postpone the rename problem.** RN still references `RNConfig`, `RN_ASYNC_STORAGE_KEY`, etc. in public-adjacent code. Pick Flutter naming up front: types are `FormbricksConfig`, storage key is `formbricks-flutter`, no `Flutter` prefix on internal types (it's redundant inside a Flutter package).
15. **Don't skip the `connectivity_plus`-equivalent guard on `track()`.** RN guards via `@react-native-community/netinfo` (`action.ts:89–101`). Without it, the WebView renders, fails to fetch the surveys script, and the user sees an empty modal with no signal. Mirror the guard in Flutter.

---

## Appendix A — Suggested package layout

```text
formbricks_flutter/
├── lib/
│   ├── formbricks_flutter.dart            # public exports only
│   └── src/
│       ├── common/
│       │   ├── api_client.dart
│       │   ├── command_queue.dart
│       │   ├── config.dart
│       │   ├── expiry_ticker.dart
│       │   ├── filter_surveys.dart
│       │   ├── logger.dart
│       │   └── setup.dart
│       ├── survey/
│       │   ├── action.dart
│       │   └── survey_store.dart
│       ├── user/
│       │   ├── attribute.dart
│       │   ├── update_queue.dart
│       │   └── user.dart
│       ├── workspace/
│       │   └── workspace_state.dart
│       ├── types/
│       │   ├── config.dart
│       │   ├── survey.dart
│       │   ├── action_class.dart
│       │   ├── workspace.dart
│       │   └── result.dart                # Rust-style Result<T, E>, ports types/error.ts
│       └── widgets/
│           ├── formbricks_widget.dart
│           └── survey_webview.dart
├── example/                                # full Flutter app, equivalent of apps/playground
├── test/                                   # unit tests, one file per src/ file
├── integration_test/                       # end-to-end on iOS sim + Android emulator
├── pubspec.yaml
├── CHANGELOG.md
├── LICENSE                                 # MIT, same as RN SDK
└── README.md
```

## Appendix B — Parity matrix vs RN SDK

| Feature | RN | Flutter v1 |
|---|---|---|
| `setup({appUrl, workspaceId})` | ✓ | ✓ |
| Backward-compat `environmentId` alias | ✓ (deprecated) | ✗ (intentional) |
| `track(name)` with action-class lookup | ✓ | ✓ |
| `setUserId` with previous-user teardown | ✓ | ✓ |
| `setAttribute` / `setAttributes` (string, number, Date) | ✓ | ✓ (String, num, DateTime) |
| `setLanguage` w/o userId → local-only update | ✓ | ✓ |
| `logout` → reset user state | ✓ | ✓ |
| Workspace state cache + 60s expiry ticker | ✓ | ✓ (unified ticker) |
| User state 30 min expiry refresh | ✓ | ✓ |
| `displayOption` filtering (4 modes) | ✓ | ✓ |
| `recontactDays` (per-survey + workspace fallback) | ✓ | ✓ |
| `displayPercentage` gate | ✓ | ✓ |
| Segment filtering (anonymous + identified) | ✓ | ✓ |
| Multi-language survey resolution | ✓ | ✓ |
| Error-state 10-min cooldown after setup fail | ✓ | ✓ (named constant) |
| Same-origin WebView nav, external links via `url_launcher` | ✓ (`Linking`) | ✓ |
| `displayPercentage`-style soft randomness | ✓ | ✓ |
| Survey file upload | ✗ (stubbed) | ✗ (out of scope) |
| Encrypted storage by default | ✗ | ✗ (opt-in slot) |
| Offline response queue | ✗ (delegated to WebView) | ✗ (same delegation) |
