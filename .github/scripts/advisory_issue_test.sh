#!/usr/bin/env bash
# Self-test for advisory_issue.sh (plain bash, no network): `gh` is a stub on
# PATH that records its calls and answers `issue list` from $STUB_OPEN_ISSUES.
# Run from anywhere:
#   .github/scripts/advisory_issue_test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/advisory_issue.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin"
cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records every call; `gh issue list` prints the number(s) in $STUB_OPEN_ISSUES.
printf '%s\n' "$*" >>"$STUB_CALLS"
if [[ "$1 $2" == "issue list" ]]; then
    for n in $STUB_OPEN_ISSUES; do echo "$n"; done
fi
STUB
chmod +x "$tmp/bin/gh"

failures=0

# run_case <open issue numbers> <script args...>: prints the recorded gh calls
# other than `issue list`, one per line.
run_case() {
    local open="$1"
    shift
    : >"$tmp/calls"
    STUB_CALLS="$tmp/calls" STUB_OPEN_ISSUES="$open" PATH="$tmp/bin:$PATH" \
        RUN_URL="https://github.com/ChelaDB/neon/actions/runs/42" "$script" "$@" >/dev/null 2>"$tmp/err" || {
        echo "script exited non-zero: $(cat "$tmp/err")"
        return
    }
    grep -v '^issue list' "$tmp/calls"
}

# expect_match <name> <actual> <grep -E pattern, must match>
expect_match() {
    if grep -Eq -- "$3" <<<"$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1: [$2] does not match /$3/"
        failures=$((failures + 1))
    fi
}

# expect_empty <name> <actual>
expect_empty() {
    if [[ -z "$2" ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1: expected no gh writes, got [$2]"
        failures=$((failures + 1))
    fi
}

# The open-issue lookup must be restricted to open issues (a closed issue must
# never receive the comment). run_case leaves the recorded calls in $tmp/calls.
out="$(run_case "" 1 "RUSTSEC-2026-0001 RUSTSEC-2026-0002")"
if grep -E '^issue list ' "$tmp/calls" | grep -Eq -- '--state open( |$)'; then
    echo "ok: issue list is called with --state open"
else
    echo "FAIL: issue list must be called with --state open: [$(grep '^issue list' "$tmp/calls")]"
    failures=$((failures + 1))
fi

expect_match "failure, no open issue: creates one" "$out" '^issue create .*--title New RustSec advisory'
expect_match "failure, no open issue: body has the run URL" "$out" 'actions/runs/42'
expect_match "failure, no open issue: body has the IDs" "$out" 'RUSTSEC-2026-0001.*RUSTSEC-2026-0002'

out="$(run_case "7" 1 "RUSTSEC-2026-0003")"
expect_match "failure, open issue: comments on it" "$out" '^issue comment 7 '
expect_match "failure, open issue: comment has the run URL and ID" "$out" 'actions/runs/42.*RUSTSEC-2026-0003'
if grep -q '^issue create' <<<"$out"; then
    echo "FAIL: failure, open issue: must not create another issue"
    failures=$((failures + 1))
else
    echo "ok: failure, open issue: creates nothing"
fi

out="$(run_case "" 0 "")"
expect_empty "pass, no open issue: nothing" "$out"
out="$(run_case "7" 0 "")"
expect_empty "pass, open issue: nothing" "$out"

out="$(run_case "" 1 "")"
expect_match "failure without IDs still files an issue" "$out" '^issue create '

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all passed"
