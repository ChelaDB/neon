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
