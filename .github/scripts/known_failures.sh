#!/usr/bin/env bash
# Turns test_runner/known_failures.txt into pytest `--deselect` arguments,
# printed one argument per line, so a caller can do:
#   .github/scripts/known_failures.sh >"$list"   # fails the caller under `set -e`
#   mapfile -t deselect <"$list"
#   ./scripts/pytest ... "${deselect[@]}"
# (not `mapfile < <(...)`: that ignores the script's exit status).
#
# Usage: known_failures.sh [FILE...]
# Several files are merged in argument order (scripts/ci-local.sh passes
# test_runner/known_failures.txt and test_runner/known_failures.local.txt).
# With no FILE the default is $KNOWN_FAILURES_FILE, then
# test_runner/known_failures.txt at the repository root. A listed file that
# does not exist is an error, never skipped: skipping would silently run
# tests that are quarantined.
#
# Format: one `<nodeid>  # <reason>` per line; blank lines and lines starting
# with `#` are ignored. An entry without a reason, or without `::` (not a
# node id: a bare path would deselect a whole file), is an error.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if (($# > 0)); then
    files=("$@")
else
    files=("${KNOWN_FAILURES_FILE:-$root/test_runner/known_failures.txt}")
fi

parse_file() {
    local file="$1" line trimmed nodeid reason lineno=0
    if [[ ! -f "$file" ]]; then
        echo "known_failures.sh: $file not found" >&2
        exit 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        nodeid="${trimmed%%#*}"
        nodeid="${nodeid%"${nodeid##*[![:space:]]}"}"
        reason=""
        [[ "$trimmed" == *#* ]] && reason="${trimmed#*#}"
        reason="${reason//[[:space:]]/}"
        if [[ -z "$reason" ]]; then
            echo "known_failures.sh: $file:$lineno: '$nodeid' has no '# reason'" >&2
            exit 1
        fi
        if [[ "$nodeid" != *::* ]]; then
            echo "known_failures.sh: $file:$lineno: '$nodeid' is not a pytest node id (no '::')" >&2
            exit 1
        fi
        printf -- '--deselect\n%s\n' "$nodeid"
    done <"$file"
}

for f in "${files[@]}"; do
    parse_file "$f"
done
