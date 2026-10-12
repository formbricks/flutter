# Dependency security

How this repository inventories, scans and triages the dependencies used to
build, test and release the Formbricks Flutter SDK, what is covered, and what is
not.

## At a glance

| Question                                                  | Answer                                                                                                                                                                                                                                     |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Does the published `formbricks` package ship native code? | No. It is a Dart-only package (`flutter pub publish --dry-run` lists `lib/`, `test/`, docs and metadata; no `android/` or `ios/`). Native code arrives through the federated plugins it depends on, which the **consumer's** app resolves. |
| Where do Pub vulnerabilities come from?                   | GitHub's dependency graph parses the root `pubspec.lock` automatically; Dependabot alerts cover it. All 86 hosted packages were verified present.                                                                                          |
| Where do Android/Maven vulnerabilities come from?         | Not detected automatically. The `Dependency Submission` workflow resolves the playground's Gradle build, validates the result and submits it to the dependency graph.                                                                      |
| How do I check a release candidate?                       | Run the `Release Dependency Assessment` workflow for the exact ref/SHA. It is independent of default-branch alert counts. See [Release candidate assessment](#release-candidate-assessment).                                               |
| Is anything dismissed or accepted automatically?          | Never. Exceptions are human-authored entries in `.github/dependency-exceptions.json`; alert dismissal is a manual action in GitHub.                                                                                                        |

## Inventory

Verified against `main` at `7345fa5620bc9455a743e73131f926b69584b1e9`.

### SDK runtime (what consumers get)

`packages/formbricks/pubspec.yaml` declares: `http`, `shared_preferences`,
`clock`, `webview_flutter`, `webview_flutter_android`, `url_launcher`,
`connectivity_plus` (plus dev-only `flutter_test`, `flutter_lints`, `mocktail`,
`fake_async`). All resolve through the single workspace lockfile `pubspec.lock`
(86 hosted packages, including transitive ones and workspace tooling such as
Melos).

Consumers' Android builds pull native libraries through four plugins whose
`android/` projects Gradle includes: `connectivity_plus`,
`shared_preferences_android`, `url_launcher_android`, `webview_flutter_android`
(for example `androidx.core`, `androidx.datastore`, `androidx.browser`,
`androidx.webkit`). The playground's resolution of these is the best available
proxy for what a consumer app ships; the consumer's own Android Gradle Plugin,
Kotlin version and other plugins are theirs.

### Native

| Platform | Source of truth                                                                                                                              | Third-party native dependencies                                                                                                                                                                                                                        | Coverage                                                                                            |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| Android  | `apps/playground/android` (Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20) plus the four plugin projects above                                       | 731 Maven artifacts resolved in total: 115 on the app runtime classpath (debug + release), 616 build tooling (AGP and plugin build-script classpaths)                                                                                                  | `Dependency Submission` workflow + release assessment (this document)                               |
| iOS      | `apps/playground/ios`; Swift Package Manager (generated `FlutterGeneratedPluginSwiftPackage`), no `Podfile`, no committed `Package.resolved` | None found. All four iOS plugins (`connectivity_plus`, `shared_preferences_foundation`, `url_launcher_ios`, `webview_flutter_wkwebview`) ship a `Package.swift` whose only dependency is Flutter's own framework package (`FlutterFramework`) or none. | Nothing to submit. Limitation: the Flutter engine, Xcode and Apple frameworks are not in any graph. |

The iOS CI job caches `apps/playground/ios/Pods` and keys it on
`ios/Podfile.lock`, neither of which exists with Swift Package Manager; that
cache step is vestigial.

### Build, test and publish

| Item                                                          | Where                                                                                  | Covered by                                                                                                  |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Pub dev tooling (Melos, `flutter_lints`, `mocktail`, …)       | `pubspec.lock`                                                                         | GitHub dependency graph (Pub)                                                                               |
| GitHub Actions                                                | `.github/workflows`, `.github/actions` (all pinned to commit SHAs)                     | Dependabot `github-actions`                                                                                 |
| Gradle build plugins and Gradle wrapper version               | `apps/playground/android/settings.gradle.kts`, `gradle-wrapper.properties`             | Dependabot `gradle`; plugin artifacts are in the Gradle snapshot; wrapper JAR checked by wrapper validation |
| Flutter SDK                                                   | `.fvmrc` (3.47.7), installed by `subosito/flutter-action`                              | **Not scanned.** Version-pinned; bumped by hand.                                                            |
| `pana`                                                        | `make pana-install` (`dart pub global activate pana`, unpinned) in the Pana workflow   | **Not scanned.** CI-only; does not touch the published artifact.                                            |
| `prettier@3.6.2`                                              | `make format-docs-check` via `npx -y`; its transitive npm packages resolve at run time | **Not scanned.** CI-only.                                                                                   |
| SonarQube scan action, runner images, JDK, Android SDK, Xcode | Workflows / GitHub-hosted runners                                                      | Action is Dependabot-tracked; runner image contents are GitHub's.                                           |

### Playground and tests

`apps/playground` is `publish_to: none`; it is not part of the pub.dev release.
The release workflow (`.github/workflows/release.yml`) formats, analyzes, runs
SDK and playground tests, does a publish dry run and publishes the Dart package.
The Android/iOS playground builds (`build.yml`) are separate CI jobs and
**do not** gate the release. Their dependency graph still matters for two
reasons: it is the only place the SDK's transitive native libraries are
resolved in this repo, and build-tool vulnerabilities can compromise CI.

## How Gradle coverage works

`Dependency Submission` (`.github/workflows/dependency-submission.yml`) runs on
pushes to `main`, weekly (to refresh resolution) and on demand:

1. **`collect` job (read-only token).** Reuses the composite action
   `.github/actions/gradle-dependency-snapshot`:
   - sets up JDK 17 and the pinned Flutter SDK; `make deps-lockfile` writes
     `local.properties` and `.flutter-plugins-dependencies` so Gradle can include
     the Flutter plugin projects;
   - validates the Gradle wrapper, then runs
     `gradle/actions/dependency-submission` in `generate` mode (Gradle resolves
     everything; the GitHub Dependency Graph Gradle Plugin records it; nothing is
     submitted or cached);
   - resolves `:app:dependencies` for `releaseRuntimeClasspath` and
     `debugRuntimeClasspath` as an independent view of what Gradle resolved;
   - validates the snapshot (below) and runs the assessment;
   - uploads `dependency-evidence-<sha>` (90-day retention).
2. **`submit` job (`contents: write`, runs no repository code).** Downloads that
   evidence, re-checks the snapshot is bound to this exact SHA and ref and is not
   trivially small, and posts it to the Dependency Submission API. It only runs
   on the default branch; dispatching from another branch is a dry run.

Third-party Gradle build scripts execute in `collect`, which therefore never
holds a write token.

### What "complete" means

`tool/dependency_inventory.dart` refuses to call an inventory complete unless:

- the snapshot exists, parses, and its `sha` equals the commit being assessed
  (stale or wrong-commit snapshots are rejected);
- it contains at least 100 Maven components and the coordinates that any real
  playground build resolves (Android Gradle Plugin, Kotlin Gradle Plugin, Flutter
  engine embedding, `androidx.webkit`);
- every library declared literally in each Android plugin's `build.gradle` (the
  plugin list comes from `.flutter-plugins-dependencies`) is in the graph, which
  proves the plugin projects, not only the app module, were resolved;
