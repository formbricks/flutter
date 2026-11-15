#!/usr/bin/env bash
# Tests for prepend_changelog.sh. Run: bash tool/release/prepend_changelog_test.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/prepend_changelog.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
url="https://github.com/formbricks/flutter/releases/tag/1.4.0"

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# Compares the changelog against the expected text, showing a diff on mismatch.
expect_changelog() {
  local name="$1" expected="$2"
  if ! diff -u <(printf '%s\n' "$expected") "$work/CHANGELOG.md" > "$work/diff"; then
    fail "$name"
    cat "$work/diff"
  fi
}

# A changelog shaped like packages/formbricks/CHANGELOG.md on main.
main_changelog() {
  cat > "$work/CHANGELOG.md" <<'MD'
# Changelog

Release notes live on GitHub Releases.

## 1.3.1

- Raise the `shared_preferences` floor to ^2.5.6.
MD
}

# --- The release notes go in as the newest entry, below the intro. ---
main_changelog
cat > "$work/notes.md" <<'MD'
## What's Changed

- feat: add setLanguage by @someone in https://github.com/formbricks/flutter/pull/90
MD
bash "$script" "$work/CHANGELOG.md" "1.4.0" "$work/notes.md" "$url" > /dev/null 2>&1 ||
  fail "inserting notes exited non-zero"
expect_changelog "notes are inserted as the newest entry with demoted headings" "# Changelog

Release notes live on GitHub Releases.

## 1.4.0

### What's Changed

- feat: add setLanguage by @someone in https://github.com/formbricks/flutter/pull/90

## 1.3.1

- Raise the \`shared_preferences\` floor to ^2.5.6."

# --- A release with no notes (or no release at all) links to the release. ---
main_changelog
printf ' \n\n' > "$work/notes.md"
bash "$script" "$work/CHANGELOG.md" "1.4.0" "$work/notes.md" "$url" > /dev/null 2>&1 ||
  fail "empty notes exited non-zero"
expect_changelog "empty notes become a link to the GitHub release" "# Changelog

Release notes live on GitHub Releases.

## 1.4.0

- See the [GitHub release]($url).

## 1.3.1

- Raise the \`shared_preferences\` floor to ^2.5.6."

# --- A version that already has an entry is left alone. ---
main_changelog
printf -- '- something new\n' > "$work/notes.md"
before="$(cat "$work/CHANGELOG.md")"
bash "$script" "$work/CHANGELOG.md" "1.3.1" "$work/notes.md" "$url" > /dev/null 2>&1 ||
  fail "existing version exited non-zero"
expect_changelog "an existing entry for the version is not duplicated" "$before"

# --- Notes edited in the GitHub UI: CRLF, an H1, and a fenced code block. ---
main_changelog
printf '# Highlights\r\n\r\n```bash\r\n# not a heading\r\n```\r\n\r\n## What'"'"'s Changed\r\n* fix: x\r\n' > "$work/notes.md"
bash "$script" "$work/CHANGELOG.md" "1.4.0" "$work/notes.md" "$url" > /dev/null 2>&1 ||
  fail "CRLF notes exited non-zero"
expect_changelog "CRLF is stripped and headings nest below the version, code is untouched" "# Changelog

Release notes live on GitHub Releases.

## 1.4.0

### Highlights

\`\`\`bash
# not a heading
\`\`\`

#### What's Changed
* fix: x

## 1.3.1

- Raise the \`shared_preferences\` floor to ^2.5.6."

# --- A changelog with no entries yet gets the notes below its intro. ---
printf '# Changelog\n\nRelease notes live on GitHub Releases.\n' > "$work/CHANGELOG.md"
printf -- '- fix: x\n' > "$work/notes.md"
bash "$script" "$work/CHANGELOG.md" "1.4.0" "$work/notes.md" "$url" > /dev/null 2>&1 ||
  fail "changelog without entries exited non-zero"
expect_changelog "notes are appended when there is no entry yet" "# Changelog

Release notes live on GitHub Releases.

## 1.4.0

- fix: x"

# --- A missing notes file is an error, so a broken fetch fails the run. ---
main_changelog
if bash "$script" "$work/CHANGELOG.md" "1.4.0" "$work/missing.md" "$url" > /dev/null 2>&1; then
  fail "a missing notes file was accepted"
fi

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "prepend_changelog: all tests passed"
