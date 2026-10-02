#!/usr/bin/env bash
# Self-test for the pure logic of publish-dev.sh (argument parsing, tags, the build-tools
# tag, submodule status, login detection, digest parsing, the existing-tag check). It sources
# the script, which does nothing when sourced. Run from anywhere:
#   .github/scripts/publish-dev_test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=publish-dev.sh
source "$here/publish-dev.sh"

failures=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# expect <name> <expected> <actual>
expect() {
    if [[ "$2" == "$3" ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1: expected [$2], got [$3]"
        failures=$((failures + 1))
    fi
}

# expect_ok / expect_fail <name> <command...>
expect_ok() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then echo "ok: $name"; else echo "FAIL: $name: expected success"; failures=$((failures + 1)); fi
}
expect_fail() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then echo "FAIL: $name: expected failure"; failures=$((failures + 1)); else echo "ok: $name"; fi
}

# parse <args...>: prints the resulting settings on one line.
parse() {
    (
        parse_args "$@" || exit 1
        echo "no_push=$NO_PUSH only=$ONLY dirty=$ALLOW_DIRTY unpushed=$ALLOW_UNPUSHED force=$FORCE_RETAG"
    )
}
expect "defaults" "no_push=0 only= dirty=0 unpushed=0 force=0" "$(parse)"
expect "all flags" "no_push=1 only=compute dirty=1 unpushed=1 force=1" \
    "$(parse --no-push --only compute --allow-dirty --allow-unpushed --force-retag)"
expect "only storage" "no_push=0 only=storage dirty=0 unpushed=0 force=0" "$(parse --only storage)"
expect_fail "only needs a value" parse --only
expect_fail "only rejects other names" parse --only nope
expect_fail "unknown argument" parse --bogus
expect "help returns 2" "2" "$(
    parse_args --help >/dev/null 2>&1
    echo $?
)"

# sha12
sha=7dc4d86b7d48aabbccddeeff00112233445566ff
expect "sha12" "7dc4d86b7d48" "$(sha12 "$sha")"

# image refs
expect "storage ref" "ghcr.io/cheladb/neon-storage:7dc4d86b7d48-dev" "$(image_ref storage 7dc4d86b7d48)"
expect "compute ref" "ghcr.io/cheladb/neon-compute-v17:7dc4d86b7d48-dev" "$(image_ref compute 7dc4d86b7d48)"
expect_fail "unknown image name" image_ref other 7dc4d86b7d48

# build-tools tag: first 12 hex of sha256sum build-tools/Dockerfile
mkdir -p "$tmp/root/build-tools"
printf 'FROM scratch\n' >"$tmp/root/build-tools/Dockerfile"
expected="$(sha256sum "$tmp/root/build-tools/Dockerfile" | cut -c1-12)"
expect "build-tools tag" "$expected" "$(build_tools_tag "$tmp/root")"
expect "build-tools tag has 12 hex" "12" "$(build_tools_tag "$tmp/root" | tr -d '\n' | wc -c)"

# submodule status: any '-', '+' or 'U' prefix is a failure
ok_status=" 0ce4410764df1a67931de1036e45704f1798d14f vendor/postgres-v14 (heads/x)
 473d64ac837c741c2cbb2cbd2e8e6c80e47f3d8d vendor/postgres-v17 (heads/y)"
expect_ok "submodules clean" submodules_ok "$ok_status"
expect_fail "submodule uninitialised" submodules_ok "-0ce4410764df1a67931de1036e45704f1798d14f vendor/postgres-v14"
expect_fail "submodule moved" submodules_ok "+0ce4410764df1a67931de1036e45704f1798d14f vendor/postgres-v14 (x)"
expect_fail "submodule conflict" submodules_ok "U0ce4410764df1a67931de1036e45704f1798d14f vendor/postgres-v14"
expect_fail "no submodules at all" submodules_ok ""

# ghcr.io login detection
printf '{"auths":{"ghcr.io":{"auth":"x"}}}\n' >"$tmp/auths.json"
printf '{"auths":{"https://index.docker.io/v1/":{}}}\n' >"$tmp/other.json"
printf '{"credHelpers":{"ghcr.io":"pass"}}\n' >"$tmp/helper.json"
printf '{"credsStore":"desktop"}\n' >"$tmp/store.json"
expect_ok "login in auths" ghcr_login_present "$tmp/auths.json"
expect_ok "login via credHelpers" ghcr_login_present "$tmp/helper.json"
expect_ok "login via credsStore" ghcr_login_present "$tmp/store.json"
expect_fail "no ghcr login" ghcr_login_present "$tmp/other.json"
expect_fail "no config file" ghcr_login_present "$tmp/missing.json"

# digest from `docker buildx imagetools inspect` output
inspect_out="Name:      ghcr.io/cheladb/neon-storage:7dc4d86b7d48-dev
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
"
expect "digest parse" "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" \
    "$(digest_from_inspect "$inspect_out")"
expect_fail "digest parse of garbage" digest_from_inspect "nothing here"
expect "pin form" "ghcr.io/cheladb/neon-compute-v17:7dc4d86b7d48-dev@sha256:abc" \
    "$(pin_ref ghcr.io/cheladb/neon-compute-v17:7dc4d86b7d48-dev sha256:abc)"

# existing-tag check, with `docker` stubbed
# shellcheck disable=SC2329 # called by tag_exists
docker() { [[ "$*" == "buildx imagetools inspect ghcr.io/x/exists:1" ]]; }
expect_ok "tag_exists true" tag_exists ghcr.io/x/exists:1
expect_fail "tag_exists false" tag_exists ghcr.io/x/missing:1
FORCE_RETAG=0
expect_fail "refuses existing tag" check_tag_free ghcr.io/x/exists:1
expect_ok "free tag passes" check_tag_free ghcr.io/x/missing:1
FORCE_RETAG=1
expect_ok "force-retag allows existing tag" check_tag_free ghcr.io/x/exists:1
unset -f docker

if ((failures > 0)); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