- every dependency Gradle itself reports on the app's debug and release runtime
  classpaths is present in the snapshot at the same version;
- `pubspec.lock` yields hosted packages and no git-sourced packages;
- the exception register (if any entries) is valid;
- every component was successfully looked up in OSV.

Any failure makes the result **INCOMPLETE**. An incomplete result is never
reported as clean: the workflow fails, `assessment.md` says "NOT a clean result",
and `assessment.json` has `"cleanResult": false`.

Verdicts and exit codes:

| Verdict      | Exit | Meaning                                                                                        |
| ------------ | ---- | ---------------------------------------------------------------------------------------------- |
| `PASS`       | 0    | Complete inventory; no High/Critical/unrated advisory without an active exception.             |
| `FINDINGS`   | 1    | Complete inventory; at least one High/Critical/unrated advisory needs a human decision.        |
| `INCOMPLETE` | 2    | Collection, cross-check or advisory lookup failed. **Not clean.** Fix the pipeline and re-run. |

Severity comes from the advisory's `database_specific.severity` (GitHub
Security Advisories) or, failing that, a CVSS v3 base score. An advisory with
neither is **unrated** and treated as blocking until a human rates or excepts it.
Medium and Low advisories are listed but do not block.

### Evidence

Every run uploads `dependency-evidence-<full sha>`:

| File                                           | Contents                                                                                  |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `assessment.json` / `assessment.md`            | Commit SHA, timestamp, verdict, problems, counts, every advisory with scope, input hashes |
| `inventory.json`                               | Every component (ecosystem, name, version, scope) that was checked                        |
| `gradle-snapshot/*.json`                       | The exact dependency-graph snapshot (carries the commit SHA, ref, scan time)              |
| `gradle-{release,debug}-runtime-classpath.txt` | Gradle's own resolution used for the cross-check                                          |

