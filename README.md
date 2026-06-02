# Formbricks Flutter

Monorepo for the first-party **Flutter SDK** for [Formbricks](https://formbricks.com)
and its demo app. The SDK mirrors the [React Native SDK](https://github.com/formbricks/react-native):
initialize a workspace, identify users, track actions, and render targeted in-app
surveys inside a WebView backed by `{appUrl}/js/surveys.umd.cjs`.

> **Status:** repository skeleton. The SDK currently exposes only a placeholder
> `welcome()`. The public API, survey rendering, CI, and pub.dev publishing land
> in follow-up work — see [Roadmap](#roadmap).

## Repository layout

```
flutter/
├── pubspec.yaml                 # pub workspace root + Melos script config (never published)
├── analysis_options.yaml        # shared analyzer + lint rules for every package
├── sonar-project.properties     # SonarCloud config (finalised in a follow-up)
├── LICENSE                      # MIT
├── packages/
│   └── formbricks_flutter/      # the SDK package (the thing we publish)
│       ├── lib/
│       │   ├── formbricks_flutter.dart   # public exports
│       │   └── src/                       # (added in implementation tickets)
│       ├── test/                          # one test file per source file
│       ├── pubspec.yaml
│       ├── CHANGELOG.md
│       ├── LICENSE
│       └── README.md
└── apps/
    └── playground/              # demo / manual-QA app (equivalent of RN's apps/playground)
        ├── lib/main.dart        # SDK test buttons: track, setUserId, setAttributes, …
        ├── android/  ios/       # platform projects (iOS + Android only for v1)
        ├── test/
        └── pubspec.yaml
```

This mirrors the RN repo's `packages/*` + `apps/*` split, so anyone moving
between the two SDKs finds the same shape.

### Why these locations

| Path | Holds | Rationale |
|------|-------|-----------|
| `packages/formbricks_flutter` | The publishable SDK | Single source of the pub.dev package. `src/` is private; only `lib/formbricks_flutter.dart` re-exports the public API. |
| `apps/playground` | Demo app | Real Flutter app on iOS + Android for manual QA of WebView / keyboard / modal behaviour. Excluded from SonarCloud + pub scoring. The RN SDK proved this app is what catches keyboard/touch regressions before customers do, so it ships from day one. |

## Monorepo tooling

Uses **Dart pub workspaces** (Dart ≥ 3.6) + **[Melos](https://melos.invertase.dev) 7**.

- The root `pubspec.yaml` declares `workspace:` members. Each member sets
  `resolution: workspace`, so the whole repo shares **one** lockfile and one
  resolved dependency graph — no version drift between SDK and demo app.
- Melos 7 sits on top of native workspaces and adds cross-package scripts
  (analyze / test / format across everything at once). Its config lives under
  the `melos:` key in the root `pubspec.yaml` (Melos 7 dropped `melos.yaml`).

### Common commands

All run from the repo root. The Flutter version is pinned with **fvm** (see
[Toolchain](#toolchain)), so prefix Flutter/Dart calls with `fvm` to use the
exact pinned SDK:

```bash
fvm flutter pub get              # resolve the whole workspace (one lockfile)
fvm dart run melos run analyze   # dart analyze --fatal-infos across all packages
fvm dart run melos run format    # dart format .
fvm dart run melos run format-check          # CI: fail if unformatted
fvm dart run melos run test --no-select      # flutter test in every package
fvm dart run melos run test-coverage --no-select
```

> - `--no-select` skips Melos's interactive package picker — required in CI and
>   any non-TTY shell.
> - `fvm dart run melos` runs the workspace's pinned Melos under the pinned SDK.
>   If you prefer the global `melos` binary (`dart pub global activate melos`),
>   run it as `fvm exec melos run …` so it still uses the pinned Flutter.

## Conventions

These are locked in for all follow-up work (full rationale in the RN repo's
`FLUTTER_SDK_PLAN.md`):

- **Naming.** Internal types are `FormbricksConfig`, `Logger`, etc. — no
  redundant `Flutter` prefix inside a Flutter package. Storage key is
  `formbricks-flutter` (distinct from RN's `formbricks-react-native`).
- **Static public API, hidden singleton.** `Formbricks.track(...)` /
  `Formbricks.setup(...)` are static facades over a private singleton — **not**
  `Formbricks.instance.track(...)`. The host widget and static API share the
  one `Formbricks` class.
- **No `environmentId`.** The SDK accepts `workspaceId` only — no legacy alias
  to ever deprecate (RN still carries that debt).
- **Dates cross one boundary.** `DateTime` in memory, ISO-8601 `String` on the
  wire and on disk; convert only in `fromJson` / `toJson`. No stray
  `DateTime.parse` elsewhere.
- **Testing is mandatory.** Every source file gets a dedicated test file (happy
  path + errors + edge cases). PRs aren't mergeable without it; aim for ≥ 80 %
  coverage on touched files. Unit tests use `flutter_test` + `mocktail` /
  `http`'s `MockClient` — no real network.
- **Targets.** iOS + Android only for v1. A `kIsWeb` guard throws on Flutter Web.

## Toolchain

The exact Flutter version is pinned in **`.fvmrc`** (currently `3.44.0`, which
ships Dart 3.12) and managed with [fvm](https://fvm.app). Pinning means every
contributor and CI run uses a byte-identical SDK — no "works on my machine"
version drift.

First-time setup:

```bash
dart pub global activate fvm     # install the fvm tool (one-time, global)
fvm install                      # download the version from .fvmrc into fvm's cache
fvm flutter pub get              # resolve the workspace
```

- fvm itself needs a Dart/Flutter on `PATH` only to bootstrap; it then downloads
  and isolates the pinned Flutter under `~/fvm/versions/` — you don't clone
  Flutter by hand. `.fvm/flutter_sdk` (a symlink to the active version) and the
  version cache are git-ignored; only `.fvmrc` is committed.
- Editors: point your editor's Flutter/Dart SDK path at `.fvm/flutter_sdk` so
  analysis uses the pinned SDK.
- Bumping the version: `fvm use <version> --force`, commit the changed `.fvmrc`.
- fvm docs: <https://fvm.app>. Flutter floor enforced by pubspecs: ≥ 3.22 / Dart
  ≥ 3.12.

## Running the demo app

The playground targets **iOS + Android only** — there is no `macos/`/`web/`
project. Note that `flutter run` cannot boot a simulator on its own: with no
device running it falls back to the macOS desktop target (which this app does
not support), so a simulator/emulator must be started first.

**Easiest — one command** (boots the device if needed, then runs):

```bash
# one-time: copy the template and fill in your workspace credentials
cp apps/playground/.env.example apps/playground/.env

./tool/run.sh            # iOS simulator (default)
./tool/run.sh android    # Android emulator
# or via Melos (package.json-style scripts, see Monorepo tooling):
melos run ios
melos run android
```

`tool/run.sh` auto-passes `apps/playground/.env` to the app via
`--dart-define-from-file` (the `.env` is git-ignored). You can still override
with explicit `--dart-define=APP_URL=… --dart-define=WORKSPACE_ID=…` flags.

**Manual CLI:** a simulator/emulator must be booted *first* — `flutter run`
never boots one itself. Start a device, then target it by name:

```bash
fvm flutter emulators --launch apple_ios_simulator   # iOS sim
# or: fvm flutter emulators --launch Pixel_9a         # Android emulator
cd apps/playground
fvm flutter run -d iphone        # iOS;  -d emulator  for Android.
                                 # -d matches a device NAME/id substring, NOT the
                                 # platform — `-d ios` will NOT match, and with no
                                 # device booted this falls back to the
                                 # (unsupported) macOS desktop target.
```

> First Android build is slow — Gradle downloads the NDK + CMake (~3 GB,
> one-time) before compiling. Subsequent builds reuse them.

Once running, the `flutter run` session is interactive: press **`r`** for hot
reload, **`R`** for hot restart, **`q`** to quit. `./tool/run.sh` keeps that
session in your terminal, so hot reload works there too.

You should see a **"Welcome to Formbricks"** header and six SDK-test buttons
(track / setUserId / setAttributes ×2 / setLanguage / logout). They are inert
stubs — each shows a "not wired to the SDK yet" snackbar — until the SDK API
lands in follow-up work.

## Roadmap

| Stage | Scope |
|-------|-------|
| Repo + monorepo skeleton | This ✅ |
| `setup` + command queue | `setup` function, `CommandQueue`, `FormbricksConfig`, `ApiClient` |
| Track + show survey | `track` + survey rendering (WebView) |
| CI | GitHub Actions (format / analyze / test / build) |
| Code quality | SonarCloud wiring + quality gate |

The canonical spec and the React-Native→Flutter architecture mapping live in
[`docs/FLUTTER_SDK_PLAN.md`](docs/FLUTTER_SDK_PLAN.md). The reference RN source is
the `formbricks/react-native` repo.
