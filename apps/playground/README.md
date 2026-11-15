# Playground

Demo / manual-QA app for the [`formbricks`](../../packages/formbricks)
SDK. Targets iOS + Android.

It calls `Formbricks.setup` on launch (reading `APP_URL` / `WORKSPACE_ID` from
`--dart-define`) and shows the connection status. Once connected, use the
"Trigger Code Action" button and the identity buttons (setUserId / setAttributes
/ setAttribute / setLanguage / logout) to drive the SDK against a real workspace;
the local-storage buttons inspect and clear the persisted config.

## Run

Put your workspace credentials in a local `.env` (git-ignored) once:

```bash
cp apps/playground/.env.example apps/playground/.env
# then edit APP_URL / WORKSPACE_ID
```

Then from the repo root (`tool/run.sh` boots a device if none is running and
auto-passes the `.env` via `--dart-define-from-file`):

```bash
./tool/run.sh            # iOS simulator
./tool/run.sh android    # Android emulator
```

Prefer one-off flags? Pass them directly (they override the `.env`):

```bash
./tool/run.sh ios --dart-define=APP_URL=https://app.formbricks.com \
                  --dart-define=WORKSPACE_ID=wsp_...
```

Without any credentials the app still runs but shows a "Missing APP_URL /
WORKSPACE_ID" status and skips setup. See the repo root README for full toolchain
details.

## E2E golden journey (Patrol)

`patrol_test/golden_journey_test.dart` is the SDK golden journey that every
Formbricks SDK runs in CI: set up, `setUserId`, `setAttribute(plan, pro)`,
`track('qa-action')`, then answer the survey (NPS 9, feedback, Finish, close).
Patrol drives the Flutter widgets and, through UiAutomator / XCUITest, the
survey inside the SDK's native WebView. `.github/workflows/e2e.yml` runs it on
an Android emulator and an iOS simulator against a seeded server
(`e2e/server`); see `e2e/flutter/run-journey.sh` for the commands.

Run it locally against a server you seeded with `e2e/server/up.sh` and
`seed.sh`, with the [Patrol CLI](https://patrol.leancode.co) installed:

```bash
E2E_USER_ID=me E2E_FEEDBACK=hello e2e/flutter/run-journey.sh android   # emulator running
E2E_USER_ID=me E2E_FEEDBACK=hello e2e/flutter/run-journey.sh ios-build
E2E_USER_ID=me E2E_FEEDBACK=hello E2E_APP_URL=http://localhost:3000 \
  e2e/flutter/run-journey.sh ios
```

`patrol_test/survey_filtering_qa_test.dart` holds the manual survey-filtering
QA scenarios; it runs only when you pass `SURVEY_ID` (see its header).
