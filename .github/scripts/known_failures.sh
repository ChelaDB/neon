#!/usr/bin/env bash
# Turns test_runner/known_failures.txt into pytest `--deselect` arguments,
# printed one argument per line, so a caller can do:
#   mapfile -t deselect < <(.github/scripts/known_failures.sh)
#   ./scripts/pytest ... "${deselect[@]}"
#
# Usage: known_failures.sh [FILE]
# FILE defaults to $KNOWN_FAILURES_FILE, then to test_runner/known_failures.txt
# at the repository root.
#
# Format: one `<nodeid>  # <reason>` per line; blank lines and lines starting
# with `#` are ignored. An entry without a reason is an error.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
file="${1:-${KNOWN_FAILURES_FILE:-$root/test_runner/known_failures.txt}}"

if [[ ! -f "$file" ]]; then
    echo "known_failures.sh: $file not found" >&2
    exit 1
fi

lineno=0
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
    printf -- '--deselect\n%s\n' "$nodeid"
done <"$file"
