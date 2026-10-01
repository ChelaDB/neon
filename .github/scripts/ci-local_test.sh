#!/usr/bin/env bash
# Self-test for the pure logic of ci-local.sh (argument parsing, the image tag
# and the docker command line). It sources the script, which does nothing when
# sourced. Run from anywhere:
#   .github/scripts/ci-local_test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-local.sh
source "$here/ci-local.sh"

failures=0

# expect <name> <expected> <actual>
expect() {
    if [[ "$2" == "$3" ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1: expected [$2], got [$3]"
        failures=$((failures + 1))
    fi
}

# parse <args...>: prints the resulting settings on one line.
parse() {
    (
        parse_args "$@" || exit 1
        echo "pg=$PG build=$BUILD_TYPE regress=$REGRESS k=$KEXPR n=$WORKERS"
    )
}

expect "defaults (no regression suite)" "pg=v17 build=release regress=0 k= n=6" "$(parse)"
expect "--pg and --build-type" "pg=v16 build=debug regress=0 k= n=6" "$(parse --pg v16 --build-type debug)"
expect "--regress" "pg=v17 build=release regress=1 k= n=6" "$(parse --regress)"
expect "--regress with -k and -n" "pg=v17 build=release regress=1 k=test_a or test_b n=3" "$(parse --regress -k 'test_a or test_b' -n 3)"
expect "-k and -n in either order" "pg=v17 build=release regress=1 k=x n=2" "$(parse -k x -n 2 --regress)"
expect "every major is accepted" "pg=v14 build=release regress=0 k= n=6" "$(parse --pg v14)"

for bad in "--pg v18" "--pg" "--build-type fast" "-n 0" "-n x" "--bogus" "-k" "--quick" "-k x" "-n 3"; do
    # shellcheck disable=SC2086
    if parse $bad >/dev/null 2>&1; then
        echo "FAIL: [$bad] must be rejected"
        failures=$((failures + 1))
    else
        echo "ok: [$bad] is rejected"
    fi
done

# The image tag is the first 12 hex characters of sha256sum build-tools/Dockerfile,
# exactly as pr.yml and build-tools.yml compute it.
root="$(cd "$here/../.." && pwd)"
expected="ghcr.io/cheladb/neon-build-tools:$(sha256sum "$root/build-tools/Dockerfile" | cut -c1-12)"
expect "image name" "$expected" "$(image_name "$root")"

# The docker command line: caches in the two named volumes, never host networking.
cmd="$(docker_args "$root" v17 release lint | paste -sd' ' -)"
if [[ "$cmd" == *chela-neon-cargo* && "$cmd" == *chela-neon-target* ]]; then
    echo "ok: docker args use both named volumes"
else
    echo "FAIL: docker args must use both named volumes: $cmd"
    failures=$((failures + 1))
fi
if [[ "$cmd" != *--network* ]]; then
    echo "ok: docker args do not set --network"
else
    echo "FAIL: docker args must not set --network: $cmd"
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
