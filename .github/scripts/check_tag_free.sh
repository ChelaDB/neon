#!/usr/bin/env bash
# Fails when any of the given image tags already exists in the registry, so a CI run cannot
# retag an image published from a developer machine (published tags are pinned by digest in
# chelabase). Set FORCE_RETAG=true to skip the check.
#
#   FORCE_RETAG=false .github/scripts/check_tag_free.sh <ref>...
#
# Exit codes: 0 all tags free (or forced), 1 a tag exists, 2 usage.
set -uo pipefail

if (($# == 0)); then
    echo "usage: check_tag_free.sh <ref>..." >&2
    exit 2
fi
if [[ "${FORCE_RETAG:-false}" == true ]]; then
    echo "check_tag_free: force_retag is set, not checking: $*"
    exit 0
fi
rc=0
for ref in "$@"; do
    if docker buildx imagetools inspect "$ref" >/dev/null 2>&1; then
        echo "check_tag_free: the tag $ref already exists in the registry (published tags are pinned by digest elsewhere); run with force_retag=true to overwrite it" >&2
        rc=1
    fi
done
exit "$rc"
