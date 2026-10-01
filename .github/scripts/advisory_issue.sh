#!/usr/bin/env bash
# Files the RustSec advisory issue after the scheduled `cargo deny check
# advisories` run (advisories.yml).
#
#   advisory_issue.sh <cargo-deny exit status> "<advisory IDs, space-separated>"
#
# Environment: RUN_URL (the run's URL), GH_TOKEN (for gh; GH_REPO or a checkout
# selects the repository).
#
# Status 0: does nothing. Otherwise: comments on the single open issue titled
# "New RustSec advisory" with the run URL and the IDs, or opens it if none is open.
set -euo pipefail

status="${1:?usage: advisory_issue.sh <status> <ids>}"
ids="${2:-}"
title="New RustSec advisory"

if [[ "$status" == "0" ]]; then
    echo "cargo deny passed; nothing to report"
    exit 0
fi

if [[ -n "$ids" ]]; then
    found="${ids// /, }"
else
    found="none parsed from the output (cargo deny failed for another reason; read the log)"
fi
line="cargo deny check advisories failed in ${RUN_URL:?RUN_URL is not set}. Advisories: ${found}."

# --search narrows the list; the jq filter keeps the exact title only.
number="$(gh issue list --state open --search "in:title \"$title\"" --json number,title \
    --jq ".[] | select(.title == \"$title\") | .number" | head -n1)"

if [[ -n "$number" ]]; then
    gh issue comment "$number" --body "$line"
else
    gh issue create --title "$title" --body "$line Fix by bumping the dependency (preferred) or, for an advisory with no fix, adding its ID to the \`ignore\` list in \`deny.toml\` with a reason. This issue stays open until someone closes it; later failing runs comment here."
fi
