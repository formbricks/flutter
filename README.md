# Formbricks Flutter

Monorepo for the first-party **Flutter SDK** for [Formbricks](https://formbricks.com)
and its demo app. The SDK mirrors the [React Native SDK](https://github.com/formbricks/react-native):
initialize a workspace, identify users, track actions, and render targeted in-app
surveys inside a WebView backed by `{appUrl}/js/surveys.umd.cjs`.

> **Status:** repository skeleton. The SDK currently exposes only a placeholder
> `welcome()`. The public API, survey rendering, CI, and pub.dev publishing land
> in follow-up work — see [Roadmap](#roadmap).

## Quick Start

Run commands from the repo root unless a step says otherwise.

### 1. Install platform prerequisites

FVM installs the Flutter SDK for this project, but you still need the native
tooling for the platform you want to run:

- **iOS simulator:** macOS with Xcode installed. Also run
  `xcode-select --install` once so command-line tools are available.
- **Android emulator:** Android Studio with the Android SDK, Platform Tools,
  and at least one Android Virtual Device (AVD) created in Device Manager.

If you only plan to run one platform, you only need that platform's tooling.

### 2. Install FVM

FVM reads `.fvmrc` and downloads the exact Flutter version used by this repo.
On macOS, Homebrew is the easiest install path:

```bash
brew tap leoafarias/fvm
brew install fvm
```

If you already have Dart on your machine, this also works:

```bash
dart pub global activate fvm
```

### 3. Install the pinned Flutter SDK

```bash
fvm install
make doctor
```

`fvm install` downloads the Flutter version from `.fvmrc` (currently `3.44.0`).
`make doctor` checks the local iOS/Android tooling with the pinned Flutter SDK.
Fix the red `✗` items for the platform you want to run, then run the doctor
command again.

### 4. Fetch dependencies

```bash
make deps
```

This resolves the whole Dart pub workspace from the root `pubspec.yaml` and
uses the shared `pubspec.lock`.

### 5. Run the playground app

```bash
make run            # iOS simulator, default
make run android    # Android emulator
```

The Makefile delegates to `tool/run.sh`, boots a simulator/emulator when it can,
then runs `apps/playground`. Once the app is running, press `r` for hot reload,
`R` for hot restart, and `q` to quit.

You should see a **"Welcome to Formbricks"** header and six SDK-test buttons
(track / setUserId / setAttributes ×2 / setLanguage / logout). They are inert
stubs — each shows a "not wired to the SDK yet" snackbar — until the SDK API
lands in follow-up work.

## Repository layout

```
flutter/
├── pubspec.yaml                 # pub workspace root + Melos script config (never published)
├── Makefile                     # daily dev + CI command entry point
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

All run from the repo root. Use the Makefile for normal development; it uses
`fvm flutter` / `fvm dart` when FVM is installed and falls back to `flutter` /
`dart` from `PATH` otherwise.

```bash
make help          # list available targets
make deps          # resolve the whole workspace (one lockfile)
make format        # format Dart code
make format-check  # CI-style formatting check
make analyze       # analyze all packages
make test          # run tests in packages that have test/
make coverage      # run tests with coverage
make check         # format-check + analyze + test
```

Important daily commands:

```bash
make deps
make run
make run android
make format
make analyze
make test
make check
```

CI/parity targets are also available when you need to reproduce workflow steps:

```bash
make deps-lockfile
make analyze-ci
make test-sdk-machine
make test-sdk-coverage
make test-playground
make build-android
make build-ios-no-codesign
make pana-install
make pana
make pub-publish-dry-run
```

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

## Toolchain details

The exact Flutter version is pinned in **`.fvmrc`** and managed with
[fvm](https://fvm.app). Pinning means every contributor and CI run uses the same
SDK version.

- FVM downloads Flutter into its own cache under `~/fvm/versions/`; you do not
  clone Flutter by hand.
- `.fvm/flutter_sdk` is a local symlink to the active SDK and is git-ignored.
  Only `.fvmrc` is committed.
- Editors should use `.fvm/flutter_sdk` as the Flutter/Dart SDK path so analysis
  and code completion use the pinned SDK.
- Bump the repo's Flutter version with `fvm use <version> --force`, then commit
  the changed `.fvmrc`.
- Floors: published SDK = Flutter ≥ 3.27 / Dart ≥ 3.6; dev tooling pins a newer SDK via `.fvmrc`.

## Running the demo app

The playground targets **iOS + Android only** — there is no `macos/`/`web/`
project. Note that `flutter run` cannot boot a simulator on its own: with no
device running it falls back to the macOS desktop target (which this app does
not support), so a simulator/emulator must be started first.

### One-command run

```bash
make run            # iOS simulator (default)
make run android    # Android emulator
```

Or call the underlying script directly after `make deps`:

```bash
./tool/run.sh
./tool/run.sh android
```

### Device checks

Use these commands when the run script cannot find a device:

```bash
make emulators   # configured simulators/emulators Flutter can launch
make devices     # currently running simulators/emulators/devices
```

For Android, if no emulator appears in `make emulators`, create an AVD in
Android Studio's Device Manager first.

### Manual CLI run

A simulator/emulator must be booted *first* — `flutter run` never boots one
itself. Start a device, then target it by id or name substring:

```bash
fvm flutter emulators --launch apple_ios_simulator   # iOS sim
# or: fvm flutter emulators --launch Pixel_9a         # Android emulator
cd apps/playground
fvm flutter run -d iphone        # iOS, if the simulator name contains "iphone"
fvm flutter run -d emulator      # Android, if the emulator id contains "emulator"
```

`-d` matches a device id or name substring, not a platform name. For example,
`-d ios` does not mean "run on iOS".

First Android build is slow because Gradle downloads the NDK and CMake
(approximately 3 GB, one-time). Subsequent builds reuse them.

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