Scopes: `app-runtime` (on the playground's runtime classpath), `build-tooling`
(any other Gradle-resolved artifact: AGP internals, plugin classpaths) and `pub`.
Pub packages are not split into runtime/dev; check `pubspec.lock`
(`dependency: direct main | direct dev | transitive`).

## Release candidate assessment

To assess the exact commit you intend to release:

1. Actions → **Release Dependency Assessment** → _Run workflow_, with the
   release candidate branch, tag or full commit SHA.
2. Read the job summary and `dependency-evidence-<sha>`. The run fails for
   `FINDINGS` and for `INCOMPLETE`.
3. Record the outcome (green run URL, or the decisions below) in the release
   issue/PR.

The candidate must contain this tooling, since it is checked out and run as-is.
This assessment is independent of default-branch Dependabot alert counts; it
inspects the resolved inventory of that SHA.

To reproduce locally from downloaded evidence (no Android SDK needed):

```bash
unzip dependency-evidence-<sha>.zip -d /tmp/evidence
git checkout <sha>
make deps-lockfile
dart run tool/dependency_inventory.dart assess \
  --sha "$(git rev-parse HEAD)" \
  --gradle-snapshot /tmp/evidence/gradle-snapshot \
  --runtime-classpath /tmp/evidence/gradle-release-runtime-classpath.txt \
  --runtime-classpath /tmp/evidence/gradle-debug-runtime-classpath.txt \
  --out /tmp/assessment
```

`make test-tools` runs the tool's tests.

## Handling findings

### Where findings surface

- **Dependabot alerts** (Security tab) once the Gradle snapshot is in the graph
  and for Pub packages. These are per default branch.
- **`Dependency Submission` runs** (push, weekly): a High/Critical/unrated finding
  emits a warning annotation and a job summary but does not fail the run; an
  `INCOMPLETE` inventory fails it.
- **`Release Dependency Assessment`** for a specific commit (fails on findings).
- **`Dependency Review`** on pull requests: fails when a PR introduces a
  High/Critical vulnerability in Pub packages.

### Triage

Each High/Critical finding needs a human decision. Nothing here is automatic.

1. **Locate it.** Find the `scope` in `assessment.md`. For Gradle artifacts, trace
   the source (from `apps/playground/android`, after `make deps-lockfile`):

   ```bash
   ./gradlew :app:dependencyInsight --configuration releaseRuntimeClasspath --dependency <group:artifact>
   ./gradlew :<plugin-project>:buildEnvironment | grep -C 5 <artifact>   # plugin/AGP classpath
   ```

2. **Classify.**
   - `app-runtime` or `pub`: a runtime exposure for apps built from this SDK.
     Fix before release (bump the plugin/package, or add a constraint).
   - `build-tooling`: not on the app runtime classpath; the exposure is to the
     build/CI environment (for example Android Gradle Plugin internals). Still
     assess it: is the vulnerable code reachable from our build, does the build
     process untrusted input, can the AGP/Flutter version be bumped?
3. **Decide and record.** Either:
   - **Fix:** bump the dependency (Dependabot PR, Flutter/AGP upgrade, or a
     Gradle dependency constraint). The next run is the evidence.
   - **Exception:** open a PR adding an entry to
     `.github/dependency-exceptions.json`:

     ```json
     {
       "exceptions": [
         {
           "advisory": "GHSA-xxxx-xxxx-xxxx",
           "package": "io.netty:netty-codec-http2",
           "reason": "Build tooling only (AGP); not on app runtime classpath; no untrusted HTTP/2 input in our build. Tracked in ENG-1234.",
           "approvedBy": "@github-handle",
           "expires": "2027-01-15"
         }
       ]
     }
     ```

     All fields are required. The exception matches the advisory ID or any alias
     for that package name, applies to every version of it, must expire within 180
     days, and stops being honored after `expires`. Active exceptions stay visible in
     every report. A PR that adds one needs a human reviewer; the tooling never
     writes this file.

   - **Dismiss the Dependabot alert** in GitHub with an accurate reason, only
     as a human decision. Nothing in this repo dismisses alerts.

An invalid register, an expired entry, or an exception with no matching finding
never silently clears anything: invalid registers make the run INCOMPLETE and
expired entries are reported as expired.

## Limitations and follow-ups

- **Pull requests are not covered for Gradle.** `Dependency Review` sees Pub
  changes only. Generating PR snapshots needs a split design: generate with a
  read-only token on `pull_request`, then submit from a privileged
  `workflow_run` job. That job must verify the artifact's `sha` equals the PR head
  SHA and its `ref` is `refs/pull/<n>/merge`/head. A forged snapshot with the
  default branch's SHA and ref would otherwise overwrite the default-branch graph.
  Not implemented here to avoid shipping that risk untested.
- **The advisory data source for the assessment is OSV** (which mirrors GitHub
  Security Advisories). It can differ from Dependabot's view; treat a difference
  as a prompt to investigate, not as proof either way.
- **Scope split is by classpath.** `build-tooling` means "not on the debug/release
  runtime classpath of `:app`", not "harmless".
- **Not scanned:** Flutter SDK, Gradle distribution, JDK, Android SDK, Xcode,
  `pana`, `prettier`'s npm tree and runner images (see
  [Build, test and publish](#build-test-and-publish)). Possible follow-ups: pin
  and lock `pana`, add an npm lockfile for `prettier`, and track the Flutter SDK
  version against Flutter security advisories.
- **iOS** has no third-party native dependencies today. If a plugin adds a
  CocoaPod or Swift package, commit `Podfile.lock` / `Package.resolved` (or add a
  macOS snapshot job) so GitHub's graph can see it.
- **Gradle coverage is only as fresh as the last successful submission.** The
  weekly run refreshes it; if that run fails, the graph is stale and the failed
  run is the signal. Treat a failing `Dependency Submission` run as an open
  security task.
- **The Dependabot `gradle` entry** keeps plugin versions in
  `settings.gradle.kts` current, but Dependabot cannot see versions resolved
  inside Flutter plugin projects; that is what the snapshot is for.
