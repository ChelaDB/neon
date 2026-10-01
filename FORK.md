# ChelaDB Fork of Neon

This is ChelaDB's hard fork of [neondatabase/neon](https://github.com/neondatabase/neon), based on upstream commit fa504217 (2026-08-31, main HEAD when upstream froze). PostgreSQL sources are pulled from [ChelaDB/postgres](https://github.com/ChelaDB/postgres) branches `REL_14_STABLE_cheladb` through `REL_17_STABLE_cheladb`.

## License

Apache License 2.0, unchanged. NOTICE file and upstream copyright are retained.

## Policy

We do not rewrite the core engine (pageserver, safekeepers, or Neon's PostgreSQL patches). We replace specific components only when our needs genuinely differ from upstream. Performance improvements must have supporting profiling evidence.

## PostgreSQL Minors

When a new PostgreSQL minor release becomes available:

1. Merge the `postgres/postgres REL_x_y` tag into `REL_x_STABLE_cheladb` in ChelaDB/postgres (pull request, run `make check`).
2. Bump the submodule commit here and update `vendor/revisions.json` (pull request, run full regression CI).
3. Process oldest minors first.

Neon's own `REL_x_STABLE_neon` branches remain read-only references; we do not track them.

## Tests

CI quarantines known test failures in `test_runner/known_failures.txt`, each with a reason. This list may only shrink.

## Checks

The gate for every PR is `.github/scripts/ci-local.sh`: lint (self-tests, actionlint, fmt, clippy, cargo deny, ruff, mypy), build, and the Rust tests. It runs on a developer machine inside the same `ghcr.io/cheladb/neon-build-tools` image as `.github/workflows/pr.yml` (needs `docker login ghcr.io` once), with caches in the Docker volumes `chela-neon-cargo` and `chela-neon-target` and logs under `.ci-local/` (git-ignored). Use `--pg v14|v15|v16` for the older majors.

Per-PR GitHub CI is manual: `pr.yml` is `workflow_dispatch` only until the fork is integrated, and branch protection on `main` requires a PR but no status check.

Neon's pytest regression suite is opt-in and required for no PR: `ci-local.sh --regress [-k <expr>] [-n <workers>]` runs it for a targeted check, for example to debug one test. When an image changes, cheladb's own e2e covers the parts we use. The regression run deselects `test_runner/known_failures.txt` (fails on GitHub's runners too) and `test_runner/known_failures.local.txt` (fails only in the local run); both use the `<nodeid>  # <reason>` format and may only shrink.
