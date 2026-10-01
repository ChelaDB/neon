#!/usr/bin/env bash
# Self-test for known_failures.sh (plain bash, no bats). Run from anywhere:
#   .github/scripts/known_failures_test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/known_failures.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0

# check <name> <file content> <expected args, space-joined>
check() {
    local name="$1" content="$2" expected="$3" actual
    printf '%s' "$content" >"$tmp/kf.txt"
    if ! actual="$("$script" "$tmp/kf.txt" | paste -sd' ' -)"; then
        echo "FAIL: $name: script exited non-zero"
        failures=$((failures + 1))
        return
    fi
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $name: expected [$expected], got [$actual]"
        failures=$((failures + 1))
        return
    fi
    echo "ok: $name"
}

# check_fails <name> <file content>: the script must exit non-zero.
check_fails() {
    local name="$1" content="$2"
    printf '%s' "$content" >"$tmp/kf.txt"
    if "$script" "$tmp/kf.txt" >/dev/null 2>&1; then
        echo "FAIL: $name: expected a non-zero exit"
        failures=$((failures + 1))
        return
    fi
    echo "ok: $name"
}

check "empty file gives no args" "" ""
check "one entry" $'a::b  # x\n' "--deselect a::b"
check "comment and blank lines are ignored" \
    $'# header comment\n\n   \n  # indented comment\na::b  # x\n\n' \
    "--deselect a::b"
check "several entries keep their order" \
    $'test_runner/regress/test_a.py::test_one[release-pg17]  # needs real S3\nt.py::two  # timing on 4 vCPU (passed 0/3)\n' \
    "--deselect test_runner/regress/test_a.py::test_one[release-pg17] --deselect t.py::two"
check "no trailing newline" "a::b  # x" "--deselect a::b"
check_fails "an entry without a reason is rejected" $'a::b\n'
check_fails "an entry with an empty reason is rejected" $'a::b  #   \n'

# Path from the environment instead of an argument.
printf 'env::case  # x\n' >"$tmp/env.txt"
if [[ "$(KNOWN_FAILURES_FILE="$tmp/env.txt" "$script" | paste -sd' ' -)" == "--deselect env::case" ]]; then
    echo "ok: KNOWN_FAILURES_FILE overrides the default path"
else
    echo "FAIL: KNOWN_FAILURES_FILE overrides the default path"
    failures=$((failures + 1))
fi

if "$script" "$tmp/does-not-exist.txt" >/dev/null 2>&1; then
    echo "FAIL: a missing file must be an error"
    failures=$((failures + 1))
else
    echo "ok: a missing file is an error"
fi

# The committed list itself must parse.
if "$script" >/dev/null; then
    echo "ok: the committed test_runner/known_failures.txt parses"
else
    echo "FAIL: the committed test_runner/known_failures.txt does not parse"
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
