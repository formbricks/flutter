# Dependency security

Which dependencies of the Formbricks Flutter SDK are scanned for known
vulnerabilities, how, and what to do with a finding.

## At a glance

| Question                                                  | Answer                                                                                                                                                                                   |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Does the published `formbricks` package ship native code? | No. It is Dart-only (`flutter pub publish --dry-run` lists `lib/`, docs and metadata; no `android/` or `ios/`). Native code comes from the plugins it depends on, in the consumer's app. |
| Where do Pub vulnerabilities come from?                   | GitHub's dependency graph reads the root `pubspec.lock`; Dependabot alerts cover all hosted packages.                                                                                    |
| Where do native Android vulnerabilities come from?        | The `Dependency Submission` workflow submits the playground app's release runtime classpath to the dependency graph, so Dependabot alerts cover it.                                      |
| What is deliberately not covered?                         | Gradle build tooling (Android Gradle Plugin internals, plugin classpaths). See [Scope](#scope).                                                                                          |
| Is anything dismissed automatically?                      | No. Alert dismissal is a human decision in GitHub.                                                                                                                                       |

## Inventory

### SDK runtime (what consumers get)

`packages/formbricks/pubspec.yaml` depends on `http`, `shared_preferences`,
`clock`, `webview_flutter`, `webview_flutter_android`, `url_launcher` and
`connectivity_plus`. Everything resolves through the single workspace lockfile
`pubspec.lock`, which GitHub's dependency graph parses automatically.

Four of those plugins ship Android code with their own Maven dependencies
(`connectivity_plus`, `shared_preferences_android`, `url_launcher_android`,
`webview_flutter_android`: AndroidX libraries such as `androidx.webkit`,
`androidx.core`, `androidx.datastore`). An app that uses the SDK resolves these
in its own Gradle build, together with its other dependencies, so its final
versions can differ from ours. The playground app's resolution is the closest
proxy we have.

### Native

| Platform | Dependencies                                                                                                                                                                                                                              | Coverage                                        |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Android  | `apps/playground/android` (Gradle, Android Gradle Plugin, Kotlin) plus the plugin projects above. About 90 Maven artifacts on the release runtime classpath.                                                                              | `Dependency Submission` workflow (see below)    |
| iOS      | Swift Package Manager (generated `FlutterGeneratedPluginSwiftPackage`); no `Podfile`, no committed `Package.resolved`. The four iOS plugins' `Package.swift` files depend on nothing third-party (only Flutter's own `FlutterFramework`). | Nothing to submit; no third-party iOS libraries |

### Build, test and publish

| Item                              | Where                                               | Covered by                                    |
| --------------------------------- | --------------------------------------------------- | --------------------------------------------- |
| Pub dev tooling (Melos, lints, …) | `pubspec.lock`                                      | GitHub dependency graph (Pub)                 |
| GitHub Actions                    | `.github/workflows` (pinned to commit SHAs)         | Dependabot `github-actions`                   |
| Gradle plugin versions            | `apps/playground/android/settings.gradle.kts`       | Dependabot `gradle`                           |
| Gradle wrapper                    | `gradle-wrapper.jar`                                | Wrapper validation in `Dependency Submission` |
| Flutter SDK, `pana`, `prettier`   | `.fvmrc`; `make pana-install`; `npx prettier@3.6.2` | Not scanned (CI-only, or pinned by hand)      |

`apps/playground` is `publish_to: none`; it is not part of the pub.dev release.
The release workflow formats, analyzes, tests and publishes the Dart package and
does not run Gradle.

## How Android coverage works

`.github/workflows/dependency-submission.yml` runs on pushes to `main`, weekly
(to refresh the resolution) and on demand:

1. Sets up JDK 17 and the pinned Flutter SDK, and runs `make deps-lockfile`
   (Gradle needs the `local.properties` and plugin list it writes).
2. Validates the Gradle wrapper, then has Gradle resolve the playground build and
   records the result with the
   [Gradle dependency-submission action](https://github.com/gradle/actions/blob/main/docs/dependency-submission.md).
3. Checks the snapshot and fails the run instead of submitting if it is for a
   different commit or ref, contains fewer than 50 components, or lacks
   `androidx.webkit` (the SDK's WebView dependency).
4. Uploads the snapshot as `dependency-snapshot-<sha>` (90 days), which ties
   exactly what was submitted to the commit.
5. On the default branch, submits it to GitHub's Dependency Submission API.
   Run from another branch, the workflow stops after step 4 (a dry run).

A failed run means the Android part of the graph may be stale. Treat a failing
`Dependency Submission` run as an open security task.

## Scope

The snapshot contains only the playground app's `releaseRuntimeClasspath`
(`dependency-graph-include-projects: ":app"` and
`dependency-graph-include-configurations: "^releaseRuntimeClasspath$"`). That is
the native code that is compiled into an app, which is what an SDK user is
exposed to. Debug and test scaffolding and Gradle's own build tooling are
excluded, so they raise no alerts.

At the time this was set up, the excluded build tooling included advisories
rated High and Critical in Android Gradle Plugin internals (netty, bouncycastle
and similar). They affect the machines that build the app, not the built app.
If build-environment exposure becomes a concern, remove the
`dependency-graph-include-configurations` input; expect many alerts that are
resolved only by upgrading the Android Gradle Plugin.

## Handling findings

Findings appear as Dependabot alerts (Security tab) for the default branch, and
as a failing `Dependency Review` check when a pull request introduces a
High/Critical vulnerability in Pub packages.

For each High/Critical alert, a person decides:

1. **Locate it.** For a Maven artifact, from `apps/playground/android` after
   `make deps-lockfile`:

   ```bash
   ./gradlew :app:dependencyInsight --configuration releaseRuntimeClasspath --dependency <group:artifact>
   ```

   For a Pub package, check `pubspec.lock` (`direct main`, `direct dev` or
   `transitive`).

2. **Assess reachability.** It is a runtime exposure for SDK users if it is on
   the release runtime classpath or a `direct main`/transitive Pub dependency of
   `formbricks`. Dev-only packages affect our tooling, not consumers.
3. **Fix or accept.** Bump the dependency (a Dependabot PR, a plugin update, or a
   Gradle dependency constraint), or dismiss the alert in GitHub with an accurate
   reason and a note on who decided. Nothing in this repository dismisses or
   accepts a finding automatically.

## Before a release

Dependabot alerts describe the default branch, so check them at the commit you
release:

1. The latest `Dependency Submission` run on `main` is green and less than a week
   old (the weekly run keeps it fresh), so the Android graph is current.
2. No open High/Critical Dependabot alerts remain for the Pub or Gradle
   ecosystems, or each is a recorded decision from [Handling findings](#handling-findings).

## Limitations

- **Default-branch snapshots only.** `Dependency Review` sees Pub changes on pull
  requests but not Gradle changes. Submitting snapshots for pull requests needs a
  privileged job that verifies the snapshot's commit and ref against the pull
  request, since a forged snapshot could overwrite the default-branch graph.
- **Consumers' builds differ.** The graph reflects the playground's resolution,
  not a particular customer's app.
- **iOS** has no third-party native dependencies today. If a plugin adds a
  CocoaPod or Swift package, commit `Podfile.lock` or `Package.resolved` so the
  graph can see it.
- **Not scanned:** the Flutter SDK, `pana`, `prettier` and its npm dependencies,
  and CI runner images.
