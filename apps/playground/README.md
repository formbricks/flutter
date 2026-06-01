# Playground

Demo / manual-QA app for the [`formbricks_flutter`](../../packages/formbricks_flutter)
SDK. Targets iOS + Android.

Right now it renders a "Welcome to Formbricks" header and six SDK-test buttons
(track / setUserId / setAttributes ×2 / setLanguage / logout). The buttons are
inert stubs until the SDK API lands; each shows a "not wired to the SDK yet"
snackbar.

## Run

From the repo root (a simulator/emulator must be booted — `flutter run` won't
boot one itself):

```bash
./tool/run.sh            # iOS simulator (boots one if needed)
./tool/run.sh android    # Android emulator (boots one if needed)
```

See the repo root README for full toolchain + run details.
