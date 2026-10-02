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
# A pytest node id always has `::`; a bare path would silently deselect a whole file.
check_fails "an entry without :: is rejected" $'test_runner/regress/test_a.py  # whole file\n'
check_fails "a typo without :: is rejected" $'test_one  # not a node id\n'

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

# Several files are merged in argument order (known_failures.txt, then known_failures.local.txt).
printf 'one::a  # x\n' >"$tmp/m1.txt"
printf '# local\ntwo::b  # y\n' >"$tmp/m2.txt"
if [[ "$("$script" "$tmp/m1.txt" "$tmp/m2.txt" | paste -sd' ' -)" == "--deselect one::a --deselect two::b" ]]; then
    echo "ok: two files are merged in argument order"
else
    echo "FAIL: two files are merged in argument order"
    failures=$((failures + 1))
fi

if "$script" "$tmp/m1.txt" "$tmp/does-not-exist.txt" >/dev/null 2>&1; then
    echo "FAIL: a missing second file must be an error"
    failures=$((failures + 1))
else
    echo "ok: a missing second file is an error"
fi

# An invalid entry in the second file is rejected and names that file.
printf 'bad::entry\n' >"$tmp/m3.txt"
if err="$("$script" "$tmp/m1.txt" "$tmp/m3.txt" 2>&1 >/dev/null)"; then
    echo "FAIL: an entry without a reason in the second file must be an error"
    failures=$((failures + 1))
elif [[ "$err" == *m3.txt* ]]; then
    echo "ok: an entry without a reason in the second file is rejected, naming the file"
else
    echo "FAIL: the error for the second file must name it: $err"
    failures=$((failures + 1))
fi

# The committed list itself must parse.
if "$script" >/dev/null; then
    echo "ok: the committed test_runner/known_failures.txt parses"
else
    echo "FAIL: the committed test_runner/known_failures.txt does not parse"
    failures=$((failures + 1))
fi

# The committed local list parses together with the shared one.
root="$(cd "$here/../.." && pwd)"
if "$script" "$root/test_runner/known_failures.txt" "$root/test_runner/known_failures.local.txt" >/dev/null; then
    echo "ok: the committed known_failures.txt and known_failures.local.txt parse together"
else
    echo "FAIL: the committed known_failures.txt and known_failures.local.txt do not parse together"
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
