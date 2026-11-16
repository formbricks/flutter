# Releasing the Flutter SDK

The `formbricks` package is published to [pub.dev](https://pub.dev/packages/formbricks)
by the [Release workflow](.github/workflows/release.yml). You publish a GitHub
release; the workflow does the rest.

The steps shared by all Formbricks SDKs, including the manual QA run before a
release, are in the
[SDK QA & Release doc](https://app.notion.com/p/419e5de84a5881cd8091c30193db8607).

## Release a version

1. Run the manual QA described in the SDK QA & Release doc against the
   Formbricks server version you are releasing for.
2. On GitHub, draft a new release from `main`:
   - **Tag:** a new tag named after the version, with no `v` prefix. For
     example `1.4.0`, or `1.4.0-rc.1` for a prerelease.
   - **Notes:** select **Generate release notes**, then edit them. They become
     the changelog entry on pub.dev, so edit them before you publish.
   - Tick **Set as a pre-release** for a version with a `-` suffix, and only
     then. The workflow fails when the box disagrees with the tag.
3. Publish the release. GitHub creates the tag, and the tag push starts the
   Release workflow.
4. Check that the workflow's `Verify on pub.dev` job passed.

Do not bump the version in a PR. `packages/formbricks/pubspec.yaml` on `main`
holds the `0.0.0-dev` placeholder; the workflow writes the version from the tag
into its own checkout only.

## What the workflow does

The workflow runs build, publish, then verify. It does not re-run CI. Every
job checks out the tag, so the scripts come from the tag, not from `main`.

1. `build` checks that the tag is a semver version, writes it into the
   pubspec, and checks that the GitHub release's **Set as a pre-release** box
   matches the tag. It fails when the tag has no GitHub release.
2. `build` asks the pub.dev API whether the version exists. If it does, the
   workflow skips to verify, so **Re-run failed jobs** is always safe.
3. `build` adds the GitHub release notes to `CHANGELOG.md` as the newest
   entry, so the changelog tab on pub.dev shows them. The file in the
   repository is not changed: it keeps the entries up to 1.3.1 and links to
   GitHub Releases.
4. `build` runs `flutter analyze` and `pub publish --dry-run`, then hands the
   versioned pubspec and changelog to `publish`.
5. `publish`, the only job that can get a pub.dev OIDC token, publishes those
   files with `pub publish --force`.
6. `verify` polls the pub.dev API until it serves the version, and fails
   after 15 minutes.

pub.dev treats a version with a `-` suffix as a prerelease by itself. Pub
prefers stable versions, so users get a prerelease when they ask for it, for
example with `formbricks: ^1.4.0-rc.1`.

The release scripts and their tests live in [`tool/release/`](tool/release).
`make script-tests` runs their tests (CI runs it in `unit-tests`).

## Why Flutter triggers on a tag push

The other SDKs publish on the `release: published` event. Flutter publishes on
the tag push instead, because pub.dev only accepts an automated publish from a
GitHub Actions run triggered by pushing a tag that matches the package's tag
pattern. This repo published on the release event until June 2026, and pub.dev
rejected it. Publishing a GitHub release creates its tag, and that tag push runs
the workflow, so the person releasing does the same thing as in the other SDK
repos.

Two consequences:

- Create tags only by publishing a GitHub release. A tag pushed with `git`
  has no release yet, so the workflow fails in `build` without publishing.
- A tag created by a workflow using `GITHUB_TOKEN` does not start other
  workflows, so a release cannot be automated that way.

## Fixing a failed release

- **Failed on the pre-release check:** edit the GitHub release so **Set as a
  pre-release** matches the tag, then re-run the failed jobs.
- **Failed in `build` or `publish`:** if the cause was transient,
  re-run the failed jobs. A re-run uses the code at the tag, so if that code
  is broken, fix it on `main` and release a new version.
- **Failed in `verify`:** pub.dev may be slow. Re-run the failed job.
- **Wrong version published:** pub.dev never takes a version down. Retract it
  on pub.dev (possible for 7 days) and release a new version.

Never delete or move a published tag.

## One-time setup on pub.dev

On the package's admin page on pub.dev, automated publishing from GitHub
Actions must be enabled for `formbricks/flutter` with the tag pattern
`{{version}}`. The workflow writes the tag into the pubspec, so the published
version always matches the tag. The workflow needs no secrets.
