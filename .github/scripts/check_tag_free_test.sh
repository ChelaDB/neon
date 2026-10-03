#!/usr/bin/env bash
# Self-test for check_tag_free.sh, with a fake `docker` on PATH. Run from anywhere:
#   .github/scripts/check_tag_free_test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

# The fake docker: `buildx imagetools inspect <ref>` succeeds when <ref> is listed in $FAKE_EXISTING.
cat >"$tmp/docker" <<'FAKE'
#!/usr/bin/env bash
ref="${*: -1}"
[[ " ${FAKE_EXISTING:-} " == *" $ref "* ]]
FAKE
chmod +x "$tmp/docker"

# run <force_retag> <existing refs> <refs...>: prints the exit code.
run() {
    local force="$1" existing="$2"
    shift 2
    PATH="$tmp:$PATH" FAKE_EXISTING="$existing" FORCE_RETAG="$force" "$here/check_tag_free.sh" "$@" >/dev/null 2>&1
    echo $?
}

expect() {
    if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1: expected [$2], got [$3]"; failures=$((failures + 1)); fi
}

a=ghcr.io/chelabase/neon-storage:abc-dev
b=ghcr.io/chelabase/neon-compute-v17:abc-dev
expect "free tag passes" 0 "$(run false "" "$a")"
expect "existing tag fails" 1 "$(run false "$a" "$a")"
expect "one of two existing fails" 1 "$(run false "$b" "$a" "$b")"
expect "force_retag=true passes over an existing tag" 0 "$(run true "$a" "$a")"
expect "force_retag=false (default) still fails" 1 "$(run "" "$a" "$a")"
expect "no refs is a usage error" 2 "$(run false "")"

if ((failures > 0)); then echo "$failures failure(s)"; exit 1; fi
echo "all passed"
