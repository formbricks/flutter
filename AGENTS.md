# Repository Guidelines

## Project Structure & Module Organization

- This repository is a Dart pub workspace (root `pubspec.yaml`) managed with Melos, with one shared `pubspec.lock`. The Flutter version is pinned in `.fvmrc` and used through FVM.
- The published SDK, the `formbricks` package on pub.dev, lives in `packages/formbricks`. Its public entry point is `lib/formbricks.dart`; the implementation lives in `lib/src` (`common`, `survey`, `types`, `user`, `widgets`), and tests mirror that layout under `test/`.
- The demo app lives in `apps/playground` and exercises the SDK on an iOS simulator or Android emulator. Its Patrol golden journey lives in `apps/playground/patrol_test`.
- `e2e/` holds the E2E harness: `e2e/server` (a published Formbricks server in Docker), `e2e/tunnel` (exposes it to the macOS iOS runners) and `e2e/flutter` (runs the journey).
- `.github/scripts` and `tool/` hold the release, PR Check Summary and run scripts, with their `*_test.sh` tests.
- Generated output such as `build/`, `.dart_tool/`, `coverage/` and `test-results/` should not be edited by hand.

## Build, Test, and Development Commands

Run commands from the repo root. The `Makefile` wraps everything and uses `fvm` when it is installed.

- `make deps` fetches workspace dependencies; `make deps-lockfile` (what CI runs) fails instead of changing `pubspec.lock`.
- `make run` / `make run android` runs the playground on an iOS simulator or Android emulator.
- `make analyze-ci` runs `flutter analyze --fatal-infos --fatal-warnings`; infos and warnings fail it. `make analyze` is the `dart analyze` equivalent.
- `make format-check` checks Dart formatting (`dart format`) and Markdown formatting (Prettier); `make format` fixes both.
- `make test-sdk-machine` runs the SDK tests with coverage; `make test-playground` runs the playground tests; `make test` runs every package with a `test/` dir.
- `make build-android` / `make build-ios-no-codesign` build the playground debug app.
- `make pub-publish-dry-run` and `make pana` check the package as pub.dev will see it.
- `make script-tests` runs the shell-script tests; `make shellcheck` lints the scripts.
- E2E (`.github/workflows/e2e.yml`, job `e2e-tests`): `e2e/server/up.sh` and `seed.sh` boot and seed the server (needs `ENTERPRISE_LICENSE_KEY`), `e2e/flutter/run-journey.sh` runs the golden journey on Android or iOS, then `e2e/server/assert-response.sh`, `cleanup.sh` and `down.sh`.

## Coding Style & Naming Conventions

- `analysis_options.yaml` is the shared lint config (`flutter_lints` with strict casts, inference and raw types, plus `prefer_single_quotes`) for every package.
- CI runs every check in `.github/workflows/ci.yml`; `PR Check Summary` is the one required check.
- Format with `dart format`; Markdown is formatted with Prettier.
- Keep public exports in `packages/formbricks/lib/formbricks.dart`.
- Tests follow the source name, for example `lib/src/common/filter_surveys.dart` → `test/common/filter_surveys_test.dart`.

## Commit & Pull Request Guidelines

- Commits and PR titles follow Conventional Commits, such as `fix: …`, `feat: …` or `chore(deps): …`. The `PR Title` workflow checks PR titles, and release notes are built from them.
- Keep commit subjects short and imperative.
- Don't bump the version in a PR; see `RELEASING.md`.
- PRs should explain the behavioral change and note affected packages (`packages/formbricks`, `apps/playground`, or both), and link the Linear issue (`Fixes ENG-1234`).

## Agent skills

### Issue tracker

Linear, Engineering team (`ENG`); skills use the Linear MCP tools. See `docs/agents/issue-tracker.md`.

### Triage labels

No triage labels: the five roles map onto Linear workflow states. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the repo root and ADRs in `docs/adr/`. See `docs/agents/domain.md`.
