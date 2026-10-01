#!/usr/bin/env bash
# Custom `shell:` for steps of jobs that run inside the build-tools image:
#
#   defaults: { run: { shell: "bash .github/scripts/as-nonroot.sh {0}" } }
#
# Why: the job container starts as root (`--user root`), because the workspace
# that GitHub bind-mounts belongs to the host runner (uid 1001) while the
# image's toolchain lives under the `nonroot` user (uid 1000), and initdb and
# Postgres refuse to run as root. This wrapper, running as root, hands the
# workspace and the caches restored by actions over to `nonroot`, makes the
# runner's command files writable, then runs the step script as `nonroot`.
set -euo pipefail

script="$1"

for f in "${GITHUB_ENV:-}" "${GITHUB_OUTPUT:-}" "${GITHUB_PATH:-}" \
    "${GITHUB_STEP_SUMMARY:-}" "${GITHUB_STATE:-}"; do
    if [[ -n "$f" && -e "$f" ]]; then chmod a+rw "$f"; fi
done
chmod a+r "$script"

for d in "$GITHUB_WORKSPACE" /home/nonroot/.cargo /home/nonroot/.cache /tmp/neon; do
    if [[ -e "$d" ]]; then
        find "$d" -xdev ! -user nonroot -exec chown -h nonroot:nonroot {} +
    fi
done

if command -v setpriv >/dev/null; then
    exec setpriv --reuid=nonroot --regid=nonroot --init-groups \
        env HOME=/home/nonroot USER=nonroot bash -euxo pipefail "$script"
fi
exec runuser -u nonroot -m -- env HOME=/home/nonroot USER=nonroot bash -euxo pipefail "$script"
