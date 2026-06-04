# Playground

Demo / manual-QA app for the [`formbricks_flutter`](../../packages/formbricks_flutter)
SDK. Targets iOS + Android.

It calls `Formbricks.setup` on launch (reading `APP_URL` / `WORKSPACE_ID` from
`--dart-define`, mirroring the React Native playground's env vars) and shows the
setup status. The six SDK-test buttons (track / setUserId / setAttributes ×2 /
setLanguage / logout) are inert stubs until the rest of the API lands; each shows
a "not wired to the SDK yet" snackbar.

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
