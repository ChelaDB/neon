#!/usr/bin/env bash
# Checks that the dev storage image (built with PG_VERSIONS=v17) holds only Postgres v17.
#   image_variant_test.sh <image>
# Asserts: /usr/local/v17/bin/postgres exists, /usr/local/v14, v15 and v16 do not, and
# /data/postgres_install.tar.gz lists only v17.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <image>" >&2
  exit 2
fi
image="$1"
fail=0

if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "FAIL: image '$image' not found locally (build or pull it first)" >&2
  exit 1
fi

run() { docker run --rm --entrypoint sh "$image" -c "$1"; }

if run 'test -x /usr/local/v17/bin/postgres'; then
  echo "ok: /usr/local/v17/bin/postgres exists"
else
  echo "FAIL: /usr/local/v17/bin/postgres is missing" >&2
  fail=1
fi

for v in v14 v15 v16; do
  if run "test ! -e /usr/local/$v"; then
    echo "ok: /usr/local/$v is absent"
  else
    echo "FAIL: /usr/local/$v exists" >&2
    fail=1
  fi
done

tops="$(run 'tar -tzf /data/postgres_install.tar.gz | cut -d/ -f1 | sort -u' | tr '\n' ' ')"
if [ "$tops" = "v17 " ]; then
  echo "ok: postgres_install.tar.gz lists only v17"
else
  echo "FAIL: postgres_install.tar.gz top-level entries: ${tops:-none}(expected only v17)" >&2
  fail=1
fi

exit "$fail"
