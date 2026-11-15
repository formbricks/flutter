#!/usr/bin/env bash
# Usage: prepend_changelog.sh <CHANGELOG.md> <version> <notes.md> <release-url>
#
# Adds the GitHub release notes for <version> to <CHANGELOG.md> as its newest
# "## <version>" entry, so the changelog tab on pub.dev shows them. The entry
# goes above the first existing "## " entry, below the file's intro.
#
# The release workflow runs this in its checkout only: on main, CHANGELOG.md
# keeps the history up to 1.3.1 and points to GitHub Releases for later ones.
set -euo pipefail

changelog="${1:?usage: prepend_changelog.sh <CHANGELOG.md> <version> <notes.md> <release-url>}"
version="${2:?version is required}"
notes="${3:?notes file is required}"
release_url="${4:?release url is required}"

# The notes, with headings demoted so the shallowest one becomes "###" and
# nests under the "## <version>" heading. Lines inside fenced code are kept.
demoted_notes() {
  awk '
    function is_fence(line) { return line ~ /^[ ]{0,3}(```|~~~)/ }
    function level(line) { match(line, /^#+/); return RLENGTH }
    NR == FNR {
      if (is_fence($0)) in_code = !in_code
      else if (!in_code && $0 ~ /^#{1,6}[ \t]/) {
        l = level($0)
        if (min == 0 || l < min) min = l
      }
      next
    }
    FNR == 1 { in_code = 0; shift = (min > 0 && min < 3) ? 3 - min : 0 }
    {
      if (is_fence($0)) in_code = !in_code
      else if (!in_code && shift > 0 && $0 ~ /^#{1,6}[ \t]/) {
        prefix = ""
        for (i = 0; i < shift; i++) prefix = prefix "#"
        $0 = prefix $0
      }
      print
    }
  ' "$clean" "$clean"
}

# A re-run of the release, or a version written up by hand, keeps its entry.
if grep -qxF "## $version" "$changelog"; then
  echo "$changelog already has a $version entry; leaving it as is."
  exit 0
fi

clean="$(mktemp)"
entry="$(mktemp)"
out="$(mktemp)"
trap 'rm -f "$clean" "$entry" "$out"' EXIT

# Notes edited in the GitHub UI can carry CRLF line endings and blank edges.
tr -d '\r' < "$notes" | awk '
  NF { while (blanks > 0) { print ""; blanks-- }; print; started = 1; next }
  started { blanks++ }
' > "$clean"

{
  printf '## %s\n\n' "$version"
  if [[ -s $clean ]]; then
    demoted_notes
  else
    printf -- '- See the [GitHub release](%s).\n' "$release_url"
  fi
} > "$entry"

# Insert above the first entry, or append when there is none yet.
awk -v entry="$entry" '
  function print_entry() { while ((getline line < entry) > 0) print line }
  !inserted && /^## / { print_entry(); print ""; inserted = 1 }
  { print }
  END { if (!inserted) { print ""; print_entry() } }
' "$changelog" > "$out"
cat "$out" > "$changelog"

echo "Added the $version release notes to $changelog."
