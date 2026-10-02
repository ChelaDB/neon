from __future__ import annotations

from typing import TYPE_CHECKING

import pytest
from werkzeug.wrappers.response import Response

if TYPE_CHECKING:
    from typing import Any

    from fixtures.httpserver import ListenAddress
    from fixtures.neon_fixtures import VanillaPostgres
    from pytest_httpserver import HTTPServer
    from werkzeug.wrappers.request import Request

ENDPOINT = "/test/roles_and_databases"


@pytest.mark.parametrize(
    "statements,expected",
    [
        # A rename plus PASSWORD NULL carries an explicit JSON null (and no encrypted_password).
        (
            "ALTER ROLE a RENAME TO b; ALTER ROLE b PASSWORD NULL",
            {"roles": [{"op": "set", "name": "b", "old_name": "a", "password": None}]},
        ),
        # PASSWORD NULL before the rename gives the same payload.
        (
            "ALTER ROLE a PASSWORD NULL; ALTER ROLE a RENAME TO b",
            {"roles": [{"op": "set", "name": "b", "old_name": "a", "password": None}]},
        ),
        # A plain rename sends only old_name and name (no password key).
        (
            "ALTER ROLE a RENAME TO b",
            {"roles": [{"op": "set", "name": "b", "old_name": "a"}]},
        ),
        # PASSWORD NULL alone keeps today's payload (no password key).
        (
            "ALTER ROLE a PASSWORD NULL",
            {"roles": [{"op": "set", "name": "a"}]},
        ),
    ],
    ids=["rename_then_null", "null_then_rename", "plain_rename", "null_alone"],
)
def test_ddl_forwarding_rename_password_null(
    httpserver: HTTPServer,
    vanilla_pg: VanillaPostgres,
    httpserver_listen_address: ListenAddress,
    statements: str,
    expected: dict[str, Any],
):
    (host, port) = httpserver_listen_address
    received: list[Any] = []

    def handler(request: Request) -> Response:
        received.append(request.json)
        return Response(status=200)

    httpserver.expect_request(ENDPOINT, method="PATCH").respond_with_handler(handler)
    vanilla_pg.configure(
        [
            f"neon.console_url=http://{host}:{port}{ENDPOINT}",
            "shared_preload_libraries = 'neon'",
        ]
    )
    vanilla_pg.start()

    # Set up the role without forwarding, then clear what was received.
    vanilla_pg.safe_psql("SET neon.forward_ddl = false; CREATE ROLE a PASSWORD 'x'")
    received.clear()

    with vanilla_pg.cursor() as cur:
        cur.execute("BEGIN")
        for stmt in statements.split(";"):
            cur.execute(stmt)
        cur.execute("COMMIT")

    assert received == [expected]
